import FileShareCore
import Foundation
import Network

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

    enum SendError: LocalizedError {
        case notConnected, timeout

        var errorDescription: String? {
            switch self {
            case .notConnected: "tablet não conectado"
            case .timeout: "o tablet não confirmou a tempo"
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

    private let queue = DispatchQueue(label: "fileshare.server")
    private let macId: String
    private let macName = Host.current().localizedName ?? "Mac"
    private let onReceive: (ClipPayload) -> Void
    private let onState: (State) -> Void
    private let onHeldDelivered: (ClipPayload) -> Void
    private let onFile: (_ url: URL, _ mime: String, _ from: String) -> Void
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
         onReceive: @escaping (ClipPayload) -> Void,
         onState: @escaping (State) -> Void,
         onHeldDelivered: @escaping (ClipPayload) -> Void,
         onFile: @escaping (_ url: URL, _ mime: String, _ from: String) -> Void) {
        self.macId = macId
        self.onReceive = onReceive
        self.onState = onState
        self.onHeldDelivered = onHeldDelivered
        self.onFile = onFile
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
            guard case .hello(let name) = try open(frame, in: session) else { throw Wire.DecodeError.badMessage("esperava HELLO") }
            write(.hello(name: macName), to: session)
            session.phase = .ready
            session.lastSeen = Date()
            if !name.isEmpty { session.tabletName = name }
            if let old = active { close(old) }
            active = session
            candidate = nil
            report(.connected(name: session.tabletName))
            deliverHeld(to: session)
        case .ready:
            session.lastSeen = Date()
            switch try open(frame, in: session) {
            case .clip(let id, let payload):
                write(.ack(id: id), to: session)
                held.discard() // o que veio do tablet é mais novo que o que estava guardado
                DispatchQueue.main.async { self.onReceive(payload) }
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
            case .ping:
                write(.pong, to: session)
            case .pong:
                break
            case .auth, .hello, .held, .fail:
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
    private func write(_ message: WireMessage, to session: Session) {
        let bytes = Wire.messageBytes(message)
        let frame: Data
        if var ch = session.channel {
            frame = Wire.frame(ch.seal(bytes))
            session.channel = ch
        } else {
            frame = Wire.frame(bytes)
        }
        session.conn.send(content: frame, completion: .contentProcessed { _ in })
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
