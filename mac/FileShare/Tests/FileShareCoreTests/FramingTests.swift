import Foundation
import Testing
@testable import FileShareCore

struct FramingTests {
    @Test func encodeThenParseHeaderRoundTrips() throws {
        let payload = ClipPayload(mime: "text/plain", data: Data("olá".utf8))
        let wire = Framing.encode(payload)
        let header = try #require(try Framing.parseHeader(wire))
        #expect(header.mime == "text/plain")
        #expect(header.size == payload.data.count)
        #expect(wire.dropFirst(header.headerLength) == payload.data)
    }

    @Test func incompleteHeaderWaitsForMoreBytes() throws {
        #expect(try Framing.parseHeader(Data("image/png\n12".utf8)) == nil)
        #expect(try Framing.parseHeader(Data()) == nil)
    }

    @Test func rejectsInvalidSizes() {
        #expect(throws: Framing.DecodeError.badSize("0")) { try Framing.parseHeader(Data("text/plain\n0\n".utf8)) }
        #expect(throws: Framing.DecodeError.badSize("abc")) { try Framing.parseHeader(Data("text/plain\nabc\n".utf8)) }
        let tooBig = String(Framing.maxPayload + 1)
        #expect(throws: Framing.DecodeError.badSize(tooBig)) { try Framing.parseHeader(Data("image/png\n\(tooBig)\n".utf8)) }
    }

    @Test func rejectsHeaderWithoutNewlineAfterLimit() {
        #expect(throws: Framing.DecodeError.badHeader) { try Framing.parseHeader(Data(repeating: 0x61, count: 300)) }
    }
}

struct FrameAccumulatorTests {
    @Test func assemblesMessageArrivingInPieces() throws {
        let payload = ClipPayload(mime: "image/png", data: Data((0..<1000).map { UInt8($0 % 256) }))
        let wire = Framing.encode(payload)
        var acc = FrameAccumulator()
        var result: ClipPayload?
        for start in stride(from: 0, to: wire.count, by: 7) {
            #expect(result == nil)
            result = try acc.append(wire.subdata(in: start..<min(start + 7, wire.count)))
        }
        #expect(result == payload)
    }
}
