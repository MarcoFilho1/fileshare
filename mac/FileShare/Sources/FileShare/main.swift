import AppKit

MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory) // só na barra de menu, sem ícone no Dock
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
