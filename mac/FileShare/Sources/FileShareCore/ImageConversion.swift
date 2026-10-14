import AppKit

enum ImageConversion {
    /// Converte qualquer imagem que o AppKit entende (TIFF, JPEG, HEIC…) para PNG.
    static func png(from data: Data) -> Data? {
        if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return data }
        return NSBitmapImageRep(data: data)?.representation(using: .png, properties: [:])
    }

    static func tiff(from data: Data) -> Data? {
        NSBitmapImageRep(data: data)?.tiffRepresentation
    }
}
