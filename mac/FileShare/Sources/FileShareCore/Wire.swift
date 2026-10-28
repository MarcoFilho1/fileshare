import Foundation

/// O que cada lado anuncia no HELLO: a versão do app e os recursos que ele entende. Vai no corpo
/// do HELLO, que as versões até a 2.3 ignoram; para elas, isto chega vazio.
public struct PeerInfo: Equatable, Sendable {
    public var version: String
    public var capabilities: Set<String>

    public init(version: String = "", capabilities: Set<String> = []) {
        self.version = version
        self.capabilities = capabilities
    }

    /// Só envie uma mensagem nova se o outro lado anunciou que a entende: um app antigo derruba a
    /// conexão ao receber um tipo que não conhece.
    public func supports(_ capability: String) -> Bool { capabilities.contains(capability) }

    /// Linhas "chave=valor"; chaves desconhecidas são ignoradas, para poder crescer depois.
    var body: Data {
        guard !version.isEmpty || !capabilities.isEmpty else { return Data() }
        return Data("v=\(version)\ncaps=\(capabilities.sorted().joined(separator: ","))\n".utf8)
    }

    init(body: Data) {
        self.init()
        for line in String(decoding: body, as: UTF8.self).split(separator: "\n") {
            let kv = line.split(separator: "=", maxSplits: 1).map(String.init)
            guard kv.count == 2 else { continue }
            switch kv[0] {
            case "v": version = kv[1]
            case "caps": capabilities = Set(kv[1].split(separator: ",").map(String.init).filter { !$0.isEmpty })
            default: break
            }
        }
    }
}

/// Mensagens trocadas numa conexão permanente entre Mac e tablet.
public enum WireMessage: Equatable, Sendable {
    /// Única mensagem em claro: o nonce de cada lado para derivar as chaves da sessão.
    case auth(nonce: Data)
    case hello(name: String, info: PeerInfo = PeerInfo())
    case clip(id: Int, payload: ClipPayload)
    /// Cópia que o Mac guardou enquanto o tablet estava desconectado, com o horário em que foi feita
    /// (ms desde 1970), para o tablet não sobrescrever algo que o usuário copiou lá depois.
    case held(id: Int, copiedAt: Int64, payload: ClipPayload)
    /// Início de um arquivo vindo do menu Compartilhar do tablet; o conteúdo segue em PARTs.
    case file(id: Int, size: Int64, mime: String, name: String)
    /// Pedaço do arquivo `id`, em ordem. Quando o total chega a `size`, o Mac confirma com ACK.
    case part(id: Int, data: Data)
    case ack(id: Int)
    /// O Mac recusou o arquivo `id` (grande demais, sem espaço…); o motivo aparece no tablet.
    case fail(id: Int, reason: String)
    case ping
    case pong
    /// Bateria do tablet (0–100) e se está carregando; ele manda ao conectar e quando muda (2.4+).
    case battery(level: Int, charging: Bool)
    /// Tipo que esta versão não conhece (de uma versão mais nova do outro lado): quem recebe ignora,
    /// em vez de derrubar a conexão. Para crescer o protocolo, crie tipos novos em vez de mudar os
    /// argumentos dos que já existem.
    case unknown(type: String)
}

