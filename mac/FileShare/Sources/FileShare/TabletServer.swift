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
        /// Pasta sendo compactada antes de entrar na fila.
        case preparing(name: String)
        /// Você cancelou o envio no meio.
        case cancelled(name: String)
        /// Arquivo chegando do tablet (só os grandes, para a barra não piscar).
        case receiving(name: String, fraction: Double)
        /// O arquivo que chegava terminou, foi recusado ou cancelado.
        case receivingEnded(name: String)
    }

    enum SendError: LocalizedError {
        case notConnected, timeout, cancelled
        case refused(String)

        var errorDescription: String? {
            switch self {
            case .notConnected: "tablet não conectado"
            case .timeout: "o tablet não confirmou a tempo"
            case .cancelled: "cancelado"
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
        /// Último percentual avisado de cada arquivo chegando.
        var reportedPercent: [Int: Int] = [:]

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
        /// Abre no navegador do Mac os links de Compartilhar → Abrir no Mac (OPEN).
        static let open = "open"
        /// Aceita arquivos de até 2 GB (antes, 100 MB).
        static let bigFiles = "big"
        /// Entende STOP: quem envia desistiu no meio.
        static let stop = "stop"
        /// O tablet desfaz pastas compactadas (Wire.folderMime) em Download/FileShare.
        static let folders = "folder"
        /// Entende SEND/FROM: arquivos continuam de onde pararam se a conexão cair.
        static let resume = "resume"
    }

    /// O que o Mac anuncia no HELLO. Cada recurso novo entra aqui quando estiver pronto.
    static let localInfo = PeerInfo(
        version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev",
        capabilities: [Capability.held, Capability.battery, Capability.open, Capability.bigFiles, Capability.stop, Capability.resume])
    /// Cópia vinda do tablet; copiedAt (ms desde 1970) só vem quando ele a guardou com o Mac longe (HELD).
    private let onReceive: (_ payload: ClipPayload, _ copiedAt: Int64?) -> Void
    private let onState: (State) -> Void
    private let onHeldDelivered: (ClipPayload) -> Void
    private let onFile: (_ url: URL, _ mime: String, _ from: String) -> Void
    private let onFileEvent: (FileEvent) -> Void
    private let onBattery: (_ level: Int, _ charging: Bool) -> Void
    private let onOpen: (URL) -> Void
    /// Algo para mandar ao tablet: um arquivo, ou uma pasta já compactada num zip temporário.
    private struct Outgoing {
        let url: URL
        let name: String
        let isFolder: Bool
        /// O mesmo em todas as tentativas: o tablet 2.6+ continua de onde parou.
        let transferId = Wire.newTransferId()
    }

    /// Arquivos a enviar ao tablet, um de cada vez; ficam aqui enquanto ele dorme.
    private var outbox: [Outgoing] = []
    private var sendingFile = false
    /// id do FILE que está indo agora, para o botão Cancelar.
    private var sendingId: Int?
    private static let zipQueue = DispatchQueue(label: "fileshare.zip")
    /// Arquivos que chegavam do tablet quando a conexão caiu, pelo transferId: continuam de onde
    /// pararam quando ele mandar o SEND de novo. Esquecidos depois de 24 h.
    private var partials: [String: IncomingFile] = [:]
    private static let partialLifetime: TimeInterval = 24 * 60 * 60
    /// SEND já mandado, esperando o FROM do tablet para começar (ou continuar) os pedaços.
    private var awaitingFrom: [Int: (handle: FileHandle, size: Int64, name: String)] = [:]
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
         onBattery: @escaping (_ level: Int, _ charging: Bool) -> Void,
         onOpen: @escaping (URL) -> Void) {
        self.macId = macId
        self.onReceive = onReceive
        self.onState = onState
        self.onHeldDelivered = onHeldDelivered
        self.onFile = onFile
        self.onFileEvent = onFileEvent
        self.onBattery = onBattery
        self.onOpen = onOpen
        IncomingFile.removeLeftovers(in: Self.receivedFolder) // pedaços de quando o app foi fechado no meio
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
                guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else {
                    fileEvent(.failed(name: url.lastPathComponent, reason: "não encontrei o arquivo"))
                    continue
                }
                if isDir.boolValue {
                    compressFolder(url)
                } else {
                    outbox.append(Outgoing(url: url, name: url.lastPathComponent, isFolder: false))
                }
            }
            pumpOutbox()
        }
    }

    /// Compacta a pasta (fora da fila do servidor, pode demorar) e a põe na fila de envio.
    private func compressFolder(_ folder: URL) {
        let name = folder.lastPathComponent
        fileEvent(.preparing(name: name))
        Self.zipQueue.async { [self] in
            let zip = FileManager.default.temporaryDirectory
                .appendingPathComponent("fileshare-\(UUID().uuidString)", isDirectory: true)
                .appendingPathComponent(name + ".zip")
            let ok = FolderZip.zip(folder, to: zip)
            queue.async { [self] in
                guard ok else {
                    fileEvent(.failed(name: name, reason: "não consegui compactar a pasta"))
                    return
                }
                outbox.append(Outgoing(url: zip, name: name, isFolder: true))
                pumpOutbox()
            }
        }
    }

    /// Botão × do envio: para no meio. Um tablet 2.6+ apaga o que chegou ao receber STOP; com um
    /// mais antigo, a conexão é refeita, e ele apaga o pedaço ao perder a conexão.
    func cancelSending() {
        queue.async { [self] in
            guard let id = sendingId, let done = pending.removeValue(forKey: id) else { return }
            if let session = active {
                if session.peer.supports(Capability.stop) { write(.stop(id: id), to: session) } else { close(session) }
            }
            done(.failure(SendError.cancelled))
        }
    }

    /// Botão × do que está chegando: recusa o resto (o tablet para de mandar) e apaga o que chegou.
    func cancelReceiving() {
        queue.async { [self] in
            guard let session = active, let (id, file) = session.incoming.first else { return }
            forgetPartial(file)
            file.discard()
            session.incoming[id] = nil
            session.reportedPercent[id] = nil
            write(.fail(id: id, reason: "cancelado no Mac"), to: session)
            fileEvent(.receivingEnded(name: file.name))
        }
    }

    /// Fim de um item da fila: apaga o zip temporário de uma pasta.
    private func finishOutgoing(_ item: Outgoing) {
        if item.isFolder { try? FileManager.default.removeItem(at: item.url.deletingLastPathComponent()) }
    }

    /// Envia o próximo arquivo da fila, se houver tablet conectado e nada sendo enviado.
    private func pumpOutbox() {
        guard !sendingFile, let item = outbox.first else { return }
        guard let session = active, Date().timeIntervalSince(session.lastSeen) <= Self.staleAfter else {
            if let stale = active { close(stale) }
            outbox.forEach { fileEvent(.queued(name: $0.name)) }
            return
        }
        let url = item.url
        let name = item.name
        let size = ((try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) as? NSNumber)?.int64Value ?? -1
        let limit = Wire.maxFileSize(peerSupportsBigFiles: session.peer.supports(Capability.bigFiles))
        guard size >= 0, size <= limit, let handle = try? FileHandle(forReadingFrom: url) else {
            outbox.removeFirst()
            finishOutgoing(item)
            let reason = size < 0 ? "não consegui ler o arquivo"
                : size <= Wire.maxFileSize ? "acima de \(Wire.readable(limit)): atualize o FileShare no tablet"
                : "maior que \(Wire.readable(Wire.maxFileSize))"
            fileEvent(.failed(name: name, reason: reason))
            return pumpOutbox()
        }
        sendingFile = true
        let id = nextId
        nextId += 1
        sendingId = id
        let startedAt = Date()
        pending[id] = { [weak self] result in
            guard let self else { return }
            try? handle.close()
            sendingFile = false
            sendingId = nil
            switch result {
            case .success:
                outbox.removeFirst()
                finishOutgoing(item)
                NSLog("FileShare: enviado ao tablet: %@", Wire.speed(size, since: startedAt))
                fileEvent(.delivered(name: name))
            case .failure(SendError.cancelled):
                outbox.removeFirst()
                finishOutgoing(item)
                fileEvent(.cancelled(name: name))
            case .failure(SendError.refused(let reason)):
                outbox.removeFirst()
                finishOutgoing(item)
                fileEvent(.failed(name: name, reason: reason))
            case .failure:
                // conexão caiu no meio: o arquivo continua na fila para quando o tablet voltar
                fileEvent(.queued(name: name))
                return
            }
            pumpOutbox()
        }
        // Pasta: o tablet 2.6+ a desfaz; um mais antigo recebe o zip como arquivo comum.
        let (mime, wireName) = item.isFolder
            ? (session.peer.supports(Capability.folders) ? (Wire.folderMime, name) : ("application/zip", name + ".zip"))
            : (UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream", name)
        if session.peer.supports(Capability.resume) {
            // o tablet responde FROM com quanto já tem deste arquivo
            awaitingFrom[id] = (handle, size, name)
            write(.send(id: id, size: size, transferId: item.transferId, mime: mime, name: wireName), to: session)
            queue.asyncAfter(deadline: .now() + Self.ackTimeout) { [weak self] in
                guard let self, awaitingFrom.removeValue(forKey: id) != nil else { return }
                pending.removeValue(forKey: id)?(.failure(SendError.timeout))
            }
        } else {
            write(.file(id: id, size: size, mime: mime, name: wireName), to: session)
            sendPart(id, handle: handle, sent: 0, size: size, name: name, session: session)
        }
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
            // cancelado ou caído enquanto este pedaço ia: não recria a barra de progresso
            guard let self, pending[id] != nil else { return }
            fileEvent(.progress(name: name, fraction: Double(total) / Double(max(size, 1))))
            sendPart(id, handle: handle, sent: total, size: size, name: name, session: session)
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
            case .send(let id, let size, let tid, let mime, let name):
                prunePartials()
                do {
                    let file: IncomingFile
                    if let partial = partials[tid], partial.size == size, partial.mime == mime {
                        file = partial
                        NSLog("FileShare: continuando %@ de %@", partial.name, Wire.readable(partial.received))
                    } else {
                        partials.removeValue(forKey: tid)?.discard()
                        file = try IncomingFile(name: name, mime: mime, size: size, directory: Self.receivedFolder, transferId: tid)
                        partials[tid] = file
                    }
                    session.incoming[id] = file
                    write(.from(id: id, offset: file.received), to: session)
                    if file.isComplete { finishFile(id, in: session) }
                } catch {
                    refuseFile(id, error, in: session)
                }
            case .from(let id, let offset):
                guard let sending = awaitingFrom.removeValue(forKey: id) else { break }
                guard offset <= sending.size, (try? sending.handle.seek(toOffset: UInt64(offset))) != nil else {
                    pending.removeValue(forKey: id)?(.failure(SendError.refused("o tablet pediu uma posição inválida")))
                    break
                }
                if offset > 0 { NSLog("FileShare: o tablet já tinha %@ de %@; continuando", Wire.readable(offset), sending.name) }
                sendPart(id, handle: sending.handle, sent: offset, size: sending.size, name: sending.name, session: session)
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
                    if file.isComplete {
                        finishFile(id, in: session)
                    } else if file.size >= Self.showProgressFrom {
                        let percent = Int(file.received * 100 / max(file.size, 1))
                        if session.reportedPercent[id] != percent {
                            session.reportedPercent[id] = percent
                            fileEvent(.receiving(name: file.name, fraction: Double(percent) / 100))
                        }
                    }
                } catch {
                    session.incoming[id] = nil
                    session.reportedPercent[id] = nil
                    forgetPartial(file)
                    if file.size >= Self.showProgressFrom { fileEvent(.receivingEnded(name: file.name)) }
                    refuseFile(id, error, in: session)
                }
            case .stop(let id):
                // o tablet cancelou o envio deste arquivo
                if let file = session.incoming.removeValue(forKey: id) {
                    forgetPartial(file)
                    file.discard()
                    session.reportedPercent[id] = nil
                    fileEvent(.receivingEnded(name: file.name))
                    NSLog("FileShare: o tablet cancelou %@", file.name)
                }
            case .ack(let id):
                pending.removeValue(forKey: id)?(.success(()))
            case .fail(let id, let reason):
                pending.removeValue(forKey: id)?(.failure(SendError.refused(reason)))
            case .ping:
                write(.pong, to: session)
            case .pong:
                break
            case .open(let id, let text):
                if let url = Wire.webURL(text) {
                    write(.ack(id: id), to: session)
                    DispatchQueue.main.async { self.onOpen(url) }
                } else {
                    write(.fail(id: id, reason: "não é um link da web"), to: session)
                }
            case .battery(let level, let charging):
                DispatchQueue.main.async { self.onBattery(level, charging) }
            case .unknown(let type):
                NSLog("FileShare: mensagem %@ de um tablet mais novo, ignorada", type)
            case .auth, .hello:
                throw Wire.DecodeError.badMessage("mensagem fora de lugar")
            }
        }
    }

    private func forgetPartial(_ file: IncomingFile) {
        if let tid = file.transferId, partials[tid] === file { partials[tid] = nil }
    }

    /// Esquece (e apaga) os pedaços guardados há mais de 24 h.
    private func prunePartials() {
        for (tid, file) in partials where Date().timeIntervalSince(file.lastActivity) > Self.partialLifetime {
            file.discard()
            partials[tid] = nil
        }
    }

    /// Arquivos menores que isto chegam rápido demais para valer uma barra.
    private static let showProgressFrom: Int64 = 4 * Int64(Wire.partSize)

    private func finishFile(_ id: Int, in session: Session) {
        guard let file = session.incoming.removeValue(forKey: id) else { return }
        session.reportedPercent[id] = nil
        forgetPartial(file)
        if file.size >= Self.showProgressFrom { fileEvent(.receivingEnded(name: file.name)) }
        do {
            let url = try file.finish()
            write(.ack(id: id), to: session)
            NSLog("FileShare: recebido do tablet: %@", Wire.speed(file.size, since: file.startedAt))
            let from = session.tabletName
            DispatchQueue.main.async { self.onFile(url, file.mime, from) }
        } catch {
            refuseFile(id, error, in: session)
        }
    }

    private func refuseFile(_ id: Int, _ error: Error, in session: Session) {
        let reason: String
        switch error {
        case IncomingFile.Failure.tooLarge: reason = "arquivo maior que \(Wire.readable(Wire.maxFileSize))"
        case IncomingFile.Failure.noSpace(let size): reason = "não há espaço no Mac para \(Wire.readable(size))"
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
        session.incoming.values.forEach { file in
            // com transferId, o pedaço fica guardado para continuar quando o tablet voltar
            if file.transferId == nil { file.discard() }
            if file.size >= Self.showProgressFrom { fileEvent(.receivingEnded(name: file.name)) }
        }
        if session === active {
            awaitingFrom.values.forEach { try? $0.handle.close() }
            awaitingFrom.removeAll()
        }
        session.incoming.removeAll()
        session.reportedPercent.removeAll()
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
