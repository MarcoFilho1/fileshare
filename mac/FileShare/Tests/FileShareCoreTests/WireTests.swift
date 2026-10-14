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

    @Test(arguments: [
        WireMessage.hello(name: "Galaxy Tab S9 FE"),
        .clip(id: 1, payload: ClipPayload(mime: "image/png", data: Data([0x89, 0x50, 0x0A, 0x00]))),
        .ack(id: 42),
        .ping,
        .pong,
    ])
    func roundTrips(_ message: WireMessage) throws {
        var decoder = WireDecoder()
        #expect(try decoder.append(Wire.encode(message)) == [message])
    }

    @Test func splitsAndJoinsMessagesAcrossChunks() throws {
        let messages: [WireMessage] = [.ping, .clip(id: 3, payload: ClipPayload(mime: "text/plain", data: Data("olá\nmundo".utf8))), .ack(id: 3)]
        let wire = messages.reduce(Data()) { $0 + Wire.encode($1) }
        var decoder = WireDecoder()
        var out: [WireMessage] = []
        for start in stride(from: 0, to: wire.count, by: 5) {
            out += try decoder.append(wire.subdata(in: start..<min(start + 5, wire.count)))
        }
        #expect(out == messages)
    }

    @Test func rejectsOversizedFrame() {
        var decoder = WireDecoder()
        #expect(throws: Wire.DecodeError.frameTooLarge(0x7fff_ffff)) { try decoder.append(Data([0x7f, 0xff, 0xff, 0xff])) }
    }

    @Test func rejectsUnknownMessage() {
        var decoder = WireDecoder()
        #expect(throws: Wire.DecodeError.badMessage("HACK")) { try decoder.append(Data([0, 0, 0, 5]) + Data("HACK\n".utf8)) }
    }
}
