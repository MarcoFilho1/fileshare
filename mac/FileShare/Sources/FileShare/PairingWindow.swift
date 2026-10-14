import AppKit
import CoreImage.CIFilterBuiltins

/// Janela com o QR de pareamento.
@MainActor
final class PairingWindow {
    private var window: NSWindow?

    func show(link: String) {
        window?.close()
        let qr = NSImageView(image: Self.qrImage(link, size: 280))
        qr.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: "Parear o tablet")
        title.font = .boldSystemFont(ofSize: 17)
        let steps = NSTextField(wrappingLabelWithString:
            "1. No tablet, abra a Câmera e aponte para o código.\n" +
            "2. Toque no link que aparecer e escolha abrir com o FileShare.\n\n" +
            "O código contém a chave secreta do pareamento: não compartilhe. " +
            "Parear de novo substitui o tablet anterior.")
        steps.preferredMaxLayoutWidth = 300

        let stack = NSStackView(views: [title, qr, steps])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 24, bottom: 24, right: 24)
        NSLayoutConstraint.activate([qr.widthAnchor.constraint(equalToConstant: 280), qr.heightAnchor.constraint(equalToConstant: 280)])

        let w = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = "FileShare"
        w.contentView = stack
        w.isReleasedWhenClosed = false
        w.center()
        window = w
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.close()
        window = nil
    }

    private static func qrImage(_ text: String, size: CGFloat) -> NSImage {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return NSImage() }
        let scale = size / output.extent.width
        let rep = NSCIImageRep(ciImage: output.transformed(by: CGAffineTransform(scaleX: scale, y: scale)))
        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        return image
    }
}
