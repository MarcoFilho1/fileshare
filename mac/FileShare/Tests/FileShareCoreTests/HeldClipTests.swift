import Foundation
import Testing
@testable import FileShareCore

struct HeldClipTests {
    let t0 = Date(timeIntervalSince1970: 1_792_000_000)
    func text(_ s: String) -> ClipPayload { ClipPayload(mime: "text/plain", data: Data(s.utf8)) }

    @Test func keepsOnlyTheLatestCopy() throws {
        var held = HeldClip()
        held.hold(text("primeira"), copiedAt: t0)
        held.hold(text("segunda"), copiedAt: t0 + 5)
        let result = held.take(now: t0 + 60)
        let taken = try #require(result)
        #expect(taken.payload == text("segunda"))
        #expect(taken.copiedAt == t0 + 5)
        let again = held.take(now: t0 + 61)
        #expect(again == nil) // entregue uma vez só
    }

    @Test func expiresAfterTenMinutes() {
        var held = HeldClip()
        held.hold(text("velha"), copiedAt: t0)
        let taken = held.take(now: t0 + HeldClip.lifetime + 1)
        #expect(taken == nil)
    }

    @Test func discardDropsIt() {
        var held = HeldClip()
        held.hold(text("x"), copiedAt: t0)
        held.discard()
        let taken = held.take(now: t0)
        #expect(taken == nil)
    }
}
