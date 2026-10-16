import AppKit
import Observation
import SwiftUI

// Painel do ícone ⇄: no lugar de um menu simples, um painel de vidro no estilo da Central de
// Controle, com o tablet, os botões redondos de ligar e desligar e a atividade recente.

@MainActor @Observable
final class StatusModel {
    enum Link: Equatable {
        case unpaired, searching, connected, rejected
        case failed(String)
    }

    struct Activity: Identifiable, Equatable {
        enum Kind { case toTablet, fromTablet, waiting, failed }
        let id = UUID()
        let kind: Kind
        let text: String
        let date: Date
    }

    struct Actions {
        var togglePause: () -> Void = {}
        var toggleLogin: () -> Void = {}
        var sendFile: () -> Void = {}
        var openFolder: () -> Void = {}
        var pair: () -> Void = {}
        var forget: () -> Void = {}
        var enableNotifications: () -> Void = {}
        var quit: () -> Void = {}
    }

    var visible = false
    var anchorX = 0.5
    var link: Link = .searching
    var tabletName = "Tablet"
    var paused = false
    var openAtLogin = false
    var notificationsAllowed = true
    private(set) var activity: [Activity] = []
    /// Arquivo indo para o tablet agora.
    var sending: (name: String, fraction: Double)?
    var actions = Actions()

    var paired: Bool { link != .unpaired }

    func log(_ kind: Activity.Kind, _ text: String) {
        activity.insert(Activity(kind: kind, text: text, date: Date()), at: 0)
        if activity.count > 4 { activity.removeLast(activity.count - 4) }
    }

    /// O que muda a altura do painel (para a janela acompanhar).
    var layoutKey: [Int] {
        [notificationsAllowed ? 1 : 0]
    }
}

struct StatusPanelView: View {
    static let width: CGFloat = 340
    static let margin: CGFloat = 26
    static let activityHeight: CGFloat = 4 * 22 + 3 * 8