/// Formato: [tamanho: UInt32 big-endian][quadro]. O quadro é a mensagem "TIPO args\n" + corpo;
/// depois do AUTH, cada quadro vai cifrado pelo SecureChannel.
public enum Wire {
    public static let maxPayload = 25 * 1024 * 1024
    /// Arquivos vão em pedaços, então podem passar do limite de um quadro.
    public static let maxFileSize: Int64 = 100 * 1024 * 1024
    public static let partSize = 512 * 1024
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
        case .hello(let name, let info): return Data("HELLO \(name)\n".utf8) + info.body
        case .clip(let id, let payload):
            var d = Data("CLIP \(id) \(payload.mime)\n".utf8)
            d.append(payload.data)
            return d
        case .held(let id, let copiedAt, let payload):
            var d = Data("HELD \(id) \(copiedAt) \(payload.mime)\n".utf8)
            d.append(payload.data)
            return d
        case .file(let id, let size, let mime, let name): return Data("FILE \(id) \(size) \(mime) \(name)\n".utf8)
        case .part(let id, let data):
            var d = Data("PART \(id)\n".utf8)
            d.append(data)
            return d
        case .ack(let id): return Data("ACK \(id)\n".utf8)
        case .fail(let id, let reason): return Data("FAIL \(id) \(reason)\n".utf8)
        case .ping: return Data("PING\n".utf8)
        case .pong: return Data("PONG\n".utf8)
        case .battery(let level, let charging): return Data("BATT \(level) \(charging ? 1 : 0)\n".utf8)
        case .unknown(let type): return Data("\(type)\n".utf8)
        }
    }

    public static func decodeMessage(_ bytes: Data) throws -> WireMessage {
        guard let nl = bytes.firstIndex(of: UInt8(ascii: "\n")) else { throw DecodeError.badMessage("sem cabeçalho") }
        let header = String(decoding: bytes[bytes.startIndex..<nl], as: UTF8.self)
        let body = Data(bytes[(nl + 1)...])
        let parts = header.split(separator: " ", maxSplits: Self.argumentCount(header)).map(String.init)
        switch parts.first {
        case "AUTH":
            guard parts.count == 2, let nonce = Data(base64Encoded: parts[1]), nonce.count == 16 else {
                throw DecodeError.badMessage(header)
            }
            return .auth(nonce: nonce)
        case "HELLO":
            return .hello(name: parts.count > 1 ? header.dropFirst(6).description : "", info: PeerInfo(body: body))
        case "CLIP":
            guard parts.count == 3, let id = Int(parts[1]), !body.isEmpty else { throw DecodeError.badMessage(header) }
            return .clip(id: id, payload: ClipPayload(mime: parts[2], data: body))
        case "HELD":
            guard parts.count == 4, let id = Int(parts[1]), let copiedAt = Int64(parts[2]), !body.isEmpty else {
                throw DecodeError.badMessage(header)
            }
            return .held(id: id, copiedAt: copiedAt, payload: ClipPayload(mime: parts[3], data: body))
        case "FILE":
            guard parts.count == 5, let id = Int(parts[1]), let size = Int64(parts[2]), size >= 0, body.isEmpty else {
                throw DecodeError.badMessage(header)
            }
            return .file(id: id, size: size, mime: parts[3], name: parts[4])
        case "PART":
            guard parts.count == 2, let id = Int(parts[1]), !body.isEmpty else { throw DecodeError.badMessage(header) }
            return .part(id: id, data: body)
        case "ACK":
            guard parts.count == 2, let id = Int(parts[1]) else { throw DecodeError.badMessage(header) }
            return .ack(id: id)
        case "FAIL":
            guard parts.count == 3, let id = Int(parts[1]) else { throw DecodeError.badMessage(header) }
            return .fail(id: id, reason: parts[2])
        case "PING": return .ping
        case "PONG": return .pong
        case "BATT":
            guard parts.count == 3, let level = Int(parts[1]), (0...100).contains(level), ["0", "1"].contains(parts[2]) else {
                throw DecodeError.badMessage(header)
            }
            return .battery(level: level, charging: parts[2] == "1")
        default:
            // Um tipo novo é uma palavra em maiúsculas; qualquer outra coisa é lixo.
            guard let type = parts.first, !type.isEmpty, type.count <= 16,
                  type.unicodeScalars.allSatisfy({ ("A"..."Z").contains($0) }) else { throw DecodeError.badMessage(header) }
            return .unknown(type: type)
        }
    }

    /// Quantos cortes no cabeçalho: o último argumento (nome, mime) pode ter espaços.
    private static func argumentCount(_ header: String) -> Int {
        if header.hasPrefix("FILE ") { return 4 }
        if header.hasPrefix("HELD ") { return 3 }
        return 2
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
