import Foundation
import Testing
@testable import FileShareCore

struct PairingLinkTests {
    @Test func buildsLinkTheTabletParses() throws {
        let key = Data([0xfb, 0xff, 0x3e] + Array(repeating: 0, count: 29))
        let url = PairingLink.url(macId: "abc-123", name: "Marco MacBook Air", key: key)
        let c = try #require(URLComponents(string: url))
        #expect(c.scheme == "fileshare")
        #expect(c.host == "pair")
        let items = Dictionary(uniqueKeysWithValues: (c.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        #expect(items["v"] == "1")
        #expect(items["id"] == "abc-123")
        #expect(items["name"] == "Marco MacBook Air")
        #expect(items["k"] == "-_8-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA") // base64url, sem "="
    }
}
