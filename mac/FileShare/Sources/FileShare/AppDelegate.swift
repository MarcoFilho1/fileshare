import AppKit
import FileShareCore
import ServiceManagement
import UniformTypeIdentifiers
import UserNotifications

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
    private let folderItem = NSMenuItem(title: "Abrir pasta de recebidos", action: #selector(openReceivedFolder), keyEquivalent: "")
    /// Só aparece quando os avisos estão desligados nos Ajustes (o macOS não pergunta duas vezes).
    private let notificationsItem = NSMenuItem(title: "Ativar notificações de arquivos…", action: #selector(openNotificationSettings), keyEquivalent: "")
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
            onState: { [weak self] state in self?.update(state) },
            onHeldDelivered: { [weak self] payload in self?.show(last: "Entregue ao tablet quando ele acordou: \(payload.summary)") },
            onFile: { [weak self] url, mime, from in self?.receivedFile(url, mime: mime, from: from) })
        setUpNotifications()
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
        folderItem.target = self
        notificationsItem.target = self
        notificationsItem.isHidden = true
        menu.autoenablesItems = false
        menu.addItem(statusLine)
        menu.addItem(lastLine)
        menu.addItem(.separator())
        menu.addItem(folderItem)
        menu.addItem(notificationsItem)
        menu.addItem(pauseItem)
        menu.addItem(pairItem)
        menu.addItem(forgetItem)
        menu.addItem(loginItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Sair do FileShare", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        menu.delegate = self
        statusItem.menu = menu
        updateIcon()
    }

    private func copied(_ payload: ClipPayload) {
        guard !paused else { return }
        server.send(payload) { [weak self] result in
            switch result {
            case .success(.delivered): self?.show(last: "Enviado ao tablet: \(payload.summary)")
            case .success(.held): self?.show(last: "Guardado até o tablet acordar: \(payload.summary)")
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

    // MARK: Arquivos do menu Compartilhar

    private func setUpNotifications() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if !granted { NSLog("FileShare: notificações desligadas \(error.map { "(\($0))" } ?? "")") }
            DispatchQueue.main.async { self.notificationsItem.isHidden = granted }
        }
    }

    @objc private func openNotificationSettings() {
        let id = Bundle.main.bundleIdentifier ?? "dev.marcofilho.fileshare"
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(id)")!)
    }

    @objc private func openReceivedFolder() {
        let folder = TabletServer.receivedFolder
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(folder)
    }

    /// Arquivo salvo em Downloads: avisa, e clicar no aviso abre o arquivo.
    private func receivedFile(_ url: URL, mime: String, from tablet: String) {
        let kind = Self.kind(of: mime)
        show(last: "\(kind) recebido: \(url.lastPathComponent)")
        let content = UNMutableNotificationContent()
        content.title = "\(kind) recebido de \(tablet)"
        content.body = "\(url.lastPathComponent) — clique para abrir"
        content.sound = .default
        content.userInfo = ["path": url.path]
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)) { error in
            if let error { NSLog("FileShare: não consegui mostrar o aviso: \(error)") }
        }
    }

    private static func kind(of mime: String) -> String {
        if mime == "application/pdf" { return "PDF" }
        if mime.hasPrefix("image/") { return "Imagem" }
        if mime.hasPrefix("video/") { return "Vídeo" }
        return "Arquivo"
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

extension AppDelegate: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        guard let path = response.notification.request.content.userInfo["path"] as? String else { return }
        await MainActor.run { _ = NSWorkspace.shared.open(URL(fileURLWithPath: path)) }
    }

    /// Mostra o aviso mesmo com o FileShare em primeiro plano (o menu aberto, por exemplo).
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}

extension AppDelegate: NSMenuDelegate {
    /// Reconfere os avisos a cada abertura do menu: some o item assim que forem ligados nos Ajustes.
    func menuWillOpen(_ menu: NSMenu) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let allowed = settings.authorizationStatus == .authorized
            DispatchQueue.main.async { self.notificationsItem.isHidden = allowed }
        }
    }
}
