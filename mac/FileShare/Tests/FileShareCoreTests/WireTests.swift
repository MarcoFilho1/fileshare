import Foundation
import Testing
@testable import FileShareCore

struct WireTests {
    /// Mesmo vetor do teste Android (WireTest.java): os dois lados precisam gerar os mesmos bytes.
    @Test func matchesSharedVector() {
        let wire = Wire.encode(.clip(id: 7, payload: ClipPayload(mime: "text/plain", data: Data("oi".utf8))))
        #expect(wire.map { String(format: "%02x", $0) }.joined()
            == "00000014" + "CLIP 7 text/plain\noi".utf8.map { String(format: "%02x", $0) }.joined())
    }

    static func decodeAll(_ decoder: inout FrameDecoder, _ chunk: Data) throws -> [WireMessage] {
        try decoder.append(chunk).map(Wire.decodeMessage)
    }

    @Test(arguments: [
        WireMessage.auth(nonce: Data(repeating: 0xA0, count: 16)),
        .hello(name: "Galaxy Tab S9 FE"),
        .hello(name: "Marco MacBook Air", info: PeerInfo(version: "2.4.0", capabilities: ["batt", "held"])),
        .clip(id: 1, payload: ClipPayload(mime: "image/png", data: Data([0x89, 0x50, 0x0A, 0x00]))),
        .held(id: 2, copiedAt: 1_792_000_000_123, payload: ClipPayload(mime: "text/plain", data: Data("guardado".utf8))),
        .file(id: 3, size: 1_048_576, mime: "application/pdf", name: "Aula 3 - resumo.pdf"),
        .part(id: 3, data: Data([0x25, 0x50, 0x44, 0x46, 0x0A])),
        .ack(id: 42),
        .fail(id: 3, reason: "arquivo maior que 100 MB"),
        .ping,
        .pong,
        .battery(level: 72, charging: false),
        .open(id: 5, url: "https://www.youtube.com/watch?v=abc&t=10"),
        .battery(level: 100, charging: true),
    ])
    func roundTrips(_ message: WireMessage) throws {
        var decoder = FrameDecoder()
        #expect(try Self.decodeAll(&decoder, Wire.encode(message)) == [message])
    }

    /// Mesmo cabeçalho do WireTest.java: o nome do arquivo vai por último e pode ter espaços.
    @Test func fileHeaderMatchesAndroidFormat() {
        let bytes = Wire.messageBytes(.file(id: 4, size: 2048, mime: "application/pdf", name: "Nota de aula.pdf"))
        #expect(String(decoding: bytes, as: UTF8.self) == "FILE 4 2048 application/pdf Nota de aula.pdf\n")
    }

    @Test func splitsAndJoinsMessagesAcrossChunks() throws {
        let messages: [WireMessage] = [.ping, .clip(id: 3, payload: ClipPayload(mime: "text/plain", data: Data("olá\nmundo".utf8))), .ack(id: 3)]
        let wire = messages.reduce(Data()) { $0 + Wire.encode($1) }
        var decoder = FrameDecoder()
        var out: [WireMessage] = []
        for start in stride(from: 0, to: wire.count, by: 5) {
            out += try Self.decodeAll(&decoder, wire.subdata(in: start..<min(start + 5, wire.count)))
        }
        #expect(out == messages)
    }

    @Test func rejectsOversizedFrame() {
        var decoder = FrameDecoder()
        #expect(throws: Wire.DecodeError.frameTooLarge(0x7fff_ffff)) { try decoder.append(Data([0x7f, 0xff, 0xff, 0xff])) }
    }

    /// Um tipo de uma versão mais nova não derruba a conexão: vira .unknown e é ignorado.
    @Test func toleratesMessageFromNewerVersion() throws {
        #expect(try Wire.decodeMessage(Data("HIST 3 texto\n".utf8)) == .unknown(type: "HIST"))
        #expect(try Wire.decodeMessage(Data("NOTIF\ncorpo qualquer".utf8)) == .unknown(type: "NOTIF"))
    }

    /// Mesmo texto do WireTest.java.
    @Test func batteryMatchesAndroidFormat() throws {
        #expect(String(decoding: Wire.messageBytes(.battery(level: 7, charging: true)), as: UTF8.self) == "BATT 7 1\n")
        #expect(throws: Wire.DecodeError.self) { try Wire.decodeMessage(Data("BATT 101 0\n".utf8)) }
        #expect(throws: Wire.DecodeError.self) { try Wire.decodeMessage(Data("BATT 50 sim\n".utf8)) }
    }

    /// Mesmo texto do WireTest.java.
    @Test func openMatchesAndroidFormat() {
        #expect(String(decoding: Wire.messageBytes(.open(id: 3, url: "https://exemplo.com/a")), as: UTF8.self) == "OPEN 3 https://exemplo.com/a\n")
    }

    /// Só páginas da web: nada de file:, apps ou endereço vazio.
    @Test(arguments: [
        ("https://marcofilho1.github.io/fileshare/", true),
        ("HTTP://exemplo.com", true),
        ("file:///etc/passwd", false),
        ("javascript:alert(1)", false),
        ("x-apple.systempreferences:com.apple.preference.security", false),
        ("https://", false),
        ("não é link", false),
    ])
    func acceptsOnlyWebLinks(_ text: String, _ ok: Bool) {
        #expect((Wire.webURL(text) != nil) == ok)
    }

    /// Lixo continua sendo erro: só uma palavra curta em maiúsculas conta como tipo novo.
    @Test(arguments: ["hack 1\n", "\n", "HIST1 2\n", "ÇÃO\n", "UMTIPOMUITOCOMPRIDO\n"])
    func rejectsGarbage(_ text: String) {
        #expect(throws: Wire.DecodeError.self) { try Wire.decodeMessage(Data(text.utf8)) }
    }

    /// Mesmo texto do WireTest.java: versão e recursos vão no corpo do HELLO.
    @Test func helloInfoMatchesAndroidFormat() {
        let bytes = Wire.messageBytes(.hello(name: "Marco MacBook Air", info: PeerInfo(version: "2.4.0", capabilities: ["held", "batt"])))
        #expect(String(decoding: bytes, as: UTF8.self) == "HELLO Marco MacBook Air\nv=2.4.0\ncaps=batt,held\n")
    }

    /// Até a 2.3 o HELLO não tem corpo: o outro lado fica sem versão e sem recursos.
    @Test func helloFromOldVersionHasNoInfo() throws {
        let old = try Wire.decodeMessage(Data("HELLO Galaxy Tab S9 FE\n".utf8))
        #expect(old == .hello(name: "Galaxy Tab S9 FE", info: PeerInfo()))
        guard case .hello(_, let info) = old else { return }
        #expect(!info.supports("batt"))
    }

    /// Chaves desconhecidas no corpo do HELLO são ignoradas, para o formato poder crescer.
    @Test func helloIgnoresUnknownKeys() throws {
        let m = try Wire.decodeMessage(Data("HELLO Tab\nv=2.6.0\ntema=escuro\ncaps=batt,,hist\nlixo\n".utf8))
        #expect(m == .hello(name: "Tab", info: PeerInfo(version: "2.6.0", capabilities: ["batt", "hist"])))
    }
}
