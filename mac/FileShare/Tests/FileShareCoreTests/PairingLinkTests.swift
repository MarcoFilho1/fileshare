import Foundation
import Testing
@testable import FileShareCore

struct PairingLinkTests {
    private let key = Data([0xfb, 0xff, 0x3e] + Array(repeating: 0, count: 29))

    private func fields(_ query: String?) -> [String: String] {
        var c = URLComponents()
        c.percentEncodedQuery = query
        return Dictionary(uniqueKeysWithValues: (c.queryItems ?? []).map { ($0.name, $0.value ?? "") })
    }

    @Test func qrIsTheSitePageWithEverythingAfterTheHash() throws {
        let url = PairingLink.url(macId: "abc-123", name: "Marco MacBook Air", key: key)
        let c = try #require(URLComponents(string: url))
        #expect(c.scheme == "https")
        #expect(c.host == "marcofilho1.github.io")
        #expect(c.path == "/fileshare/pair/")
        #expect(c.query == nil) // nada da chave vai ao servidor
        let items = fields(c.percentEncodedFragment)
        #expect(items["v"] == "1")
        #expect(items["id"] == "abc-123")
        #expect(items["name"] == "Marco MacBook Air")
        #expect(items["k"] == "-_8-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA") // base64url, sem "="
    }

    @Test func appLinkHasTheSameFieldsTheTabletParses() throws {
        let url = PairingLink.appURL(macId: "abc-123", name: "Marco MacBook Air", key: key)
        let c = try #require(URLComponents(string: url))
        #expect(c.scheme == "fileshare")
        #expect(c.host == "pair")
        #expect(fields(c.percentEncodedQuery) == fields(URLComponents(string: PairingLink.url(macId: "abc-123", name: "Marco MacBook Air", key: key))!.percentEncodedFragment))
    }
}
