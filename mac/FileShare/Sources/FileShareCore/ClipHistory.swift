import Foundation

/// As últimas cópias trocadas entre o Mac e o tablet, para o painel ⇄. Fica só na memória: some ao
/// fechar o app, e cópias de gerenciadores de senha nunca chegam aqui (o PasteboardReader as ignora).
public struct ClipHistory: Equatable, Sendable {
    public struct Entry: Identifiable, Equatable, Sendable {
        public let id: UUID
        public let payload: ClipPayload
        /// true: veio do tablet; false: foi copiada no Mac.
        public let fromTablet: Bool
        public let date: Date
    }

    public static let maxEntries = 10
    /// Imagens grandes somam rápido: passando disso, saem as imagens mais antigas.
    public static let maxBytes = 60 * 1024 * 1024

    public private(set) var entries: [Entry] = []

    public init() {}

    /// A mais nova vai para o topo; copiar de novo algo que já está na lista só a traz para cima.
    public mutating func add(_ payload: ClipPayload, fromTablet: Bool, at date: Date = Date()) {
        entries.removeAll { $0.payload == payload }
        entries.insert(Entry(id: UUID(), payload: payload, fromTablet: fromTablet, date: date), at: 0)
        if entries.count > Self.maxEntries { entries.removeLast(entries.count - Self.maxEntries) }
        while entries.count > 1, totalBytes > Self.maxBytes,
              let oldestImage = entries.lastIndex(where: { $0.payload.isImage }), oldestImage > 0 {
            entries.remove(at: oldestImage)
        }
    }

    public mutating func removeAll() {
        entries.removeAll()
    }

    public var totalBytes: Int { entries.reduce(0) { $0 + $1.payload.data.count } }

    /// Como a cópia aparece numa linha: a primeira linha do texto, sem espaços sobrando.
    public static func title(of payload: ClipPayload) -> String {
        let text = String(decoding: payload.data.prefix(4096), as: UTF8.self)
        let firstLine = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        return firstLine.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
