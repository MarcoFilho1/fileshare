import AppKit

/// O macOS não avisa quando algo é copiado: verifica o changeCount a cada meio segundo.
@MainActor
public final class PasteboardWatcher {
    private let pasteboard: NSPasteboard
    private let onCopy: (ClipPayload) -> Void
    private var lastChange: Int
    private var timer: Timer?

    public init(pasteboard: NSPasteboard = .general, onCopy: @escaping (ClipPayload) -> Void) {
        self.pasteboard = pasteboard
        self.onCopy = onCopy
        self.lastChange = pasteboard.changeCount
    }

    public func start(interval: TimeInterval = 0.5) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    public func poll() {
        let change = pasteboard.changeCount
        guard change != lastChange else { return }
        lastChange = change
        if let payload = PasteboardReader.read(pasteboard) { onCopy(payload) }
    }
}
