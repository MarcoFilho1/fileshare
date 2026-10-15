import Foundation
import Testing
@testable import FileShareCore

struct IncomingFileTests {
    private func tempDir() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("fileshare-tests-\(UUID().uuidString)")
    }

    private func visibleFiles(_ dir: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []).sorted()
    }

    @Test func writesPiecesAndKeepsExistingFiles() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("antigo".utf8).write(to: dir.appendingPathComponent("Nota.pdf"))

        let file = try IncomingFile(name: "Nota.pdf", mime: "application/pdf", size: 7, directory: dir)
        try file.append(Data("%PDF".utf8))
        #expect(!file.isComplete)
        try file.append(Data("-1\n".utf8))
        #expect(file.isComplete)
        let url = try file.finish()

        #expect(url.lastPathComponent == "Nota (2).pdf")
        #expect(try Data(contentsOf: url) == Data("%PDF-1\n".utf8))
        #expect(try Data(contentsOf: dir.appendingPathComponent("Nota.pdf")) == Data("antigo".utf8))
        #expect(visibleFiles(dir) == ["Nota (2).pdf", "Nota.pdf"])
    }

    @Test func refusesMoreThanAnnouncedAndCleansUp() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = try IncomingFile(name: "a.txt", mime: "text/plain", size: 2, directory: dir)
        #expect(throws: IncomingFile.Failure.moreThanAnnounced) { try file.append(Data("abc".utf8)) }
        #expect(visibleFiles(dir).isEmpty)
    }

    @Test func discardRemovesPartialFile() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = try IncomingFile(name: "a.txt", mime: "text/plain", size: 10, directory: dir)
        try file.append(Data("abc".utf8))
        file.discard()
        #expect(visibleFiles(dir).isEmpty)
    }

    @Test func refusesFilesOverTheLimit() {
        #expect(throws: IncomingFile.Failure.tooLarge(Wire.maxFileSize + 1)) {
            try IncomingFile(name: "grande.pdf", mime: "application/pdf", size: Wire.maxFileSize + 1, directory: tempDir())
        }
    }

    @Test(arguments: [
        ("../../.ssh/authorized_keys", "text/plain", "-..-.ssh-authorized_keys"),
        (".zshrc", "text/plain", "zshrc.txt"),
        ("Aula\n3.pdf", "application/pdf", "Aula3.pdf"),
        ("Nota de aula", "application/pdf", "Nota de aula.pdf"),
        ("", "image/png", "arquivo.png"),
        ("a:b.txt", "text/plain", "a-b.txt"),
    ])
    func sanitizesNames(_ raw: String, _ mime: String, _ expected: String) {
        #expect(IncomingFile.safeName(raw, mime: mime) == expected)
    }
}
