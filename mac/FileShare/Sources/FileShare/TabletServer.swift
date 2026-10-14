import FileShareCore
import Foundation
import Network

/// Servidor no Wi-Fi: anuncia o Mac por Bonjour (_fileshare._tcp) e mantém uma conexão
/// permanente com o tablet, por onde as cópias vão e vêm.
final class TabletServer {
    static let serviceType = "_fileshare._tcp"

    enum State: Equatable {
        case starting
        case waiting
        case connected(name: String)
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

    private static let idleTimeout: TimeInterval = 70 // o tablet manda PING a cada 20 s

    private let queue = DispatchQueue(label: "fileshare.server")
    private let onReceive: (ClipPayload) -> Void
    private let onState: (State) -> Void
    private var listener: NWListener?
    private var connection: NWConnection?
    private var decoder = WireDecoder()
    private var lastSeen = Date()
    private var nextId = 1
    private var pending: [Int: (Result<Void, Error>) -> Void] = [:]
    private var watchdog: DispatchSourceTimer?

    init(onReceive: @escaping (ClipPayload) -> Void, onState: @escaping (State) -> Void) {
        self.onReceive = onReceive
        self.onState = onState
    }

    func start() {
        let tcp = NWProtocolTCP.Options()
        tcp.enableKeepalive = true
        tcp.keepaliveIdle = 30
        do {
            let listener = try NWListener(using: NWParameters(tls: nil, tcp: tcp))
            listener.service = NWListener.Service(name: Host.current().localizedName, type: Self.serviceType)
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

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 10, repeating: 10)
        timer.setEventHandler { [weak self] in
            guard let self, let conn = connection, Date().timeIntervalSince(lastSeen) > Self.idleTimeout else { return }
            conn.cancel()
            dropped(conn)
        }
        timer.resume()
        watchdog = timer
    }

    // MARK: Mac → tablet

    func send(_ payload: ClipPayload, completion: @escaping (Result<Void, Error>) -> Void) {
        let done: (Result<Void, Error>) -> Void = { result in DispatchQueue.main.async { completion(result) } }
        queue.async { [self] in
            guard connection != nil else { return done(.failure(SendError.notConnected)) }
            let id = nextId
            nextId += 1
            pending[id] = done
            write(.clip(id: id, payload: payload))
            queue.asyncAfter(deadline: .now() + 15) { [weak self] in
                self?.pending.removeValue(forKey: id)?(.failure(SendError.timeout))
            }
        }
    }

    // MARK: Conexão

    /// Um tablet por vez: uma conexão nova substitui a anterior (ex.: o tablet reconectou).
    private func accept(_ conn: NWConnection) {
        if let old = connection {
            old.cancel()
            dropped(old)
        }
        connection = conn
        decoder = WireDecoder()
        lastSeen = Date()
        conn.stateUpdateHandler = { [weak self, weak conn] state in
            guard let self, let conn else { return }
            switch state {
            case .failed, .cancelled: dropped(conn)
            default: break
            }
        }
        conn.start(queue: queue)
        receive(on: conn)
    }

    private func receive(on conn: NWConnection) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 1 << 16) { [weak self] data, _, isComplete, error in
            guard let self, conn === connection else { return }
            if let data, !data.isEmpty {
                lastSeen = Date()
                do {
                    for message in try decoder.append(data) { handle(message) }
                } catch {
                    NSLog("FileShare: mensagem inválida do tablet: \(error)")
                    conn.cancel()
                    return
                }
            }
            if isComplete || error != nil {
                conn.cancel()
                return
            }
            receive(on: conn)
        }
    }

    private func handle(_ message: WireMessage) {
        switch message {
        case .hello(let name):
            report(.connected(name: name.isEmpty ? "tablet" : name))
        case .clip(let id, let payload):
            write(.ack(id: id))
            DispatchQueue.main.async { self.onReceive(payload) }
        case .ack(let id):
            pending.removeValue(forKey: id)?(.success(()))
        case .ping:
            write(.pong)
        case .pong:
            break
        }
    }

    private func write(_ message: WireMessage) {
        connection?.send(content: Wire.encode(message), completion: .contentProcessed { _ in })
    }

    private func dropped(_ conn: NWConnection) {
        guard conn === connection else { return }
        connection = nil
        let failed = pending
        pending.removeAll()
        failed.values.forEach { $0(.failure(SendError.notConnected)) }
        report(.waiting)
    }

    private func report(_ state: State) {
        DispatchQueue.main.async { self.onState(state) }
    }
}
