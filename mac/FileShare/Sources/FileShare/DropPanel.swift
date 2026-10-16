import AppKit
import Observation
import SwiftUI

// Painel "Send to Tablet": quando um arquivo arrastado chega perto do ícone ⇄, um painel de vidro
// sai de dentro do ícone, como a Central de Controle, e recebe o arquivo.

/// Textos do painel no idioma do sistema.
enum DropText {
    static let portuguese = Locale.preferredLanguages.first?.hasPrefix("pt") == true

    static func t(_ english: String, _ portuguese: String) -> String {
        Self.portuguese ? portuguese : english
    }
}

@MainActor @Observable
final class DropModel {
    enum FileStatus: Equatable {
        case waiting
        case sending(Double)
        case delivered
        case queued
        case failed(String)
    }

    enum Outcome: Equatable {
        case sent, queued
        case failed(String)
    }

    var visible = false
    /// Arquivo arrastado em cima do painel ou do ícone.
    var targeted = false
    var paired = true
    var connected = false
    var tabletName = "Tablet"
    /// Ponto do painel de onde ele cresce (o ícone), de 0 a 1 na largura.
    var anchorX = 0.5

    /// Arquivos soltos agora, na ordem; vazio enquanto ninguém soltou nada.
    private(set) var batch: [String] = []
    private(set) var status: [String: FileStatus] = [:]
    private(set) var batchIcon: NSImage?

    var isTransferring: Bool { !batch.isEmpty && outcome == nil }

    var progress: Double {
        guard !batch.isEmpty else { return 0 }
        let total = batch.reduce(0.0) { sum, name in
            switch status[name] {
            case .sending(let f): sum + f
            case .delivered, .failed: sum + 1
            default: sum
            }
        }
        return total / Double(batch.count)
    }

    /// Resultado quando todos os arquivos tiveram um destino.
    var outcome: Outcome? {
        guard !batch.isEmpty else { return nil }
        let all = batch.compactMap { status[$0] }
        guard all.count == batch.count else { return nil }
        if let reason = all.lazy.compactMap({ if case .failed(let r) = $0 { r } else { nil } }).first { return .failed(reason) }
        if all.allSatisfy({ $0 == .delivered }) { return .sent }
        if all.allSatisfy({ $0 == .delivered || $0 == .queued }) { return .queued }
        return nil
    }

    var batchTitle: String {
        batch.count == 1 ? batch[0] : DropText.t("\(batch.count) files", "\(batch.count) arquivos")
    }

    func begin(_ urls: [URL]) {
        batch = urls.map(\.lastPathComponent)
        status = Dictionary(batch.map { ($0, FileStatus.waiting) }, uniquingKeysWith: { a, _ in a })
        batchIcon = NSWorkspace.shared.icon(forFiles: urls.map(\.path))
    }

    func reset() {
        batch = []
        status = [:]
        batchIcon = nil
        targeted = false
    }

    func handle(_ event: TabletServer.FileEvent) {
        switch event {
        case .queued(let name): set(name, .queued)
        case .progress(let name, let fraction): set(name, .sending(fraction))
        case .delivered(let name): set(name, .delivered)
        case .failed(let name, let reason): set(name, .failed(reason))
        }
    }

    private func set(_ name: String, _ value: FileStatus) {
        guard status[name] != nil else { return }
        status[name] = value
    }
}

// MARK: Visual

struct DropPanelView: View {
    static let width: CGFloat = 288
    static let cornerRadius: CGFloat = 24
    /// Folga em volta do vidro para a sombra.
    static let margin: CGFloat = 26

