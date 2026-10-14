import FileShareCore
import Foundation
import Network

/// Troca conteúdo com o tablet pelo túnel do adb (127.0.0.1). Provisório até o Wi-Fi.
final class TabletLink {
    enum LinkError: LocalizedError {
        case noAck, timeout

        var errorDescription: String? {
            switch self {
            case .noAck: "o tablet não confirmou (o app FileShare está aberto?)"
            case .timeout: "o tablet não respondeu a tempo"
            }
        }
    }

    private let queue = DispatchQueue(label: "fileshare.link")
    private var listener: NWListener?
    private let onReceive: (ClipPayload) -> Void

    init(onReceive: @escaping (ClipPayload) -> Void) {
        self.onReceive = onReceive
    }

    // MARK: Mac → tablet

    func send(_ payload: ClipPayload, completion: @escaping (Result<Void, Error>) -> Void) {
        let conn = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(integerLiteral: UInt16(AdbTunnel.tabletPort)), using: .tcp)
        var finished = false
        let finish: (Result<Void, Error>) -> Void = { result in
            guard !finished else { return }
            finished = true
            conn.cancel()
            DispatchQueue.main.async { completion(result) }
        }
        conn.stateUpdateHandler = { state in
            switch state {
            case .ready:
                conn.send(content: Framing.encode(payload), completion: .contentProcessed { error in
                    if let error { return finish(.failure(error)) }
                    conn.receive(minimumIncompleteLength: 1, maximumLength: 1) { data, _, _, _ in
                        finish(data?.first == Framing.ack ? .success(()) : .failure(LinkError.noAck))
                    }
                })
            case .failed(let error), .waiting(let error):
                finish(.failure(error))
            default:
                break
            }
        }
        conn.start(queue: queue)
        queue.asyncAfter(deadline: .now() + 10) { finish(.failure(LinkError.timeout)) }
    }

    // MARK: tablet → Mac

    func startListening() throws {
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(integerLiteral: UInt16(AdbTunnel.macPort)))
        params.allowLocalEndpointReuse = true
        let listener = try NWListener(using: params)
        listener.newConnectionHandler = { [weak self] conn in self?.accept(conn) }
        listener.start(queue: queue)
        self.listener = listener
    }

    private func accept(_ conn: NWConnection) {
        var accumulator = FrameAccumulator()
        func readMore() {
            conn.receive(minimumIncompleteLength: 1, maximumLength: 1 << 16) { [weak self] data, _, isComplete, error in
                do {
                    if let data, let payload = try accumulator.append(data) {
                        DispatchQueue.main.async {
                            self?.onReceive(payload)
                            conn.send(content: Data([Framing.ack]), completion: .contentProcessed { _ in conn.cancel() })
                        }
                        return
                    }
                } catch {
                    NSLog("FileShare: mensagem inválida do tablet: \(error)")
                    return conn.cancel()
                }
                if isComplete || error != nil { return conn.cancel() }
                readMore()
            }
        }
        conn.start(queue: queue)
        readMore()
    }
}
