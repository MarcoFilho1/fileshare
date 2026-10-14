import AppKit
import FileShareCore

/// Ícone na barra de menu: liga a área de transferência do Mac ao tablet nos dois sentidos.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let statusLine = NSMenuItem(title: "Iniciando…", action: nil, keyEquivalent: "")
    private let lastLine = NSMenuItem(title: "Nada enviado ainda", action: nil, keyEquivalent: "")
    private let pauseItem = NSMenuItem(title: "Pausar", action: #selector(togglePause), keyEquivalent: "p")

    private var server: TabletServer!
    private var watcher: PasteboardWatcher!
    private var connected = false
    private var paused = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        setUpMenu()

        server = TabletServer(
            onReceive: { [weak self] payload in self?.received(payload) },
            onState: { [weak self] state in self?.update(state) })
        server.start()
        watcher = PasteboardWatcher { [weak self] payload in self?.copied(payload) }
        watcher.start()
    }

    private func setUpMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let menu = NSMenu()
        statusLine.isEnabled = false
        lastLine.isEnabled = false
        pauseItem.target = self
        menu.addItem(statusLine)
        menu.addItem(lastLine)
        menu.addItem(.separator())
        menu.addItem(pauseItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Sair do FileShare", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
        updateIcon()
    }

    private func copied(_ payload: ClipPayload) {
        guard !paused, connected else { return }
        server.send(payload) { [weak self] result in
            switch result {
            case .success: self?.show(last: "Enviado ao tablet: \(payload.summary)")
            case .failure(let error): self?.show(last: "Falha ao enviar: \(error.localizedDescription)")
            }
        }
    }

    private func received(_ payload: ClipPayload) {
        guard !paused else { return }
        if PasteboardWriter.write(payload, to: .general) {
            show(last: "Recebido do tablet: \(payload.summary)")
        } else {
            show(last: "Não consegui abrir a imagem recebida")
        }
    }

    private func update(_ state: TabletServer.State) {
        switch state {
        case .starting: statusLine.title = "Iniciando…"
        case .waiting: statusLine.title = "Aguardando o tablet no Wi-Fi"
        case .connected(let name): statusLine.title = "Conectado: \(name) (Wi-Fi)"
        case .failed(let reason): statusLine.title = "Erro de rede: \(reason)"
        }
        if case .connected = state { connected = true } else { connected = false }
        updateIcon()
    }

    @objc private func togglePause() {
        paused.toggle()
        pauseItem.title = paused ? "Retomar" : "Pausar"
        updateIcon()
    }

    private func show(last text: String) {
        let time = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .short)
        lastLine.title = "\(text) às \(time)"
    }

    private func updateIcon() {
        let symbol = paused ? "pause.circle" : connected ? "arrow.left.arrow.right.circle.fill" : "arrow.left.arrow.right.circle"
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "FileShare")
        image?.isTemplate = true
        statusItem.button?.image = image
    }
}
