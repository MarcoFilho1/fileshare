import Foundation

/// Protocolo provisório entre Mac e tablet: "mime\ntamanho\n<bytes>"; quem recebe responde "k".
/// O tamanho vai no cabeçalho porque o túnel do adb não repassa half-close.
public enum Framing {
    public static let ack = UInt8(ascii: "k")
    public static let maxPayload = 25 * 1024 * 1024
    private static let maxHeader = 256

    public enum DecodeError: Error, Equatable {
        case badHeader
        case badSize(String)
    }

    public static func encode(_ payload: ClipPayload) -> Data {
        var out = Data("\(payload.mime)\n\(payload.data.count)\n".utf8)
        out.append(payload.data)
        return out
    }

    /// Lê o cabeçalho do início do buffer; retorna nil se ainda não chegou inteiro.
    public static func parseHeader(_ buffer: Data) throws -> (mime: String, size: Int, headerLength: Int)? {
        let bytes = [UInt8](buffer.prefix(maxHeader))
        let newline = UInt8(ascii: "\n")
        guard let first = bytes.firstIndex(of: newline) else {
            if buffer.count >= maxHeader { throw DecodeError.badHeader }
            return nil
        }
        guard let second = bytes[(first + 1)...].firstIndex(of: newline) else {
            if buffer.count >= maxHeader { throw DecodeError.badHeader }
            return nil
        }
        let mime = String(decoding: bytes[..<first], as: UTF8.self).trimmingCharacters(in: .whitespaces)
        let sizeText = String(decoding: bytes[(first + 1)..<second], as: UTF8.self)
        guard !mime.isEmpty else { throw DecodeError.badHeader }
        guard let size = Int(sizeText), size > 0, size <= maxPayload else { throw DecodeError.badSize(sizeText) }
        return (mime, size, second + 1)
    }
}
