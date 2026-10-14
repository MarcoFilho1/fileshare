import Foundation

/// Mensagens trocadas numa conexão permanente entre Mac e tablet.
public enum WireMessage: Equatable, Sendable {
    /// Única mensagem em claro: o nonce de cada lado para derivar as chaves da sessão.
    case auth(nonce: Data)
    case hello(name: String)
    case clip(id: Int, payload: ClipPayload)
    case ack(id: Int)
    case ping
    case pong
}

/// Formato: [tamanho: UInt32 big-endian][quadro]. O quadro é a mensagem "TIPO args\n" + corpo;
/// depois do AUTH, cada quadro vai cifrado pelo SecureChannel.
public enum Wire {
    public static let maxPayload = 25 * 1024 * 1024
    static let maxFrame = maxPayload + 1024

    public enum DecodeError: Error, Equatable {
        case frameTooLarge(Int)
        case badMessage(String)
    }

    public static func encode(_ message: WireMessage) -> Data {
        frame(messageBytes(message))
    }

    /// Prefixa o tamanho.
    public static func frame(_ body: Data) -> Data {
        var out = Data(capacity: 4 + body.count)
        withUnsafeBytes(of: UInt32(body.count).bigEndian) { out.append(contentsOf: $0) }
        out.append(body)
        return out
    }

    public static func messageBytes(_ message: WireMessage) -> Data {
        switch message {
        case .auth(let nonce): return Data("AUTH \(nonce.base64EncodedString())\n".utf8)
        case .hello(let name): return Data("HELLO \(name)\n".utf8)
        case .clip(let id, let payload):
            var d = Data("CLIP \(id) \(payload.mime)\n".utf8)
            d.append(payload.data)
            return d
        case .ack(let id): return Data("ACK \(id)\n".utf8)
        case .ping: return Data("PING\n".utf8)
        case .pong: return Data("PONG\n".utf8)
        }
    }

    public static func decodeMessage(_ bytes: Data) throws -> WireMessage {
        guard let nl = bytes.firstIndex(of: UInt8(ascii: "\n")) else { throw DecodeError.badMessage("sem cabeçalho") }
        let header = String(decoding: bytes[bytes.startIndex..<nl], as: UTF8.self)
        let body = Data(bytes[(nl + 1)...])
        let parts = header.split(separator: " ", maxSplits: 2).map(String.init)
        switch parts.first {
        case "AUTH":
            guard parts.count == 2, let nonce = Data(base64Encoded: parts[1]), nonce.count == 16 else {
                throw DecodeError.badMessage(header)
            }
            return .auth(nonce: nonce)
        case "HELLO":
            return .hello(name: parts.count > 1 ? header.dropFirst(6).description : "")
        case "CLIP":
            guard parts.count == 3, let id = Int(parts[1]), !body.isEmpty else { throw DecodeError.badMessage(header) }
            return .clip(id: id, payload: ClipPayload(mime: parts[2], data: body))
        case "ACK":
            guard parts.count == 2, let id = Int(parts[1]) else { throw DecodeError.badMessage(header) }
            return .ack(id: id)
        case "PING": return .ping
        case "PONG": return .pong
        default: throw DecodeError.badMessage(header)
        }
    }
}

/// Junta os bytes que chegam da rede e devolve os quadros completos (ainda cifrados, se for o caso).
public struct FrameDecoder {
    private var buffer = Data()

    public init() {}

    public mutating func append(_ chunk: Data) throws -> [Data] {
        buffer.append(chunk)
        var frames: [Data] = []
        while buffer.count >= 4 {
            let size = buffer.prefix(4).reduce(0) { $0 << 8 | Int($1) }
            guard size > 0, size <= Wire.maxFrame else { throw Wire.DecodeError.frameTooLarge(size) }
            guard buffer.count >= 4 + size else { break }
            let start = buffer.startIndex + 4
            frames.append(Data(buffer[start..<start + size]))
            buffer = Data(buffer[(start + size)...])
        }
        return frames
    }
}