    let model: DropModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        panel
            .frame(width: Self.width)
            .scaleEffect(model.visible ? 1 : (reduceMotion ? 0.98 : 0.35), anchor: UnitPoint(x: model.anchorX, y: 0))
            .opacity(model.visible ? 1 : 0)
            .blur(radius: model.visible || reduceMotion ? 0 : 6)
            .padding(.horizontal, Self.margin)
            .padding(.top, 2)
            .padding(.bottom, Self.margin)
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            tile
        }
        .padding(10)
        .modifier(GlassBackground(cornerRadius: Self.cornerRadius))
        .shadow(color: .black.opacity(0.22), radius: 18, y: 8)
    }

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(model.connected && model.paired ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary))
                Image(systemName: "ipad.landscape")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(model.connected && model.paired ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
            }
            .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(DropText.t("Send to Tablet", "Enviar ao Tablet"))
                    .font(.system(size: 13, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .contentTransition(.opacity)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .padding(.top, 4)
    }

    private var subtitle: String {
        if !model.paired { return DropText.t("No tablet paired", "Nenhum tablet pareado") }
        if model.connected { return model.tabletName }
        return DropText.t("Asleep · files will wait", "Dormindo · os arquivos esperam")
    }

    private var tile: some View {
        let lit = model.targeted && model.paired && model.batch.isEmpty
        return ZStack {
            RoundedRectangle(cornerRadius: Self.cornerRadius - 10, style: .continuous)
                .fill(lit ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color.primary.opacity(0.06)))
            Group {
                if let outcome = model.outcome {
                    result(outcome)
                } else if !model.batch.isEmpty {
                    transfer
                } else {
                    dropTarget(lit: lit)
                }
            }
            .transition(.blurReplace)
        }
        .frame(height: 128)
        .scaleEffect(lit && !reduceMotion ? 1.02 : 1)
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: lit)
        .animation(.smooth(duration: 0.3), value: model.outcome)
        .animation(.smooth(duration: 0.3), value: model.batch)
    }

    private func dropTarget(lit: Bool) -> some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(lit ? AnyShapeStyle(.white) : AnyShapeStyle(Color.primary.opacity(0.08)))
                Image(systemName: model.paired ? "arrow.down" : "link")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(lit ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
                    .symbolEffect(.bounce, value: lit)
            }
            .frame(width: 44, height: 44)
            Text(dropLabel(lit: lit))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(lit ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
                .contentTransition(.opacity)
        }
    }

    private func dropLabel(lit: Bool) -> String {
        if !model.paired { return DropText.t("Pair a tablet in the ⇄ menu", "Pareie um tablet no menu ⇄") }
        return lit ? DropText.t("Release to send", "Solte para enviar") : DropText.t("Drop files here", "Solte os arquivos aqui")
    }

    private var transfer: some View {
        HStack(spacing: 12) {
            if let icon = model.batchIcon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 48, height: 48)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(model.batchTitle)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                // barra própria: a do sistema fica cinza porque o FileShare nunca está em primeiro plano
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.1))
                        Capsule()
                            .fill(Color.accentColor)
                            .frame(width: max(6, geo.size.width * model.progress))
                            .animation(.smooth(duration: 0.25), value: model.progress)
                    }
                }
                .frame(height: 6)
                Text(DropText.t("Sending… \(Int(model.progress * 100))%", "Enviando… \(Int(model.progress * 100))%"))
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
        }
        .padding(.horizontal, 16)
    }

    private func result(_ outcome: DropModel.Outcome) -> some View {
        let (symbol, color, text): (String, Color, String) = switch outcome {
        case .sent: ("checkmark.circle.fill", .green, DropText.t("Sent to \(model.tabletName)", "Enviado ao \(model.tabletName)"))
        case .queued: ("clock.fill", .orange, DropText.t("Will send when \(model.tabletName) wakes", "Vai quando o \(model.tabletName) acordar"))
        case .failed(let reason): ("exclamationmark.triangle.fill", .red, DropText.t("Not sent: \(reason)", "Não enviado: \(reason)"))
        }
        return VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 34))
                .symbolRenderingMode(.palette)
                // o relógio tem as camadas ao contrário do check e do alerta
                .foregroundStyle(outcome == .queued ? color : .white, outcome == .queued ? .white : color)
                .symbolEffect(.bounce, value: outcome)
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .padding(.horizontal, 16)
    }
}

/// Vidro do macOS 26 (o da Central de Controle) sobre o desfoque do que está atrás da janela,
/// para o texto continuar legível em cima de qualquer fundo.
private struct GlassBackground: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let frosted = content.background(BehindWindowBlur().clipShape(shape))
        if #available(macOS 26, *) {
            frosted.glassEffect(.regular, in: shape)
        } else {
            frosted.overlay(shape.strokeBorder(.white.opacity(0.15)))
        }
    }
}

private struct BehindWindowBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

// MARK: Janela

/// Recebe os arquivos soltos em qualquer ponto do painel.
private final class DropTargetView: NSView {
    var accepts: () -> Bool = { true }
    var onTargeted: (Bool) -> Void = { _ in }
    var onDrop: ([URL]) -> Void = { _ in }

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) { nil }

    static func urls(_ info: NSDraggingInfo) -> [URL] {
        info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard accepts(), !Self.urls(sender).isEmpty else { return [] }
        onTargeted(true)
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        onTargeted(false)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        onTargeted(false)
        let urls = Self.urls(sender)
        guard !urls.isEmpty else { return false }
        onDrop(urls)
        return true
    }
}

/// Janela sem borda que nunca rouba o foco do app em que o usuário está.
private final class DropPanelWindow: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class DropPanelController {
    let model = DropModel()
    /// Chamado ao soltar arquivos no painel ou no ícone.
    var onDrop: ([URL]) -> Void = { _ in }
    /// O ícone fica aceso (como quando a Central de Controle está aberta) enquanto o painel aparece.
    var onVisibleChange: (Bool) -> Void = { _ in }

    private let window: DropPanelWindow
    private let hosting: NSHostingView<DropPanelView>
    private var hideWork: DispatchWorkItem?
    private var buttonWatch: Timer?
    #if DEBUG
    /// Modo de demonstração: não fecha sozinho.
    var keepOpen = false
    #endif

