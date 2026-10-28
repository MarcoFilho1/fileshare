import Foundation

/// Compacta uma pasta para mandar ao tablet como um arquivo só (o tablet 2.6+ a desfaz).
public enum FolderZip {
    /// O conteúdo da pasta (sem a pasta em si) num zip com nomes em UTF-8, sem a pasta __MACOSX nem
    /// atributos do macOS, que não servem no Android.
    public static func zip(_ folder: URL, to zip: URL) -> Bool {
        do {
            try FileManager.default.createDirectory(at: zip.deletingLastPathComponent(), withIntermediateDirectories: true)
            let ditto = Process()
            ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            ditto.arguments = ["-c", "-k", "--norsrc", "--noextattr", "--noqtn", folder.path, zip.path]
            try ditto.run()
            ditto.waitUntilExit()
            return ditto.terminationStatus == 0
        } catch {
            NSLog("FileShare: ditto falhou: \(error)")
            return false
        }
    }
}
