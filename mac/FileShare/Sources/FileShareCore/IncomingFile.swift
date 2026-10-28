import Foundation
import UniformTypeIdentifiers

/// Arquivo chegando do tablet: os pedaços vão para um arquivo oculto na pasta de destino e, quando
/// o arquivo está completo, ele ganha um nome livre (nunca sobrescreve nada que já esteja lá).
public final class IncomingFile {
    public enum Failure: Error, Equatable {
        case tooLarge(Int64)
        /// Não cabe no disco do Mac (deixando a folga de Wire.spareSpace).
        case noSpace(Int64)
        case moreThanAnnounced
        case io(String)
    }

    public let name: String
    public let mime: String
    public let size: Int64
    public private(set) var received: Int64 = 0
    /// Quando o FILE chegou, para medir a velocidade.
    public let startedAt = Date()
    /// Identificador do SEND (2.6+): com ele, o arquivo continua de onde parou se a conexão cair.
    public let transferId: String?
    /// Última vez que chegou um pedaço; pedaços guardados esquecidos por 24 h são apagados.
    public private(set) var lastActivity = Date()
    private let directory: URL
    private let partialURL: URL
    private var handle: FileHandle?

    /// `freeSpace` só existe para os testes; normalmente é o espaço livre do disco de `directory`.
    public init(name: String, mime: String, size: Int64, directory: URL, transferId: String? = nil, freeSpace: Int64? = nil) throws {
        self.transferId = transferId
        guard size <= Wire.maxFileSize else { throw Failure.tooLarge(size) }
        if let free = freeSpace ?? Self.freeSpace(near: directory), !Wire.hasRoom(for: size, free: free) {
            throw Failure.noSpace(size)
        }
        self.name = Self.safeName(name, mime: mime)
        self.mime = mime
        self.size = size
        self.directory = directory
        partialURL = directory.appendingPathComponent(".fileshare-\(UUID().uuidString).part")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            guard FileManager.default.createFile(atPath: partialURL.path, contents: nil) else {
                throw Failure.io("não consegui criar \(partialURL.lastPathComponent)")
            }
            handle = try FileHandle(forWritingTo: partialURL)
        } catch let failure as Failure {
            throw failure
        } catch {
            throw Failure.io(error.localizedDescription)
        }
    }

    public var isComplete: Bool { received == size }

    public func append(_ data: Data) throws {
        guard received + Int64(data.count) <= size else {
            discard()
            throw Failure.moreThanAnnounced
        }
        do {
            try handle?.write(contentsOf: data)
        } catch {
            discard()
            throw Failure.io(error.localizedDescription)
        }
        received += Int64(data.count)
        lastActivity = Date()
    }

    /// Pedaços (.part) que ficaram de uma vez anterior em que o app foi fechado no meio de um arquivo.
    public static func removeLeftovers(in directory: URL) {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil, options: [])) ?? []
        for url in files where url.lastPathComponent.hasPrefix(".fileshare-") && url.pathExtension == "part" {
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// Fecha o arquivo e o move para o nome final; devolve onde ele ficou.
    public func finish() throws -> URL {
        do {
            try handle?.close()
            handle = nil
            let url = Self.freeURL(for: name, in: directory)
            try FileManager.default.moveItem(at: partialURL, to: url)
            return url
        } catch {
            discard()
            throw Failure.io(error.localizedDescription)
        }
    }

    /// Espaço livre no disco da pasta (ou da pasta acima, se ela ainda não existe); nil se não deu para saber.
    static func freeSpace(near directory: URL) -> Int64? {
        var url = directory
        while !FileManager.default.fileExists(atPath: url.path), url.pathComponents.count > 1 { url.deleteLastPathComponent() }
        return (try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?.volumeAvailableCapacityForImportantUsage
    }

    /// Conexão caiu no meio: apaga o que chegou.
    public func discard() {
        try? handle?.close()
        handle = nil
        try? FileManager.default.removeItem(at: partialURL)
    }

    /// O nome vem do tablet: sem barras, caracteres de controle ou ponto no começo (arquivo oculto),
    /// com extensão pelo mime quando faltar.
    public static func safeName(_ raw: String, mime: String) -> String {
        var name = String(raw.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) })
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespaces)
        while name.hasPrefix(".") { name.removeFirst() }
        if name.isEmpty { name = "arquivo" }
        var ext = (name as NSString).pathExtension
        var stem = (name as NSString).deletingPathExtension
        if ext.isEmpty, let typeExt = UTType(mimeType: mime)?.preferredFilenameExtension { ext = typeExt }
        if stem.count > 150 { stem = String(stem.prefix(150)) }
        return ext.isEmpty ? stem : "\(stem).\(ext)"
    }

    /// "Nota.pdf", ou "Nota (2).pdf", "Nota (3).pdf"… se já existir.
    public static func freeURL(for name: String, in directory: URL) -> URL {
        let ext = (name as NSString).pathExtension
        let stem = (name as NSString).deletingPathExtension
        var url = directory.appendingPathComponent(name)
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            let candidate = "\(stem) (\(n))" + (ext.isEmpty ? "" : ".\(ext)")
            url = directory.appendingPathComponent(candidate)
            n += 1
        }
        return url
    }
}