    init() {
        window = DropPanelWindow(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false // a sombra é desenhada junto com o vidro, para crescer com ele
        window.level = .popUpMenu
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.animationBehavior = .none

        hosting = NSHostingView(rootView: DropPanelView(model: model))
        let target = DropTargetView()
        target.addSubview(hosting)
        hosting.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: target.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: target.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: target.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: target.bottomAnchor),
        ])
        window.contentView = target

        target.accepts = { [weak self] in self?.model.paired == true && self?.model.isTransferring == false }
        target.onTargeted = { [weak self] on in self?.setTargeted(on) }
        target.onDrop = { [weak self] urls in self?.accept(urls) }
    }

    var isVisible: Bool { model.visible }

    /// Painel aberto e ainda esperando um arquivo: some quando o arrasto acaba ou se afasta.
    private var isWaitingForDrop: Bool { model.visible && model.batch.isEmpty }

    /// Mostra o painel crescendo de dentro do ícone (iconFrame em coordenadas da tela).
    func show(below iconFrame: NSRect) {
        hideWork?.cancel()
        hideWork = nil
        if model.visible { return }
        if model.outcome != nil { model.reset() }

        let size = hosting.fittingSize
        let screen = NSScreen.screens.first { $0.frame.contains(NSPoint(x: iconFrame.midX, y: iconFrame.midY)) } ?? NSScreen.main
        let bounds = screen?.frame ?? iconFrame
        let glassX = min(max(iconFrame.midX - DropPanelView.width / 2, bounds.minX + 8), bounds.maxX - 8 - DropPanelView.width)
        let origin = NSPoint(x: glassX - DropPanelView.margin, y: iconFrame.minY - 6 - size.height)
        window.setFrame(NSRect(origin: origin, size: size), display: false)
        model.anchorX = min(max((iconFrame.midX - glassX) / DropPanelView.width, 0), 1)

        window.orderFrontRegardless()
        onVisibleChange(true)
        withAnimation(.spring(response: 0.38, dampingFraction: 0.8)) { model.visible = true }
        watchMouseButton()
    }

    func hide(after delay: TimeInterval = 0) {
        guard model.visible, hideWork == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            hideWork = nil
            buttonWatch?.invalidate()
            buttonWatch = nil
            withAnimation(.easeIn(duration: 0.18)) { self.model.visible = false }
            onVisibleChange(false)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { [weak self] in
                guard let self, !model.visible else { return }
                window.orderOut(nil)
                if model.outcome != nil || model.batch.isEmpty { model.reset() }
            }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// O arrasto passou por aqui: abre perto do ícone, fecha ao se afastar.
    func dragMoved(to point: NSPoint, iconFrame: NSRect) {
        guard !model.isTransferring else { return }
        let near = abs(point.x - iconFrame.midX) < 150 && point.y > iconFrame.minY - 120
        if near {
            show(below: iconFrame)
        } else if isWaitingForDrop, !window.frame.insetBy(dx: -40, dy: -40).contains(point) {
            hide()
        }
    }

    func setTargeted(_ on: Bool) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { model.targeted = on }
    }

    func accept(_ urls: [URL]) {
        hideWork?.cancel()
        hideWork = nil
        withAnimation(.smooth(duration: 0.3)) {
            model.targeted = false
            model.begin(urls)
        }
        onDrop(urls)
    }

    func handle(_ event: TabletServer.FileEvent) {
        guard model.visible, !model.batch.isEmpty else { return }
        model.handle(event)
        switch model.outcome {
        case .sent: hide(after: 1.4)
        case .queued: hide(after: 2.4)
        case .failed: hide(after: 3.5)
        case nil: break
        }
    }

    /// Soltou o botão do mouse sem soltar o arquivo aqui: fecha. (Mais confiável que esperar o
    /// evento de soltar, que às vezes não chega quando o arrasto termina em outro app.)
    private func watchMouseButton() {
        buttonWatch?.invalidate()
        #if DEBUG
        if keepOpen { return }
        #endif
        buttonWatch = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isWaitingForDrop, NSEvent.pressedMouseButtons & 1 == 0 else { return }
                self.hide(after: 0.15)
            }
        }
    }
}

// MARK: Arrasto chegando perto

/// Percebe, em qualquer app, um arrasto de arquivo em andamento e conta onde o ponteiro está.
/// Só observa eventos de arrastar com o botão esquerdo; não lê teclado nem precisa de permissão.
@MainActor
final class FileDragWatcher {
    var onMove: (NSPoint) -> Void = { _ in }
    var onEnd: () -> Void = {}

    private var monitors: [Any] = []
    /// Contador da área de arrasto no fim do último gesto: se mudou, começou um arrasto novo.
    /// (Não dá para usar o do clique: o Finder às vezes já preparou o arrasto antes de o aviso chegar aqui.)
    private var baseline = 0
    /// nil enquanto não deu para saber se o arrasto é de arquivo.
    private var isFileDrag: Bool?

    func start() {
        let drag = NSPasteboard(name: .drag)
        baseline = drag.changeCount
        monitors = [
            NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if self.isFileDrag == nil, drag.changeCount != self.baseline {
                        self.isFileDrag = drag.types?.contains(.fileURL) == true
                    }
                    if self.isFileDrag == true { self.onMove(NSEvent.mouseLocation) }
                }
            },
            NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if self.isFileDrag == true { self.onEnd() }
                    self.isFileDrag = nil
                    self.baseline = drag.changeCount
                }
            },
        ].compactMap { $0 }
    }
}