    let model: StatusModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 10) {
            header
            tabletTile
            HStack(spacing: 10) {
                ToggleTile(symbol: model.paused ? "pause.fill" : "arrow.left.arrow.right", on: !model.paused,
                           title: L10n.t("Sync", "Sincronizar"),
                           subtitle: model.paused ? L10n.t("Paused", "Pausado") : L10n.t("On", "Ligado"),
                           hint: L10n.t("Pauses or resumes sending and receiving copies between the Mac and the tablet.",
                                        "Pausa ou retoma o envio e o recebimento de cópias entre o Mac e o tablet."),
                           hintAlignment: .topLeading,
                           action: model.actions.togglePause)
                ToggleTile(symbol: "power", on: model.openAtLogin,
                           title: L10n.t("Open at Login", "Abrir ao iniciar"),
                           subtitle: model.openAtLogin ? L10n.t("On", "Ligado") : L10n.t("Off", "Desligado"),
                           hint: L10n.t("Opens FileShare automatically when you log in to the Mac.",
                                        "Abre o FileShare sozinho quando você entra no Mac."),
                           hintAlignment: .topTrailing,
                           action: model.actions.toggleLogin)
            }
            .zIndex(1) // a dica passa por cima do cartão de atividade
            activityTile
            HStack(spacing: 10) {
                ActionTile(symbol: "square.and.arrow.up", title: L10n.t("Send File…", "Enviar arquivo…"), action: model.actions.sendFile)
                    .disabled(!model.paired)
                ActionTile(symbol: "folder", title: L10n.t("Received", "Recebidos"), action: model.actions.openFolder)
            }
            Divider().padding(.horizontal, 6).padding(.top, 2)
            VStack(spacing: 0) {
                if !model.notificationsAllowed {
                    TextRow(title: L10n.t("Turn On Notifications…", "Ativar notificações…"), symbol: "bell.badge",
                            action: model.actions.enableNotifications)
                }
                // sempre as mesmas linhas, para nada mudar de lugar debaixo do ponteiro
                TextRow(title: model.paired ? L10n.t("Pair Another Tablet…", "Parear outro tablet…") : L10n.t("Pair Tablet…", "Parear tablet…"),
                        action: model.actions.pair)
                TextRow(title: L10n.t("Forget Tablet…", "Esquecer tablet…"), action: model.actions.forget)
                    .disabled(!model.paired)
                TextRow(title: L10n.t("Quit FileShare", "Sair do FileShare"), action: model.actions.quit)
            }
        }
        .padding(12)
        .frame(width: Self.width)
        .modifier(GlassBackground(cornerRadius: 24))
        .shadow(color: .black.opacity(0.22), radius: 18, y: 8)
        .scaleEffect(model.visible ? 1 : (reduceMotion ? 0.98 : 0.5), anchor: UnitPoint(x: model.anchorX, y: 0))
        .opacity(model.visible ? 1 : 0)
        .padding(.horizontal, Self.margin)
        .padding(.top, 2)
        .padding(.bottom, Self.margin)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 22, height: 22)
            Text("FileShare")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
        }
        .padding(.horizontal, 6)
        .padding(.top, 2)
    }

    private var tabletTile: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(model.link == .connected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color.primary.opacity(0.1)))
                    Image(systemName: "ipad.landscape")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(model.link == .connected ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
                }
                .frame(width: 38, height: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.paired ? model.tabletName : L10n.t("No Tablet Paired", "Nenhum tablet pareado"))
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    HStack(spacing: 5) {
                        Circle().fill(dotColor).frame(width: 6, height: 6)
                        Text(linkText)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                if !model.paired {
                    Button(action: model.actions.pair) {
                        Text(L10n.t("Pair…", "Parear…"))
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .foregroundStyle(.white)
                            .background(Color.accentColor, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(12)
        .background(Tile())
    }

    private var dotColor: Color {
        switch model.link {
        case .connected: .green
        case .unpaired: .secondary
        case .searching: .orange
        case .rejected, .failed: .red
        }
    }

    private var linkText: String {
        switch model.link {
        case .unpaired: L10n.t("Pair once with a QR code", "Pareie uma vez com um QR code")
        case .searching: L10n.t("Asleep or away · copies wait", "Dormindo ou longe · as cópias esperam")
        case .connected: L10n.t("Connected · encrypted", "Conectado · criptografado")
        case .rejected: L10n.t("Refused a device without the key", "Recusei um aparelho sem a chave")
        case .failed(let reason): reason
        }
    }

    private var activityTile: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.t("Recent", "Recentes"))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 8) {
            if let sending = model.sending {
                HStack(spacing: 10) {
                    ActivityIcon(kind: .toTablet)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(sending.name).font(.system(size: 12)).lineLimit(1).truncationMode(.middle)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.primary.opacity(0.1))
                                Capsule().fill(Color.accentColor).frame(width: max(5, geo.size.width * sending.fraction))
                            }
                        }
                        .frame(height: 5)
                    }
                }
            }
            ForEach(model.activity.prefix(model.sending == nil ? 4 : 3)) { item in
                HStack(spacing: 10) {
                    ActivityIcon(kind: item.kind)
                    Text(item.text)
                        .font(.system(size: 12))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 4)
                    Text(item.date, style: .time)
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
            }
            // altura fixa de 4 linhas: atividade nova não empurra os botões de baixo
            .frame(maxWidth: .infinity, minHeight: Self.activityHeight, maxHeight: Self.activityHeight, alignment: .top)
            .overlay {
                if model.activity.isEmpty && model.sending == nil {
                    VStack(spacing: 6) {
                        Image(systemName: "doc.on.clipboard")
                            .font(.system(size: 20))
                            .foregroundStyle(.tertiary)
                        Text(L10n.t("Copy something on the Mac or the tablet.", "Copie algo no Mac ou no tablet."))
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .clipped()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Tile())
        .animation(.smooth(duration: 0.25), value: model.activity)
    }
}

/// Fundo dos módulos, como os da Central de Controle.
private struct Tile: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.primary.opacity(0.06))
    }
}

private struct ActivityIcon: View {
    let kind: StatusModel.Activity.Kind

    var body: some View {
        let (symbol, color): (String, Color) = switch kind {
        case .toTablet: ("arrow.up.right", .accentColor)
        case .fromTablet: ("arrow.down.left", .green)
        case .waiting: ("clock", .orange)
        case .failed: ("exclamationmark", .red)
        }
        Image(systemName: symbol)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(color)
            .frame(width: 22, height: 22)
            .background(color.opacity(0.15), in: Circle())
    }
}

/// Botão redondo que fica azul quando ligado, como os da Central de Controle.
private struct ToggleTile: View {
    let symbol: String
    let on: Bool
    let title: String
    let subtitle: String
    let hint: String
    let hintAlignment: Alignment
    let action: () -> Void
    @State private var hover = false
    @State private var showHint = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                ZStack {
                    Circle().fill(on ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color.primary.opacity(0.1)))
                    Image(systemName: symbol)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(on ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                        .contentTransition(.symbolEffect(.replace))
                }
                .frame(width: 30, height: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 12, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
                    Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.primary.opacity(hover ? 0.1 : 0.06)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { inside in
            hover = inside
            if inside {
                // como as dicas do sistema: aparece depois de um instante parado em cima
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { if hover { withAnimation(.easeOut(duration: 0.15)) { showHint = true } } }
            } else {
                withAnimation(.easeIn(duration: 0.1)) { showHint = false }
            }
        }
        .overlay(alignment: hintAlignment) {
            if showHint {
                // logo abaixo do botão (50 pt de altura + 6 de folga)
                HintBubble(text: hint)
                    .offset(y: 56)
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }
        }
        .zIndex(showHint ? 1 : 0) // por cima do botão vizinho
        .animation(.smooth(duration: 0.2), value: on)
    }
}

