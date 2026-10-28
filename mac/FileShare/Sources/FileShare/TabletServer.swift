import FileShareCore
import Foundation
import Network
import UniformTypeIdentifiers

/// Servidor no Wi-Fi: anuncia o Mac por Bonjour (_fileshare._tcp) só quando há um tablet pareado,
/// autentica a conexão com a chave do pareamento e cifra tudo que passa por ela.
final class TabletServer {
    static let serviceType = "_fileshare._tcp"

    enum State: Equatable {
        case unpaired
        case waiting
        case connected(name: String)
        case rejected
        case failed(String)
    }

    /// O que aconteceu com uma cópia do Mac.
    enum Delivery {
        case delivered
        /// Tablet fora: guardada para entregar quando ele reconectar.
        case held
    }

    /// Andamento de um arquivo enviado ao tablet.
    enum FileEvent {
        /// Tablet fora: o arquivo espera na fila e vai quando ele reconectar.
        case queued(name: String)
        case progress(name: String, fraction: Double)
        case delivered(name: String)
        case failed(name: String, reason: String)
    }

    enum SendError: LocalizedError {
        case notConnected, timeout
        case refused(String)

        var errorDescription: String? {
            switch self {
            case .notConnected: "tablet não conectado"
            case .timeout: "o tablet não confirmou a tempo"
            case .refused(let reason): reason
            }
        }
    }

    /// Etapas de uma conexão: AUTH em claro → HELLO cifrado (prova que o tablet tem a chave) → pronto.
    private enum Phase {
        case awaitingAuth
        case awaitingHello
        case ready
    }

    /// Estado de uma conexão; acessado só na fila do servidor.
    private final class Session {
        let conn: NWConnection
        var phase = Phase.awaitingAuth
        var channel: SecureChannel?
        var decoder = FrameDecoder()
        let startedAt = Date()
        var lastSeen = Date()
        var tabletName = "tablet"
        /// Versão e recursos que o tablet anunciou no HELLO (vazio até a 2.3).
        var peer = PeerInfo()
        /// Arquivos do menu Compartilhar ainda chegando, pelo id do FILE.
        var incoming: [Int: IncomingFile] = [:]

        init(_ conn: NWConnection) {
            self.conn = conn
        }
    }

    private static let idleTimeout: TimeInterval = 70 // o tablet manda PING a cada 20 s
    /// Sem notícias há mais que isso, a conexão provavelmente morreu (tablet dormindo):
    /// a cópia é guardada em vez de enviada para o vazio.
    private static let staleAfter: TimeInterval = 30
    private static let ackTimeout: TimeInterval = 8
    private static let handshakeTimeout: TimeInterval = 10
    /// Depois do último pedaço, o tablet ainda grava o arquivo antes de confirmar.
    private static let fileAckTimeout: TimeInterval = 30

    private let queue = DispatchQueue(label: "fileshare.server")
    private let macId: String
    private let macName = Host.current().localizedName ?? "Mac"
    enum Capability {
        /// Aceita HELD do tablet: a cópia que ele guardou enquanto o Mac estava longe.
        static let held = "held"
        /// Mostra a bateria do tablet (BATT) no painel.
        static let battery = "batt"
    }

    /// O que o Mac anuncia no HELLO. Cada recurso novo entra aqui quando estiver pronto.
    static let localInfo = PeerInfo(
        version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev",
        capabilities: [Capability.held, Capability.battery])
    /// Cópia vinda do tablet; copiedAt (ms desde 1970) só vem quando ele a guardou com o Mac longe (HELD).
    private let onReceive: (_ payload: ClipPayload, _ copiedAt: Int64?) -> Void
    private let onState: (State) -> Void
    private let onHeldDelivered: (ClipPayload) -> Void
    private let onFile: (_ url: URL, _ mime: String, _ from: String) -> Void
    private let onFileEvent: (FileEvent) -> Void
    private let onBattery: (_ level: Int, _ charging: Bool) -> Void
    /// Arquivos a enviar ao tablet, um de cada vez; ficam aqui enquanto ele dorme.
    private var outbox: [URL] = []
    private var sendingFile = false
    /// Tudo que vem do menu Compartilhar do tablet fica junto, em Downloads/FileShare.
    static let receivedFolder = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("FileShare", isDirectory: true)
    private var held = HeldClip()
    private var pairingKey: Data?
    private var listener: NWListener?
    /// Tablet autenticado. Uma conexão nova fica como candidata e só substitui esta depois de
    /// provar que tem a chave, para um estranho na rede não conseguir derrubar o tablet.
    private var active: Session?
    private var candidate: Session?
    private var nextId = 1
    private var pending: [Int: (Result<Void, Error>) -> Void] = [:]
    private var watchdog: DispatchSourceTimer?

