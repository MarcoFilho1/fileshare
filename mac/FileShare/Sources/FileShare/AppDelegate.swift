import AppKit
import FileShareCore
import ServiceManagement

/// Ícone na barra de menu: liga a área de transferência do Mac ao tablet nos dois sentidos.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let statusLine = NSMenuItem(title: "Iniciando…", action: nil, keyEquivalent: "")
    private let lastLine = NSMenuItem(title: "Nada enviado ainda", action: nil, keyEquivalent: "")
    private let pauseItem = NSMenuItem(title: "Pausar", action: #selector(togglePause), keyEquivalent: "p")
    private let pairItem = NSMenuItem(title: "Parear tablet…", action: #selector(pair), keyEquivalent: "")
    private let forgetItem = NSMenuItem(title: "Esquecer tablet", action: #selector(forget), keyEquivalent: "")
    private let loginItem = NSMenuItem(title: "Abrir ao iniciar o Mac", action: #selector(toggleLoginItem), keyEquivalent: "")
    private let pairingWindow = PairingWindow()

    private var server: TabletServer!
    private var watcher: PasteboardWatcher!
    private var connected = false
    private var paused = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        setUpMenu()

        server = TabletServer(
            macId: PairingStore.macId,
            onReceive: { [weak self] payload in self?.received(payload) },
            onState: { [weak self] state in self?.update(state) })
        let key = PairingStore.loadKey()
        forgetItem.isEnabled = key != nil
        server.setPairingKey(key)
        enableLoginItemOnFirstInstall()
        watcher = PasteboardWatcher { [weak self] payload in self?.copied(payload) }
        watcher.start()
    }

    private func setUpMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let menu = NSMenu()
        statusLine.isEnabled = false
        lastLine.isEnabled = false
        pauseItem.target = self
        pairItem.target = self
        forgetItem.target = self
        loginItem.target = self
        menu.autoenablesItems = false
        menu.addItem(statusLine)
        menu.addItem(lastLine)
        menu.addItem(.separator())
        menu.addItem(pauseItem)
        menu.addItem(pairItem)
        menu.addItem(forgetItem)
        menu.addItem(loginItem)
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
        case .unpaired: statusLine.title = "Nenhum tablet pareado: use Parear tablet…"
        case .waiting: statusLine.title = "Aguardando o tablet no Wi-Fi"
        case .connected(let name):
            statusLine.title = "Conectado: \(name) (Wi-Fi, criptografado)"
            pairingWindow.close()
        case .rejected: statusLine.title = "Recusei um aparelho sem a chave do pareamento"
        case .failed(let reason): statusLine.title = "Erro de rede: \(reason)"
        }
        if case .connected = state { connected = true } else { connected = false }
        updateIcon()
    }

    /// Gera uma chave nova (substitui o tablet anterior) e mostra o QR.
    @objc private func pair() {
        let key = SecureChannel.randomBytes(32)
        guard PairingStore.saveKey(key) else {
            return show(last: "Não consegui guardar a chave no Keychain")
        }
        forgetItem.isEnabled = true
        server.setPairingKey(key)
        pairingWindow.show(link: PairingLink.url(macId: PairingStore.macId, name: Host.current().localizedName ?? "Mac", key: key))
    }

    @objc private func forget() {
        PairingStore.deleteKey()
        forgetItem.isEnabled = false
        server.setPairingKey(nil)
    }

    // MARK: Abrir ao iniciar

    /// Na primeira vez que roda instalado em /Applications, já liga a abertura automática.
    private func enableLoginItemOnFirstInstall() {
        let key = "loginItemConfigured"
        if !UserDefaults.standard.bool(forKey: key), Bundle.main.bundlePath.hasPrefix("/Applications/") {
            UserDefaults.standard.set(true, forKey: key)
            try? SMAppService.mainApp.register()
        }
        refreshLoginItem()
    }

    @objc private func toggleLoginItem() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            show(last: "Não consegui mudar a abertura automática: \(error.localizedDescription)")
        }
        if service.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
        refreshLoginItem()
    }

    private func refreshLoginItem() {
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
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
