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
        .clip(id: 1, payload: ClipPayload(mime: "image/png", data: Data([0x89, 0x50, 0x0A, 0x00]))),
        .held(id: 2, copiedAt: 1_792_000_000_123, payload: ClipPayload(mime: "text/plain", data: Data("guardado".utf8))),
        .file(id: 3, size: 1_048_576, mime: "application/pdf", name: "Aula 3 - resumo.pdf"),
        .part(id: 3, data: Data([0x25, 0x50, 0x44, 0x46, 0x0A])),
        .ack(id: 42),
        .fail(id: 3, reason: "arquivo maior que 100 MB"),
        .ping,
        .pong,
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

    @Test func rejectsUnknownMessage() {
        #expect(throws: Wire.DecodeError.badMessage("HACK")) { try Wire.decodeMessage(Data("HACK\n".utf8)) }
    }
}
