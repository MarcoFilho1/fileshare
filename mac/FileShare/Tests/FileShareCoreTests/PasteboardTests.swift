import AppKit
import Testing
@testable import FileShareCore

/// Usa uma área de transferência própria por teste, nunca a do usuário.
@MainActor
struct PasteboardTests {
    let pb = NSPasteboard(name: .init("dev.marcofilho.fileshare.tests.\(UUID().uuidString)"))

    static func image(_ type: NSBitmapImageRep.FileType, width: Int = 4, height: Int = 3) -> Data {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
                                   samplesPerPixel: 3, hasAlpha: false, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        return type == .tiff ? rep.tiffRepresentation! : rep.representation(using: type, properties: [:])!
    }

    static func isPNG(_ data: Data) -> Bool { data.starts(with: [0x89, 0x50, 0x4E, 0x47]) }

    static func size(_ data: Data) -> (Int, Int)? {
        NSBitmapImageRep(data: data).map { ($0.pixelsWide, $0.pixelsHigh) }
    }

    @Test func readsText() {
        pb.clearContents()
        pb.setString("olá tablet", forType: .string)
        #expect(PasteboardReader.read(pb) == ClipPayload(mime: "text/plain", data: Data("olá tablet".utf8)))
    }

    @Test func readsPNGAsIs() {
        let png = Self.image(.png)
        pb.clearContents()
        pb.setData(png, forType: .png)
        #expect(PasteboardReader.read(pb) == ClipPayload(mime: "image/png", data: png))
    }

    @Test func convertsTIFFToPNG() throws {
        pb.clearContents()
        pb.setData(Self.image(.tiff), forType: .tiff)
        let payload = try #require(PasteboardReader.read(pb))
        #expect(payload.mime == "image/png")
        #expect(Self.isPNG(payload.data))
    }

    @Test func skipsPasswordManagerCopies() {
        pb.declareTypes([.string, .init("org.nspasteboard.ConcealedType")], owner: nil)
        pb.setString("senha", forType: .string)
        #expect(PasteboardReader.read(pb) == nil)
    }

    @Test func doesNotEchoWhatCameFromTheTablet() {
        PasteboardWriter.write(ClipPayload(mime: "text/plain", data: Data("do tablet".utf8)), to: pb)
        #expect(pb.string(forType: .string) == "do tablet")
        #expect(PasteboardReader.read(pb) == nil)
    }

    @Test func writesJPEGFromTabletAsPNGAndTIFF() {
        PasteboardWriter.write(ClipPayload(mime: "image/*", data: Self.image(.jpeg)), to: pb)
        #expect(Self.isPNG(pb.data(forType: .png) ?? Data()))
        #expect(pb.data(forType: .tiff) != nil)
    }

    @Test func readsImageFileCopiedInFinder() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("fileshare-test-\(UUID()).jpg")
        try Self.image(.jpeg).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        pb.clearContents()
        pb.writeObjects([url as NSURL])
        pb.setData(Self.image(.tiff, width: 16, height: 16), forType: .tiff) // Finder também põe o ícone como TIFF
        let payload = try #require(PasteboardReader.read(pb))
        #expect(payload.mime == "image/png")
        #expect(Self.isPNG(payload.data))
        let size = try #require(Self.size(payload.data))
        #expect(size == (4, 3)) // a imagem do arquivo, não o ícone
    }

    @Test func ignoresNonImageFilesInsteadOfSendingTheirIcon() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("fileshare-test-\(UUID()).txt")
        try Data("x".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        pb.clearContents()
        pb.writeObjects([url as NSURL])
        pb.setData(Self.image(.tiff), forType: .tiff)
        #expect(PasteboardReader.read(pb) == nil)
    }

    @Test func watcherReportsOnlyNewCopies() {
        var received: [ClipPayload] = []
        pb.clearContents()
        pb.setString("antes", forType: .string)
        let watcher = PasteboardWatcher(pasteboard: pb) { received.append($0) }
        watcher.poll()
        #expect(received.isEmpty)
        pb.clearContents()
        pb.setString("depois", forType: .string)
        watcher.poll()
        watcher.poll()
        #expect(received == [ClipPayload(mime: "text/plain", data: Data("depois".utf8))])
    }
}
