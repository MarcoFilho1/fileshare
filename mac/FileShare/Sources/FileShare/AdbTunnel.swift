import Foundation

/// Mantém o túnel USB com o tablet: `adb forward` (Mac → tablet) e `adb reverse` (tablet → Mac).
/// Refaz a cada poucos segundos, então reconectar o cabo basta. Provisório até o Wi-Fi.
final class AdbTunnel {
    static let tabletPort = 47800
    static let macPort = 47801

    private let queue = DispatchQueue(label: "fileshare.adb")
    private var timer: DispatchSourceTimer?
    private let onChange: (Bool) -> Void
    private var connected: Bool?

    init(onChange: @escaping (Bool) -> Void) {
        self.onChange = onChange
    }

    static var adbPath: String? {
        ["/opt/homebrew/bin/adb", "/usr/local/bin/adb"].first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    func start() {
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now(), repeating: 5)
        t.setEventHandler { [weak self] in self?.refresh() }
        t.resume()
        timer = t
    }

    private func refresh() {
        let ok = Self.run(["get-state"]) == "device"
            && Self.run(["forward", "tcp:\(Self.tabletPort)", "tcp:\(Self.tabletPort)"]) != nil
            && Self.run(["reverse", "tcp:\(Self.macPort)", "tcp:\(Self.macPort)"]) != nil
        guard ok != connected else { return }
        connected = ok
        DispatchQueue.main.async { self.onChange(ok) }
    }

    /// Saída do comando, ou nil se falhou.
    private static func run(_ args: [String]) -> String? {
        guard let adb = adbPath else { return nil }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: adb)
        p.arguments = args
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        do { try p.run() } catch { return nil }
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { return nil }
        return String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
