import AppKit
import CoreImage.CIFilterBuiltins
import Observation
import SwiftUI

/// Janela de pareamento: o QR que o tablet lê com a câmera e, quando ele conecta, a confirmação.
@MainActor
final class PairingWindow {
    private var window: NSWindow?
    private let model = PairingModel()

    func show(link: String) {
        model.qr = Self.qrImage(link, size: 440)
        model.connectedName = nil
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 600),
                             styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isMovableByWindowBackground = true
            w.isReleasedWhenClosed = false
            w.contentViewController = NSHostingController(rootView: PairingView(model: model))
            window = w
        }
        window?.center()
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    /// O tablet conectou com a chave nova: mostra o ✓ e fecha sozinha.
    func connected(to name: String, closeAfter: Bool = true) {
        guard let window, window.isVisible, model.connectedName == nil else { return }
        withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { model.connectedName = name }
        if closeAfter { DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { [weak self] in self?.close() } }
    }

    func close() {
        window?.close()
    }

    /// QR com correção alta: aguenta o ícone do FileShare no meio.
    private static func qrImage(_ text: String, size: CGFloat) -> NSImage {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "H"
        guard let output = filter.outputImage else { return NSImage() }
        let scale = (size / output.extent.width).rounded(.down)
        let rep = NSCIImageRep(ciImage: output.transformed(by: CGAffineTransform(scaleX: scale, y: scale)))
        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        return image
    }
}

@MainActor @Observable
private final class PairingModel {
    var qr = NSImage()
    var connectedName: String?
}

private struct PairingView: View {
    let model: PairingModel

    var body: some View {
        VStack(spacing: 0) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 72, height: 72)
                .padding(.top, 36)
            Text(L10n.t("Pair Your Tablet", "Parear o seu tablet"))
                .font(.system(size: 22, weight: .bold))
                .padding(.top, 12)
            Text(L10n.t("FileShare links this Mac to your Android tablet over Wi-Fi, end-to-end encrypted.",
                        "O FileShare liga este Mac ao seu tablet Android pelo Wi-Fi, com criptografia de ponta a ponta."))
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 40)
                .padding(.top, 6)

            ZStack {
                if let name = model.connectedName {
                    VStack(spacing: 14) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 72))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .green)
                            .symbolEffect(.bounce, value: name)
                        Text(L10n.t("Connected to \(name)", "Conectado ao \(name)"))
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .transition(.blurReplace)
                } else {
                    qrCard.transition(.blurReplace)
                }
            }
            .frame(height: 270)
            .padding(.top, 22)

            if model.connectedName == nil {
                VStack(alignment: .leading, spacing: 12) {
                    Step(number: 1, text: L10n.t("On the tablet, open the Camera and point it at the code.",
                                                 "No tablet, abra a Câmera e aponte para o código."))
                    Step(number: 2, text: L10n.t("Tap the link and then Connect. No FileShare on the tablet yet? The page shows how to install it.",
                                                 "Toque no link e depois em Conectar. Ainda não tem o FileShare no tablet? A página mostra como instalar."))
                    Step(number: 3, text: L10n.t("That's it: from then on they find each other on Wi-Fi.",
                                                 "Pronto: depois disso eles se acham sozinhos no Wi-Fi."))
                }
                .padding(.horizontal, 44)
                .padding(.top, 18)
                .transition(.opacity)

                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "lock.fill").font(.system(size: 11))
                    Text(L10n.t("The code holds this pairing's secret key, so don't share it. Pairing again replaces the previous tablet.",
                                "O código contém a chave secreta do pareamento: não compartilhe. Parear de novo substitui o tablet anterior."))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 44)
                .padding(.top, 18)

                Link(L10n.t("Get FileShare for Android", "Baixar o FileShare para Android"),
                     destination: URL(string: "https://marcofilho1.github.io/fileshare/")!)
                    .font(.system(size: 12))
                    .padding(.top, 12)
            }
            Spacer(minLength: 28)
        }
        .frame(width: 440, height: 640)
        .background(.background)
    }

    private var qrCard: some View {
        VStack(spacing: 12) {
            ZStack {
                Image(nsImage: model.qr)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 200, height: 200)
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 46, height: 46)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white).padding(-3))
            }
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(.white))
            .shadow(color: .black.opacity(0.12), radius: 14, y: 6)
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text(L10n.t("Waiting for the tablet…", "Esperando o tablet…"))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct Step: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.accentColor))
            Text(text)
                .font(.system(size: 13))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
        }
    }
}
