import Foundation
import Testing
@testable import FileShareCore

struct ClipHistoryTests {
    static func text(_ s: String) -> ClipPayload { ClipPayload(mime: "text/plain", data: Data(s.utf8)) }
    static func image(_ megabytes: Int, _ tag: UInt8) -> ClipPayload {
        ClipPayload(mime: "image/png", data: Data(repeating: tag, count: megabytes * 1024 * 1024))
    }

    @Test func newestFirstAndCappedAtTen() {
        var h = ClipHistory()
        for i in 1...12 { h.add(Self.text("cópia \(i)"), fromTablet: i.isMultiple(of: 2)) }
        #expect(h.entries.count == 10)
        #expect(h.entries.first?.payload == Self.text("cópia 12"))
        #expect(h.entries.last?.payload == Self.text("cópia 3"))
        #expect(h.entries.first?.fromTablet == true)
    }

    @Test func copyingAgainMovesToTopWithoutDuplicate() {
        var h = ClipHistory()
        h.add(Self.text("a"), fromTablet: false)
        h.add(Self.text("b"), fromTablet: false)
        h.add(Self.text("a"), fromTablet: true)
        #expect(h.entries.map(\.payload) == [Self.text("a"), Self.text("b")])
        #expect(h.entries.first?.fromTablet == true)
    }

    /// Passando do limite de memória, saem as imagens mais antigas; texto e a mais nova ficam.
    @Test func dropsOldestImagesOverMemoryBudget() {
        var h = ClipHistory()
        h.add(Self.image(25, 1), fromTablet: false)
        h.add(Self.text("texto"), fromTablet: false)
        h.add(Self.image(25, 2), fromTablet: true)
        h.add(Self.image(25, 3), fromTablet: false)
        #expect(h.totalBytes <= ClipHistory.maxBytes)
        #expect(h.entries.map(\.payload) == [Self.image(25, 3), Self.image(25, 2), Self.text("texto")])
    }

    @Test func titleIsFirstLineTidied() {
        #expect(ClipHistory.title(of: Self.text("  Reunião   às 15h\nsala 2")) == "Reunião às 15h")
        #expect(ClipHistory.title(of: Self.text("\n\nsegunda linha")) == "segunda linha")
    }

    @Test func clearEmpties() {
        var h = ClipHistory()
        h.add(Self.text("x"), fromTablet: false)
        h.removeAll()
        #expect(h.entries.isEmpty)
    }
}
