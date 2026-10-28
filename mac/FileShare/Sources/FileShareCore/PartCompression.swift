import Compression
import Foundation

/// Compressão dos pedaços de arquivo durante a viagem (PARZ, 2.6+): invisível para o usuário — quem
/// recebe descomprime antes de gravar e o arquivo chega idêntico. DEFLATE cru (RFC 1951), o mesmo
/// do zip, que o Android também traz (Deflater/Inflater com nowrap).
public enum PartCompression {
    /// Só vale mandar comprimido se encolher pelo menos isto (10%).
    public static let minimumGain = 0.10
    /// Depois de tantos pedaços seguidos sem ganho, o resto do arquivo vai direto.
    public static let giveUpAfter = 4

    /// Tipos que já vêm comprimidos: nem tenta.
    static let alreadyCompressed: Set<String> = [
        "mp4", "mov", "m4v", "mkv", "avi", "webm", "3gp",
        "jpg", "jpeg", "heic", "heif", "png", "gif", "webp", "avif",
        "mp3", "m4a", "aac", "ogg", "opus", "flac",
        "zip", "gz", "tgz", "bz2", "xz", "7z", "rar", "zst",
        "apk", "dmg", "ipa", "pkg", "jar", "docx", "xlsx", "pptx", "epub",
    ]

    /// Vale tentar comprimir este arquivo?
    public static func worthTrying(name: String, mime: String) -> Bool {
        if mime == Wire.folderMime || mime.hasPrefix("video/") || mime.hasPrefix("audio/") { return false }
        if mime.hasPrefix("image/") && !["image/bmp", "image/tiff", "image/x-ms-bmp", "image/svg+xml"].contains(mime) { return false }
        let ext = (name as NSString).pathExtension.lowercased()
        return !alreadyCompressed.contains(ext)
    }

    /// O pedaço comprimido, ou nil se não encolheu pelo menos `minimumGain`.
    public static func compress(_ data: Data) -> Data? {
        guard !data.isEmpty else { return nil }
        let limit = Int(Double(data.count) * (1 - minimumGain))
        var out = Data(count: limit)
        let written = out.withUnsafeMutableBytes { dst in
            data.withUnsafeBytes { src in
                compression_encode_buffer(dst.bindMemory(to: UInt8.self).baseAddress!, limit,
                                          src.bindMemory(to: UInt8.self).baseAddress!, data.count, nil, COMPRESSION_ZLIB)
            }
        }
        // 0: não coube no limite, ou seja, não encolheu o bastante
        guard written > 0 else { return nil }
        return out.prefix(written)
    }

    public enum Failure: Error, Equatable { case corrupt, tooLarge }

    /// Descomprime um pedaço, recusando o que passar de `maxSize` (proteção contra "bombas").
    public static func decompress(_ data: Data, maxSize: Int = Wire.partSize) throws -> Data {
        guard !data.isEmpty else { throw Failure.corrupt }
        var out = Data(count: maxSize + 1)
        let written = out.withUnsafeMutableBytes { dst in
            data.withUnsafeBytes { src in
                compression_decode_buffer(dst.bindMemory(to: UInt8.self).baseAddress!, maxSize + 1,
                                          src.bindMemory(to: UInt8.self).baseAddress!, data.count, nil, COMPRESSION_ZLIB)
            }
        }
        guard written > 0 else { throw Failure.corrupt }
        guard written <= maxSize else { throw Failure.tooLarge }
        return out.prefix(written)
    }
}
