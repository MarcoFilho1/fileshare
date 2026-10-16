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
    private let sendFileItem = NSMenuItem(title: "Enviar arquivo ao tablet…", action: #selector(chooseFilesToSend), keyEquivalent: "")
    private let folderItem = NSMenuItem(title: "Abrir pasta de recebidos", action: #selector(openReceivedFolder), keyEquivalent: "")
    /// Só aparece quando os avisos estão desligados nos Ajustes (o macOS não pergunta duas vezes).
    private let notificationsItem = NSMenuItem(title: "Ativar notificações de arquivos…", action: #selector(openNotificationSettings), keyEquivalent: "")
    private let pairingWindow = PairingWindow()
    private let dropPanel = DropPanelController()
    private let dragWatcher = FileDragWatcher()

    private var server: TabletServer!
    private var watcher: PasteboardWatcher!
    private var connected = false
    private var paused = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        setUpMenu()
        #if DEBUG
        if let state = ProcessInfo.processInfo.environment["FILESHARE_DEMO_PANEL"] { return demoPanel(state) }
        #endif

        server = TabletServer(
            macId: PairingStore.macId,
            onReceive: { [weak self] payload in self?.received(payload) },
            onState: { [weak self] state in self?.update(state) },
            onHeldDelivered: { [weak self] payload in self?.show(last: "Entregue ao tablet quando ele acordou: \(payload.summary)") },
            onFile: { [weak self] url, mime, from in self?.receivedFile(url, mime: mime, from: from) },
            onFileEvent: { [weak self] event in self?.fileEvent(event) })
        setUpNotifications()
        let key = PairingStore.loadKey()
        forgetItem.isEnabled = key != nil
        dropPanel.model.paired = key != nil
        if let name = UserDefaults.standard.string(forKey: "tabletName") { dropPanel.model.tabletName = name }
        server.setPairingKey(key)
        enableLoginItemOnFirstInstall()
        watcher = PasteboardWatcher { [weak self] payload in self?.copied(payload) }
        watcher.start()
        NSApp.servicesProvider = self
        NSUpdateDynamicServices()
        setUpDrop()
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
        sendFileItem.target = self
        notificationsItem.target = self
        notificationsItem.isHidden = true
        menu.autoenablesItems = false
        menu.addItem(statusLine)
        menu.addItem(lastLine)
        menu.addItem(.separator())
        menu.addItem(sendFileItem)
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

    // MARK: Arquivos Mac → tablet

    @objc private func chooseFilesToSend() {
        let panel = NSOpenPanel()
        panel.title = "Enviar ao tablet"
        panel.prompt = "Enviar"
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        NSApp.activate()
        guard panel.runModal() == .OK else { return }
        server.sendFiles(panel.urls)
    }

    /// Finder: botão direito → Enviar ao tablet (NSServices no Info.plist).
    @objc func sendToTablet(_ pboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        let urls = pboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        guard !urls.isEmpty else { return }
        server.sendFiles(urls)
    }

    /// Arrastar arquivos até o ícone ⇄: ao chegar perto, o painel "Send to Tablet" sai do ícone.
    private func setUpDrop() {
        dropPanel.onDrop = { [weak self] urls in self?.server.sendFiles(urls) }
        dropPanel.onVisibleChange = { [weak self] on in self?.statusItem.button?.highlight(on) }
        dragWatcher.onMove = { [weak self] point in
            guard let self, let icon = iconFrame else { return }
            dropPanel.dragMoved(to: point, iconFrame: icon)
        }
        dragWatcher.onEnd = { [weak self] in
            guard let self, dropPanel.model.batch.isEmpty else { return }
            dropPanel.hide(after: 0.3)
        }
        dragWatcher.start()
        guard let window = statusItem.button?.window else { return }
        window.registerForDraggedTypes([.fileURL])
        window.delegate = self
    }

    /// Onde o ícone ⇄ está na tela.
    fileprivate var iconFrame: NSRect? {
        guard let button = statusItem.button, let window = button.window else { return nil }
        return window.convertToScreen(button.convert(button.bounds, to: nil))
    }

    fileprivate func droppedFiles(_ info: NSDraggingInfo) -> [URL] {
        info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
    }

    private func fileEvent(_ event: TabletServer.FileEvent) {
        dropPanel.handle(event)
        switch event {
        case .queued(let name): show(last: "\(name) vai quando o tablet acordar")
        case .progress(let name, let fraction):
            lastLine.title = "Enviando \(name) ao tablet… \(Int(fraction * 100))%"
        case .delivered(let name): show(last: "Enviado ao tablet: \(name)")
        case .failed(let name, let reason): show(last: "Não enviei \(name): \(reason)")
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
        if case .connected(let name) = state {
            connected = true
            dropPanel.model.tabletName = name
            UserDefaults.standard.set(name, forKey: "tabletName") // o painel mostra o nome mesmo com o tablet dormindo
        } else {
            connected = false
        }
        dropPanel.model.connected = connected
        updateIcon()
    }

    /// Gera uma chave nova (substitui o tablet anterior) e mostra o QR.
    @objc private func pair() {
        let key = SecureChannel.randomBytes(32)
        guard PairingStore.saveKey(key) else {
            return show(last: "Não consegui guardar a chave no Keychain")
        }
        forgetItem.isEnabled = true
        dropPanel.model.paired = true
        server.setPairingKey(key)
        pairingWindow.show(link: PairingLink.url(macId: PairingStore.macId, name: Host.current().localizedName ?? "Mac", key: key))
    }

    @objc private func forget() {
        PairingStore.deleteKey()
        forgetItem.isEnabled = false
        dropPanel.model.paired = false
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

#if DEBUG
extension AppDelegate {
    /// Só na versão de desenvolvimento: mostra o painel num estado fixo, para conferir o visual.
    private func demoPanel(_ state: String) {
        let model = dropPanel.model
        dropPanel.keepOpen = true
        if ProcessInfo.processInfo.environment["FILESHARE_DEMO_DARK"] != nil { NSApp.appearance = NSAppearance(named: .darkAqua) }
        model.paired = state != "unpaired"
        model.connected = state != "asleep"
        model.tabletName = "Galaxy Tab S9 FE"
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [self] in
            guard let icon = iconFrame else { return }
            dropPanel.show(below: icon)
            statusItem.button?.highlight(true)
            let files = [URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app/Contents/Info.plist")]
            switch state {
            case "targeted": dropPanel.setTargeted(true)
            case "sending":
                model.begin(files)
                model.handle(.progress(name: "Info.plist", fraction: 0.62))
            case "sent":
                model.begin(files)
                model.handle(.delivered(name: "Info.plist"))
            case "queued":
                model.begin(files)
                model.handle(.queued(name: "Info.plist"))
            default: break
            }
        }
    }
}
#endif

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

/// O ícone ⇄ fica numa janela própria da barra de menu: ela também recebe os arquivos arrastados.
extension AppDelegate: NSWindowDelegate, NSDraggingDestination {
    func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard dropPanel.model.paired, !dropPanel.model.isTransferring, !droppedFiles(sender).isEmpty else { return [] }
        if let icon = iconFrame { dropPanel.show(below: icon) }
        dropPanel.setTargeted(true)
        return .copy
    }

    func draggingExited(_ sender: NSDraggingInfo?) {
        dropPanel.setTargeted(false)
    }

    func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = droppedFiles(sender)
        guard !urls.isEmpty else { return false }
        dropPanel.accept(urls)
        return true
    }
}
