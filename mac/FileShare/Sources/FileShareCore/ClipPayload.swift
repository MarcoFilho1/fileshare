import Foundation

/// Conteúdo de uma cópia trocada entre Mac e tablet.
public struct ClipPayload: Equatable, Sendable {
    public let mime: String
    public let data: Data

    public init(mime: String, data: Data) {
        self.mime = mime
        self.data = data
    }

    public var isImage: Bool { mime.hasPrefix("image/") }

    /// Ex.: "imagem (150 KB)", "texto (12 caracteres)".
    public var summary: String {
        if isImage { return "imagem (\(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)))" }
        let chars = String(decoding: data, as: UTF8.self).count
        return "texto (\(chars) caractere\(chars == 1 ? "" : "s"))"
    }
}