    init(macId: String,
         onReceive: @escaping (_ payload: ClipPayload, _ copiedAt: Int64?) -> Void,
         onState: @escaping (State) -> Void,
         onHeldDelivered: @escaping (ClipPayload) -> Void,
         onFile: @escaping (_ url: URL, _ mime: String, _ from: String) -> Void,
         onFileEvent: @escaping (FileEvent) -> Void,
         onBattery: @escaping (_ level: Int, _ charging: Bool) -> Void) {
        self.macId = macId
        self.onReceive = onReceive
        self.onState = onState
        self.onHeldDelivered = onHeldDelivered
        self.onFile = onFile
        self.onFileEvent = onFileEvent
        self.onBattery = onBattery
        startWatchdog()
    }

    /// Com chave: anuncia e aceita só quem a tiver. Sem chave (nil): sai da rede.
    /// Trocar a chave derruba a conexão atual, que usava a anterior.
    func setPairingKey(_ key: Data?) {
        queue.async { [self] in
            pairingKey = key
            [candidate, active].compactMap { $0 }.forEach(close)
            if key == nil {
                listener?.cancel()
                listener = nil
                report(.unpaired)
            } else if listener == nil {
                startListener()
            }
        }
    }

    private func startListener() {
        let tcp = NWProtocolTCP.Options()
        tcp.enableKeepalive = true
        tcp.keepaliveIdle = 30
        do {
            let listener = try NWListener(using: NWParameters(tls: nil, tcp: tcp))
            // Nome genérico: o nome do Mac só vai cifrado, depois da autenticação.
            listener.service = NWListener.Service(name: "FileShare", type: Self.serviceType,
                                                  txtRecord: NWTXTRecord(["id": macId]).data)
            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready: self?.report(.waiting)
                case .failed(let error): self?.report(.failed(error.localizedDescription))
                default: break
                }
            }
            listener.newConnectionHandler = { [weak self] conn in self?.accept(conn) }
            listener.start(queue: queue)
            self.listener = listener
        } catch {
            report(.failed(error.localizedDescription))
        }
    }

    private func startWatchdog() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 5, repeating: 5)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            if let c = candidate, Date().timeIntervalSince(c.startedAt) > Self.handshakeTimeout { close(c) }
            if let a = active, Date().timeIntervalSince(a.lastSeen) > Self.idleTimeout { close(a) }
        }
        timer.resume()
        watchdog = timer
    }

    // MARK: Mac → tablet

    func send(_ payload: ClipPayload, completion: @escaping (Result<Delivery, Error>) -> Void) {
        let done: (Result<Delivery, Error>) -> Void = { result in DispatchQueue.main.async { completion(result) } }
        let copiedAt = Date()
        queue.async { [self] in
            guard let session = active, Date().timeIntervalSince(session.lastSeen) <= Self.staleAfter else {
                if let stale = active { close(stale) }
                held.hold(payload, copiedAt: copiedAt)
                return done(.success(.held))
            }
            let id = nextId
            nextId += 1
            pending[id] = { [weak self] result in
                switch result {
                case .success:
                    done(.success(.delivered))
                case .failure:
                    // a conexão morreu no caminho: guarda para quando o tablet voltar
                    self?.held.hold(payload, copiedAt: copiedAt)
                    done(.success(.held))
                }
            }
            write(.clip(id: id, payload: payload), to: session)
            queue.asyncAfter(deadline: .now() + Self.ackTimeout) { [weak self] in
                self?.pending.removeValue(forKey: id)?(.failure(SendError.timeout))
            }
        }
    }

    /// Entrega a cópia guardada logo depois que o tablet se autentica.
    private func deliverHeld(to session: Session) {
        guard let (payload, copiedAt) = held.take(now: Date()) else { return }
        let id = nextId
        nextId += 1
        pending[id] = { [weak self] result in
            switch result {
            case .success: DispatchQueue.main.async { self?.onHeldDelivered(payload) }
            case .failure: self?.held.hold(payload, copiedAt: copiedAt) // tenta na próxima conexão
            }
        }
        write(.held(id: id, copiedAt: Int64(copiedAt.timeIntervalSince1970 * 1000), payload: payload), to: session)
        queue.asyncAfter(deadline: .now() + Self.ackTimeout) { [weak self] in
            self?.pending.removeValue(forKey: id)?(.failure(SendError.timeout))
        }
    }

    // MARK: Arquivos Mac → tablet

    /// Põe arquivos na fila de envio (arrastados ao ícone, escolhidos no menu ou vindos do Finder).
    func sendFiles(_ urls: [URL]) {
        queue.async { [self] in
            for url in urls {
                var isDir: ObjCBool = false
                guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue else {
                    fileEvent(.failed(name: url.lastPathComponent, reason: "pastas não são enviadas"))
                    continue
                }
                outbox.append(url)
            }
            pumpOutbox()
        }
    }

    /// Envia o próximo arquivo da fila, se houver tablet conectado e nada sendo enviado.
    private func pumpOutbox() {
        guard !sendingFile, let url = outbox.first else { return }
        guard let session = active, Date().timeIntervalSince(session.lastSeen) <= Self.staleAfter else {
            if let stale = active { close(stale) }
            outbox.forEach { fileEvent(.queued(name: $0.lastPathComponent)) }
            return
        }
        let name = url.lastPathComponent
        let size = ((try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) as? NSNumber)?.int64Value ?? -1
        guard size >= 0, size <= Wire.maxFileSize, let handle = try? FileHandle(forReadingFrom: url) else {
            outbox.removeFirst()
            fileEvent(.failed(name: name, reason: size > Wire.maxFileSize ? "arquivo maior que 100 MB" : "não consegui ler o arquivo"))
            return pumpOutbox()
        }
        sendingFile = true
        let id = nextId
        nextId += 1
        pending[id] = { [weak self] result in
            guard let self else { return }
            try? handle.close()
            sendingFile = false
            switch result {
            case .success:
                outbox.removeFirst()
                fileEvent(.delivered(name: name))
            case .failure(SendError.refused(let reason)):
                outbox.removeFirst()
                fileEvent(.failed(name: name, reason: reason))
            case .failure:
                // conexão caiu no meio: o arquivo continua na fila para quando o tablet voltar
                fileEvent(.queued(name: name))
                return
            }
            pumpOutbox()
        }
        let mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        write(.file(id: id, size: size, mime: mime, name: name), to: session)
        sendPart(id, handle: handle, sent: 0, size: size, name: name, session: session)
    }

    /// Manda um pedaço e só lê o próximo quando a rede aceitou este, para não pôr o arquivo inteiro na memória.
    private func sendPart(_ id: Int, handle: FileHandle, sent: Int64, size: Int64, name: String, session: Session) {
        guard session === active, pending[id] != nil else { return }
        guard sent < size else {
            queue.asyncAfter(deadline: .now() + Self.fileAckTimeout) { [weak self] in
                self?.pending.removeValue(forKey: id)?(.failure(SendError.timeout))
            }
            return
        }
        let chunk: Data
        do {
            chunk = try handle.read(upToCount: Wire.partSize) ?? Data()
        } catch {
            pending.removeValue(forKey: id)?(.failure(SendError.refused("não consegui ler o arquivo")))
            return
        }
        guard !chunk.isEmpty else {
            pending.removeValue(forKey: id)?(.failure(SendError.refused("o arquivo mudou durante o envio")))
            return
        }
        let total = sent + Int64(chunk.count)
        write(.part(id: id, data: chunk), to: session) { [weak self] in
            self?.fileEvent(.progress(name: name, fraction: Double(total) / Double(max(size, 1))))
            self?.sendPart(id, handle: handle, sent: total, size: size, name: name, session: session)
        }
    }

    private func fileEvent(_ event: FileEvent) {
        DispatchQueue.main.async { self.onFileEvent(event) }
    }

    // MARK: Conexão

    private func accept(_ conn: NWConnection) {
        guard pairingKey != nil else { return conn.cancel() }
        if let old = candidate { close(old) }
        let session = Session(conn)
        candidate = session
        conn.stateUpdateHandler = { [weak self, weak session] state in
            guard let self, let session else { return }
            switch state {
            case .failed, .cancelled: close(session)
            default: break
            }
        }
        conn.start(queue: queue)
        receive(session)
    }

    private func receive(_ session: Session) {
        session.conn.receive(minimumIncompleteLength: 1, maximumLength: 1 << 16) { [weak self] data, _, isComplete, error in
            guard let self, session === active || session === candidate else { return }
            if let data, !data.isEmpty {
                do {
                    for frame in try session.decoder.append(data) { try handle(frame, in: session) }
                } catch SecureChannel.ChannelError.decryptFailed {
                    NSLog("FileShare: conexão com chave diferente; recusada")
                    report(.rejected)
                    return close(session)
                } catch {
                    NSLog("FileShare: mensagem inválida: \(error)")
                    return close(session)
                }
            }
            if isComplete || error != nil { return close(session) }
            receive(session)
        }
    }

    private func handle(_ frame: Data, in session: Session) throws {
        switch session.phase {
        case .awaitingAuth:
            guard case .auth(let tabletNonce) = try Wire.decodeMessage(frame), let key = pairingKey else {
                throw Wire.DecodeError.badMessage("esperava AUTH")
            }
            let macNonce = SecureChannel.randomBytes(16)
            write(.auth(nonce: macNonce), to: session) // ainda em claro
            session.channel = SecureChannel(pairingKey: key, tabletNonce: tabletNonce, macNonce: macNonce, role: .mac)
            session.phase = .awaitingHello
        case .awaitingHello:
            guard case .hello(let name, let peer) = try open(frame, in: session) else { throw Wire.DecodeError.badMessage("esperava HELLO") }
            write(.hello(name: macName, info: Self.localInfo), to: session)
            session.peer = peer
            NSLog("FileShare: tablet %@ (versão %@, recursos: %@)", name, peer.version.isEmpty ? "≤ 2.3" : peer.version,
                  peer.capabilities.sorted().joined(separator: ","))
            session.phase = .ready
            session.lastSeen = Date()
            if !name.isEmpty { session.tabletName = name }
            if let old = active { close(old) }
            active = session
            candidate = nil
            report(.connected(name: session.tabletName))
            deliverHeld(to: session)
            pumpOutbox()
        case .ready:
            session.lastSeen = Date()
            switch try open(frame, in: session) {
            case .clip(let id, let payload):
                write(.ack(id: id), to: session)
                held.discard() // o que veio do tablet é mais novo que o que estava guardado
                DispatchQueue.main.async { self.onReceive(payload, nil) }
            case .held(let id, let copiedAt, let payload):
                // O tablet guardou esta cópia enquanto o Mac estava longe (2.4+).
                write(.ack(id: id), to: session)
                DispatchQueue.main.async { self.onReceive(payload, copiedAt) }
            case .file(let id, let size, let mime, let name):
                do {
                    let file = try IncomingFile(name: name, mime: mime, size: size, directory: Self.receivedFolder)
                    session.incoming[id] = file
                    if file.isComplete { finishFile(id, in: session) }
                } catch {
                    refuseFile(id, error, in: session)
                }
            case .part(let id, let data):
                guard let file = session.incoming[id] else { break } // arquivo já recusado
                do {
                    try file.append(data)
                    if file.isComplete { finishFile(id, in: session) }
                } catch {
                    session.incoming[id] = nil
                    refuseFile(id, error, in: session)
                }
            case .ack(let id):
                pending.removeValue(forKey: id)?(.success(()))
            case .fail(let id, let reason):
                pending.removeValue(forKey: id)?(.failure(SendError.refused(reason)))
            case .ping:
                write(.pong, to: session)
            case .pong:
                break
            case .battery(let level, let charging):
                DispatchQueue.main.async { self.onBattery(level, charging) }
            case .unknown(let type):
                NSLog("FileShare: mensagem %@ de um tablet mais novo, ignorada", type)
            case .auth, .hello:
                throw Wire.DecodeError.badMessage("mensagem fora de lugar")
            }
        }
    }

    private func finishFile(_ id: Int, in session: Session) {
        guard let file = session.incoming.removeValue(forKey: id) else { return }
        do {
            let url = try file.finish()
            write(.ack(id: id), to: session)
            let from = session.tabletName
            DispatchQueue.main.async { self.onFile(url, file.mime, from) }
        } catch {
            refuseFile(id, error, in: session)
        }
    }

    private func refuseFile(_ id: Int, _ error: Error, in session: Session) {
        let reason: String
        switch error {
        case IncomingFile.Failure.tooLarge: reason = "arquivo maior que 100 MB"
        case IncomingFile.Failure.moreThanAnnounced: reason = "chegou mais do que o anunciado"
        case IncomingFile.Failure.io(let detail): reason = "não consegui salvar (\(detail))"
        default: reason = error.localizedDescription
        }
        NSLog("FileShare: arquivo \(id) recusado: \(reason)")
        write(.fail(id: id, reason: reason), to: session)
    }

    private func open(_ frame: Data, in session: Session) throws -> WireMessage {
        guard var ch = session.channel else { throw SecureChannel.ChannelError.decryptFailed }
        let plaintext = try ch.open(frame)
        session.channel = ch
        return try Wire.decodeMessage(plaintext)
    }

    /// Cifra quando o canal já existe; só o AUTH vai em claro.
    private func write(_ message: WireMessage, to session: Session, sent: (() -> Void)? = nil) {
        let bytes = Wire.messageBytes(message)
        let frame: Data
        if var ch = session.channel {
            frame = Wire.frame(ch.seal(bytes))
            session.channel = ch
        } else {
            frame = Wire.frame(bytes)
        }
        session.conn.send(content: frame, completion: .contentProcessed { _ in sent?() })
    }

    private func close(_ session: Session) {
        session.conn.stateUpdateHandler = nil
        session.conn.cancel()
        session.incoming.values.forEach { $0.discard() }
        session.incoming.removeAll()
        if session === candidate { candidate = nil }
        guard session === active else { return }
        active = nil
        let failed = pending
        pending.removeAll()
        failed.values.forEach { $0(.failure(SendError.notConnected)) }
        report(pairingKey == nil ? .unpaired : .waiting)
    }

    private func report(_ state: State) {
        DispatchQueue.main.async { self.onState(state) }
    }
}
