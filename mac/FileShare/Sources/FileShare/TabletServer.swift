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

        init(_ conn: NWConnection) {
            self.conn = conn
        }
    }

    private static let idleTimeout: TimeInterval = 70 // o tablet manda PING a cada 20 s
    private static let handshakeTimeout: TimeInterval = 10

    private let queue = DispatchQueue(label: "fileshare.server")
    private let macId: String
    private let macName = Host.current().localizedName ?? "Mac"
    private let onReceive: (ClipPayload) -> Void
    private let onState: (State) -> Void
    private var pairingKey: Data?
    private var listener: NWListener?
    /// Tablet autenticado. Uma conexão nova fica como candidata e só substitui esta depois de
    /// provar que tem a chave, para um estranho na rede não conseguir derrubar o tablet.
    private var active: Session?
    private var candidate: Session?
    private var nextId = 1
    private var pending: [Int: (Result<Void, Error>) -> Void] = [:]
    private var watchdog: DispatchSourceTimer?

    init(macId: String, onReceive: @escaping (ClipPayload) -> Void, onState: @escaping (State) -> Void) {
        self.macId = macId
        self.onReceive = onReceive
        self.onState = onState
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

    func send(_ payload: ClipPayload, completion: @escaping (Result<Void, Error>) -> Void) {
        let done: (Result<Void, Error>) -> Void = { result in DispatchQueue.main.async { completion(result) } }
        queue.async { [self] in
            guard let session = active else { return done(.failure(SendError.notConnected)) }
            let id = nextId
            nextId += 1
            pending[id] = done
            write(.clip(id: id, payload: payload), to: session)
            queue.asyncAfter(deadline: .now() + 15) { [weak self] in
                self?.pending.removeValue(forKey: id)?(.failure(SendError.timeout))
            }
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
            if let old = active { close(old) }
            active = session
            candidate = nil
            report(.connected(name: name.isEmpty ? "tablet" : name))
        case .ready:
            session.lastSeen = Date()
            switch try open(frame, in: session) {
            case .clip(let id, let payload):
                write(.ack(id: id), to: session)
                DispatchQueue.main.async { self.onReceive(payload) }
            case .ack(let id):
                pending.removeValue(forKey: id)?(.success(()))
            case .ping:
                write(.pong, to: session)
            case .pong:
                break
            case .auth, .hello:
                throw Wire.DecodeError.badMessage("handshake repetido")
            }
        }
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
