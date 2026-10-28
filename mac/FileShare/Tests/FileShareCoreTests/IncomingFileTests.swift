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

    /// Sem espaço (deixando a folga), recusa antes de criar qualquer arquivo.
    @Test func refusesWhenDiskIsFull() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let gb: Int64 = 1024 * 1024 * 1024
        #expect(throws: IncomingFile.Failure.noSpace(gb)) {
            try IncomingFile(name: "video.mp4", mime: "video/mp4", size: gb, directory: dir, freeSpace: gb + 50 * 1024 * 1024)
        }
        #expect(visibleFiles(dir).isEmpty)
        _ = try IncomingFile(name: "video.mp4", mime: "video/mp4", size: gb, directory: dir, freeSpace: 3 * gb)
    }

    /// Uma pasta compactada pelo Mac: o zip tem o conteúdo da pasta, sem a pasta __MACOSX.
    @Test func zipsFolderContents() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let folder = dir.appendingPathComponent("Aulas de Física")
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("Capítulo 1"), withIntermediateDirectories: true)
        try Data("a".utf8).write(to: folder.appendingPathComponent("Capítulo 1/exercício.txt"))
        try Data("b".utf8).write(to: folder.appendingPathComponent("índice.md"))
        let zip = dir.appendingPathComponent("out/Aulas.zip")
        #expect(FolderZip.zip(folder, to: zip))
        let back = dir.appendingPathComponent("back")
        let unzip = Process()
        unzip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        unzip.arguments = ["-x", "-k", zip.path, back.path]
        try unzip.run()
        unzip.waitUntilExit()
        let names = (FileManager.default.subpaths(atPath: back.path) ?? [])
            .filter { !$0.hasSuffix("Capítulo 1".decomposedStringWithCanonicalMapping) && $0.precomposedStringWithCanonicalMapping != "Capítulo 1" }
            .map(\.precomposedStringWithCanonicalMapping).sorted()
        #expect(names == ["Capítulo 1/exercício.txt", "índice.md"])
    }

    /// A conexão caiu no meio: o mesmo IncomingFile segue recebendo de onde parou e termina inteiro.
    @Test func continuesWhereItStopped() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = try IncomingFile(name: "video.mp4", mime: "video/mp4", size: 6, directory: dir, transferId: "abcdef0123456789", freeSpace: 1 << 40)
        try file.append(Data("abc".utf8))
        // ... a conexão cai; o tablet volta e manda SEND com o mesmo transferId; o Mac responde FROM 3
        #expect(file.received == 3)
        try file.append(Data("def".utf8))
        #expect(try Data(contentsOf: file.finish()) == Data("abcdef".utf8))
    }

    @Test func removesLeftoverPieces() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: dir.appendingPathComponent(".fileshare-ABC.part"))
        try Data("y".utf8).write(to: dir.appendingPathComponent("Nota.pdf"))
        IncomingFile.removeLeftovers(in: dir)
        #expect(visibleFiles(dir) == ["Nota.pdf"])
    }
}