/// Dica ao parar o ponteiro num botão. O .help do sistema não aparece porque o FileShare nunca
/// fica em primeiro plano (o painel não rouba o foco do app em uso).
private struct HintBubble: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11))
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(width: 210, alignment: .leading)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(nsColor: .windowBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.primary.opacity(0.1)))
            .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
    }
}

private struct ActionTile: View {
    let symbol: String
    let title: String
    let action: () -> Void
    @State private var hover = false
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol).font(.system(size: 13, weight: .medium))
                Text(title).font(.system(size: 12, weight: .medium)).lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.primary.opacity(hover && enabled ? 0.1 : 0.06)))
            .opacity(enabled ? 1 : 0.45)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

/// Linha de texto no fim do painel, como "Ajustes da Central de Controle…".
private struct TextRow: View {
    let title: String
    var symbol: String?
    let action: () -> Void
    @State private var hover = false
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title).font(.system(size: 13)).foregroundStyle(enabled ? .primary : .tertiary)
                Spacer()
                if let symbol { Image(systemName: symbol).foregroundStyle(.orange) }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(hover && enabled ? 0.08 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

// MARK: Janela

/// Painel que pode receber teclado (Esc fecha) sem ativar o app nem tirar o foco de onde o usuário está.
private final class StatusPanelWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class StatusPanelController {
    let model = StatusModel()
    var onVisibleChange: (Bool) -> Void = { _ in }

    private let window: StatusPanelWindow
    private let hosting: NSHostingView<StatusPanelView>
    private var monitors: [Any] = []
    private var iconFrame: NSRect = .zero
    #if DEBUG
    /// Modo de demonstração: cliques fora não fecham.
    var keepOpen = false
    #endif

    init() {
        window = StatusPanelWindow(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .popUpMenu
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.animationBehavior = .none
        hosting = NSHostingView(rootView: StatusPanelView(model: model))
        window.contentView = hosting
        followLayout()
    }

    var isVisible: Bool { model.visible }

    func toggle(below icon: NSRect) {
        model.visible ? hide() : show(below: icon)
    }

    func show(below icon: NSRect) {
        iconFrame = icon
        place()
        window.makeKeyAndOrderFront(nil)
        onVisibleChange(true)
        withAnimation(.spring(response: 0.36, dampingFraction: 0.82)) { model.visible = true }
        #if DEBUG
        if keepOpen { return }
        #endif
        // clique fora (em qualquer app) ou Esc fecham, como um menu
        monitors = [
            NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                MainActor.assumeIsolated { self?.hide() }
            },
            NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard event.keyCode == 53 else { return event }
                MainActor.assumeIsolated { self?.hide() }
                return nil
            },
        ].compactMap { $0 }
    }

    func hide() {
        guard model.visible else { return }
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        withAnimation(.easeIn(duration: 0.16)) { model.visible = false }
        onVisibleChange(false)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self, !model.visible else { return }
            window.orderOut(nil)
        }
    }

    /// Debaixo do ícone, preso pelo topo, centrado nele sem sair da tela.
    private func place() {
        let size = hosting.fittingSize
        let screen = NSScreen.screens.first { NSMouseInRect(NSPoint(x: iconFrame.midX, y: iconFrame.midY), $0.frame, false) } ?? NSScreen.main
        let bounds = screen?.frame ?? iconFrame
        let glassX = min(max(iconFrame.midX - StatusPanelView.width / 2, bounds.minX + 8), bounds.maxX - 8 - StatusPanelView.width)
        window.setFrame(NSRect(x: glassX - StatusPanelView.margin, y: iconFrame.minY - 6 - size.height, width: size.width, height: size.height), display: true)
        model.anchorX = min(max((iconFrame.midX - glassX) / StatusPanelView.width, 0), 1)
    }

    /// A altura muda (atividade nova, pareou…): a janela acompanha, sem sair do lugar no topo.
    private func followLayout() {
        withObservationTracking { _ = model.layoutKey } onChange: { [weak self] in
            DispatchQueue.main.async {
                guard let self else { return }
                if self.model.visible { self.place() }
                self.followLayout()
            }
        }
    }
}
