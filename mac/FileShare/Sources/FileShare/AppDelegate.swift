import AppKit
import FileShareCore
import ServiceManagement
import UniformTypeIdentifiers
import UserNotifications

/// Ícone na barra de menu: liga a área de transferência do Mac ao tablet nos dois sentidos.
/// Clicar nele abre o painel de status (StatusPanel); arrastar um arquivo até perto dele abre o
/// painel Send to Tablet (DropPanel).
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let statusPanel = StatusPanelController()
    private let pairingWindow = PairingWindow()
    private let dropPanel = DropPanelController()
    private let dragWatcher = FileDragWatcher()
    private let sensors = ProximitySensors()

    private var server: TabletServer!
    private var watcher: PasteboardWatcher!
    private var connected = false
    private var paused = false

    private var status: StatusModel { statusPanel.model }

    func applicationDidFinishLaunching(_ notification: Notification) {
        setUpStatusItem()
        #if DEBUG
        if let state = ProcessInfo.processInfo.environment["FILESHARE_DEMO_PANEL"] { return demoPanel(state) }
        #endif

        server = TabletServer(
            macId: PairingStore.macId,
            onReceive: { [weak self] payload in self?.received(payload) },
            onState: { [weak self] state in self?.update(state) },
            onHeldDelivered: { [weak self] payload in
                self?.status.log(.toTablet, L10n.t("Delivered on wake: ", "Entregue ao acordar: ") + Self.describe(payload))
            },
            onFile: { [weak self] url, mime, from in self?.receivedFile(url, mime: mime, from: from) },
            onFileEvent: { [weak self] event in self?.fileEvent(event) })
        setUpNotifications()
        if let name = UserDefaults.standard.string(forKey: "tabletName") {
            dropPanel.model.tabletName = name
            status.tabletName = name
        }
        loadPairingKey()
        enableLoginItemOnFirstInstall()
        watcher = PasteboardWatcher { [weak self] payload in self?.copied(payload) }
        watcher.start()
        NSApp.servicesProvider = self
        NSUpdateDynamicServices()
        setUpDrop()
    }

    /// Lê a chave do pareamento fora da thread principal: se o macOS perguntar sobre o acesso às
    /// Chaves, o ícone e o painel continuam respondendo enquanto a pergunta está aberta.
    private func loadPairingKey() {
        DispatchQueue.global(qos: .userInitiated).async {
            let lookup = PairingStore.loadKey()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                switch lookup {
                case .found(let key):
                    self.setPaired(true)
                    self.server.setPairingKey(key)
                case .missing:
                    // primeira vez (ou tablet esquecido): já mostra como parear
                    self.setPaired(false)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { self.pair() }
                case .failed(let code):
                    // A chave continua lá: não abre o pareamento, que a substituiria. Tenta de novo
                    // quando o app for aberto outra vez.
                    NSLog("FileShare: não consegui ler a chave do pareamento nas Chaves (%d)", code)
                    self.setPaired(true)
                    self.status.log(.failed, L10n.t("Couldn't read the pairing key from the Keychain. Reopen FileShare and click Always Allow.",
                                                     "Não consegui ler a chave do pareamento nas Chaves. Abra o FileShare de novo e clique em Sempre permitir."))
                }
            }
        }
    }

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePanel)
        statusItem.button?.sendAction(on: [.leftMouseDown, .rightMouseDown])
        statusPanel.onVisibleChange = { [weak self] _ in self?.refreshHighlight() }
        status.actions = .init(
            togglePause: { [weak self] in self?.togglePause() },
            toggleLogin: { [weak self] in self?.toggleLoginItem() },
            sendFile: { [weak self] in self?.chooseFilesToSend() },
            openFolder: { [weak self] in self?.statusPanel.hide(); self?.openReceivedFolder() },
            pair: { [weak self] in self?.statusPanel.hide(); self?.pair() },
            forget: { [weak self] in self?.statusPanel.hide(); self?.confirmForget() },
            enableNotifications: { [weak self] in self?.statusPanel.hide(); self?.openNotificationSettings() },
            quit: { NSApp.terminate(nil) })
        updateIcon()
    }

    @objc private func togglePanel() {
        guard let icon = iconFrame(near: NSEvent.mouseLocation) else { return }
        if statusPanel.isVisible { return statusPanel.hide() }
        // confere os avisos antes de abrir: a linha "Ativar notificações" não aparece depois, empurrando as outras
        guard Bundle.main.bundleIdentifier != nil else { return statusPanel.show(below: icon) }
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let allowed = settings.authorizationStatus == .authorized
            DispatchQueue.main.async {
                self.status.notificationsAllowed = allowed
                self.statusPanel.show(below: icon)
            }
        }
    }

    /// O ⇄ fica aceso enquanto um dos painéis está aberto, como a Central de Controle.
    private func refreshHighlight() {
        statusItem.button?.highlight(statusPanel.isVisible || dropPanel.isVisible)
    }

    private func copied(_ payload: ClipPayload) {
        guard !paused else { return }
        server.send(payload) { [weak self] result in
            switch result {
            case .success(.delivered): self?.status.log(.toTablet, Self.describe(payload))
            case .success(.held): self?.status.log(.waiting, Self.describe(payload))
            case .failure(let error): self?.status.log(.failed, error.localizedDescription)
            }
        }
    }

    private func received(_ payload: ClipPayload) {
        guard !paused else { return }
        if PasteboardWriter.write(payload, to: .general) {
            status.log(.fromTablet, Self.describe(payload))
        } else {
            status.log(.failed, L10n.t("Couldn't open the received image", "Não consegui abrir a imagem recebida"))
        }
    }

    /// Como uma cópia aparece na lista de atividade: o começo do texto, ou "Imagem (150 KB)".
    private static func describe(_ payload: ClipPayload) -> String {
        if payload.isImage {
            return L10n.t("Image", "Imagem") + " (\(ByteCountFormatter.string(fromByteCount: Int64(payload.data.count), countStyle: .file)))"
        }
        let text = String(decoding: payload.data, as: UTF8.self)
            .components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
        return "“\(text.count > 60 ? String(text.prefix(60)) + "…" : text)”"
    }

    // MARK: Arquivos Mac → tablet

    private func chooseFilesToSend() {
        statusPanel.hide()
        let panel = NSOpenPanel()
        panel.title = L10n.t("Send to Tablet", "Enviar ao tablet")
        panel.prompt = L10n.t("Send", "Enviar")
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
        dropPanel.onDrop = { [weak self] urls in
            self?.sensors.hide()
            self?.server.sendFiles(urls)
        }
        dropPanel.onVisibleChange = { [weak self] _ in self?.refreshHighlight() }
        dragWatcher.onDragStart = { [weak self] in
            guard let self, !dropPanel.model.isTransferring else { return }
            statusPanel.hide()
            sensors.show(below: allIconFrames)
        }
        sensors.onFileNear = { [weak self] icon in
            guard let self else { return }
            dropPanel.show(below: icon)
        }
        dragWatcher.onMove = { [weak self] point in
            self?.dropPanel.dragMoved(to: point, nearZones: self?.sensors.zones ?? [])
        }
        dragWatcher.onEnd = { [weak self] in
            guard let self else { return }
            sensors.hide()
            if dropPanel.model.batch.isEmpty { dropPanel.hide(after: 0.3) }
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

    /// O ⇄ em todas as telas.
    fileprivate var allIconFrames: [NSRect] {
        NSScreen.screens.compactMap { iconFrame(near: NSPoint(x: $0.frame.midX, y: $0.frame.midY)) }
    }

    /// O ⇄ aparece na barra de menu de cada tela, à mesma distância da borda direita, mas o AppKit
    /// só diz onde ele está numa delas: nas outras, a posição é calculada.
    fileprivate func iconFrame(near point: NSPoint) -> NSRect? {
        guard let base = iconFrame else { return nil }
        let screens = NSScreen.screens
        guard let home = screens.first(where: { NSMouseInRect(NSPoint(x: base.midX, y: base.midY), $0.frame, false) }),
              let here = screens.first(where: { NSMouseInRect(point, $0.frame, false) }),
              here != home else { return base }
        let fromRight = home.frame.maxX - base.minX
        let bar = here.frame.maxY - here.visibleFrame.maxY
        let height = bar > 0 ? bar : base.height
        return NSRect(x: here.frame.maxX - fromRight, y: here.frame.maxY - height, width: base.width, height: height)
    }

    fileprivate func droppedFiles(_ info: NSDraggingInfo) -> [URL] {
        info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
    }

    private func fileEvent(_ event: TabletServer.FileEvent) {
        dropPanel.handle(event)
        switch event {
        case .queued(let name):
            status.sending = nil
            if !status.activity.contains(where: { $0.kind == .waiting && $0.text == name }) { status.log(.waiting, name) }
        case .progress(let name, let fraction): status.sending = (name, fraction)
        case .delivered(let name):
            status.sending = nil
            status.log(.toTablet, name)
        case .failed(let name, let reason):
            status.sending = nil
            status.log(.failed, "\(name): \(reason)")
        }
    }

    // MARK: Arquivos do menu Compartilhar

    private func setUpNotifications() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if !granted { NSLog("FileShare: notificações desligadas \(error.map { "(\($0))" } ?? "")") }
            DispatchQueue.main.async { self.status.notificationsAllowed = granted }
        }
    }

    private func openNotificationSettings() {
        let id = Bundle.main.bundleIdentifier ?? "dev.marcofilho.fileshare"
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(id)")!)
    }

    private func openReceivedFolder() {
        let folder = TabletServer.receivedFolder
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(folder)
    }

    /// Arquivo salvo em Downloads: avisa, e clicar no aviso abre o arquivo.
    private func receivedFile(_ url: URL, mime: String, from tablet: String) {
        let kind = Self.kind(of: mime)
        status.log(.fromTablet, url.lastPathComponent)
        let content = UNMutableNotificationContent()
        content.title = L10n.t("\(kind) from \(tablet)", "\(kind) recebido de \(tablet)")
        content.body = url.lastPathComponent + L10n.t(" — click to open", " — clique para abrir")
        content.sound = .default
        content.userInfo = ["path": url.path]
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)) { error in
            if let error { NSLog("FileShare: não consegui mostrar o aviso: \(error)") }
        }
    }

    private static func kind(of mime: String) -> String {
        if mime == "application/pdf" { return "PDF" }
        if mime.hasPrefix("image/") { return L10n.t("Image", "Imagem") }
        if mime.hasPrefix("video/") { return L10n.t("Video", "Vídeo") }
        return L10n.t("File", "Arquivo")
    }

    private func update(_ state: TabletServer.State) {
        switch state {
        case .unpaired: status.link = .unpaired
        case .waiting: status.link = .searching
        case .connected(let name):
            status.link = .connected
            status.tabletName = name
            dropPanel.model.tabletName = name
            UserDefaults.standard.set(name, forKey: "tabletName") // os painéis mostram o nome mesmo com o tablet dormindo
            pairingWindow.connected(to: name)
        case .rejected: status.link = .rejected
        case .failed(let reason): status.link = .failed(reason)
        }
        connected = status.link == .connected
        dropPanel.model.connected = connected
        updateIcon()
    }

    private func setPaired(_ paired: Bool) {
        dropPanel.model.paired = paired
        if !paired { status.link = .unpaired } else if status.link == .unpaired { status.link = .searching }
    }

    /// Gera uma chave nova (substitui o tablet anterior) e mostra o QR.
    private func pair() {
        let key = SecureChannel.randomBytes(32)
        guard PairingStore.saveKey(key) else {
            return status.log(.failed, L10n.t("Couldn't save the key in the Keychain", "Não consegui guardar a chave no Keychain"))
        }
        setPaired(true)
        server.setPairingKey(key)
        pairingWindow.show(link: PairingLink.url(macId: PairingStore.macId, name: Host.current().localizedName ?? "Mac", key: key))
    }

    /// Esquecer exige ler um QR de novo para voltar: pede confirmação, como o macOS faz.
    private func confirmForget() {
        let alert = NSAlert()
        alert.messageText = L10n.t("Forget \(status.tabletName)?", "Esquecer o \(status.tabletName)?")
        alert.informativeText = L10n.t("To connect again, you'll need to scan a new QR code on the tablet.",
                                       "Para conectar de novo, será preciso ler um QR code novo no tablet.")
        alert.alertStyle = .warning
        alert.icon = NSApp.applicationIconImage
        alert.addButton(withTitle: L10n.t("Forget", "Esquecer")).hasDestructiveAction = true
        alert.addButton(withTitle: L10n.t("Cancel", "Cancelar"))
        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn { forget() }
    }

    private func forget() {
        PairingStore.deleteKey()
        setPaired(false)
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

    private func toggleLoginItem() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            status.log(.failed, error.localizedDescription)
        }
        if service.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
        refreshLoginItem()
    }

    private func refreshLoginItem() {
        status.openAtLogin = SMAppService.mainApp.status == .enabled
    }

    private func togglePause() {
        paused.toggle()
        status.paused = paused
        updateIcon()
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
    private func demoStatus(_ state: String) {
        status.tabletName = "Galaxy Tab S9 FE"
        status.link = state == "status-unpaired" ? .unpaired : state == "status-asleep" ? .searching : .connected
        status.openAtLogin = true
        status.notificationsAllowed = state != "status-asleep"
        if state == "status" || state == "status-asleep" {
            status.log(.toTablet, L10n.t("“Meeting at 3pm, room 2”", "“Reunião às 15h na sala 2”"))
            status.log(.fromTablet, L10n.t("Geography - class 7.pdf", "Geografia - aula 7.pdf"))
            status.log(.toTablet, L10n.t("Image (1.2 MB)", "Imagem (1,2 MB)"))
            status.sending = (L10n.t("Class 7 - slides.pdf", "Aula 7 - slides.pdf"), 0.45)
        }
        statusPanel.keepOpen = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [self] in
            if state == "pairing" || state == "paired" {
                pairingWindow.show(link: PairingLink.url(macId: "demo", name: "Mac", key: Data(count: 32))) // chave falsa, só para a foto
                if state == "paired" { DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.pairingWindow.connected(to: "Galaxy Tab S9 FE", closeAfter: false) } }
                return
            }
            guard let icon = iconFrame else { return }
            statusPanel.show(below: icon)
        }
    }

    /// Só na versão de desenvolvimento: mostra o painel num estado fixo, para conferir o visual.
    private func demoPanel(_ state: String) {
        // fora do pacote .app não há ícone: usa o gerado pelo script
        if let icon = NSImage(contentsOfFile: "Resources/AppIcon.icns") { NSApp.applicationIconImage = icon }
        if ProcessInfo.processInfo.environment["FILESHARE_DEMO_DARK"] != nil { NSApp.appearance = NSAppearance(named: .darkAqua) }
        if state.hasPrefix("status") || state.hasPrefix("pair") { return demoStatus(state) }
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

/// O ícone ⇄ fica numa janela própria da barra de menu: ela também recebe os arquivos arrastados.
extension AppDelegate: NSWindowDelegate, NSDraggingDestination {
    func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard dropPanel.model.paired, !dropPanel.model.isTransferring, !droppedFiles(sender).isEmpty else { return [] }
        if let icon = iconFrame(near: NSEvent.mouseLocation) { dropPanel.show(below: icon) }
        dropPanel.setTargeted(true)
        return .copy
    }

    func draggingExited(_ sender: NSDraggingInfo?) {
        dropPanel.setTargeted(false)
    }

    func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = droppedFiles(sender)
        guard !urls.isEmpty else { return false }
        sensors.hide()
        dropPanel.accept(urls)
        return true
    }
}
