import AppKit

/// Grava no Mac o que veio do tablet, marcado para o PasteboardReader não devolver.
public enum PasteboardWriter {
    @discardableResult
    public static func write(_ payload: ClipPayload, to pasteboard: NSPasteboard) -> Bool {
        if payload.isImage {
            // O Samsung Notes entrega JPEG; PNG + TIFF cobre todos os apps do Mac.
            guard let png = ImageConversion.png(from: payload.data) else { return false }
            pasteboard.declareTypes([.png, .tiff, PasteboardReader.originType], owner: nil)
            pasteboard.setData(png, forType: .png)
            if let tiff = ImageConversion.tiff(from: png) { pasteboard.setData(tiff, forType: .tiff) }
        } else {
            pasteboard.declareTypes([.string, PasteboardReader.originType], owner: nil)
            pasteboard.setString(String(decoding: payload.data, as: UTF8.self), forType: .string)
        }
        pasteboard.setData(Data(), forType: PasteboardReader.originType)
        return true
    }
}
