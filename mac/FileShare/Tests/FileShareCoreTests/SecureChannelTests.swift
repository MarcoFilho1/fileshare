import CryptoKit
import Foundation
import Testing
@testable import FileShareCore

struct SecureChannelTests {
    static let pairingKey = Data(0..<32)
    static let tabletNonce = Data(repeating: 0xA0, count: 16)
    static let macNonce = Data(repeating: 0xB0, count: 16)

    static func hex(_ d: Data) -> String { d.map { String(format: "%02x", $0) }.joined() }

    static func pair() -> (tablet: SecureChannel, mac: SecureChannel) {
        (SecureChannel(pairingKey: pairingKey, tabletNonce: tabletNonce, macNonce: macNonce, role: .tablet),
         SecureChannel(pairingKey: pairingKey, tabletNonce: tabletNonce, macNonce: macNonce, role: .mac))
    }

    /// Mesmos valores do SecureChannelTest.java: o Android precisa derivar e cifrar igual.
    @Test func matchesSharedVector() {
        let keys = SecureChannel.deriveKeys(pairingKey: Self.pairingKey, tabletNonce: Self.tabletNonce, macNonce: Self.macNonce)
        #expect(keys.tabletToMac.withUnsafeBytes { Self.hex(Data($0)) } == "97302912c35b777570dcbbe3251b944ea0544065536749f049dc77891a65477c")
        #expect(keys.macToTablet.withUnsafeBytes { Self.hex(Data($0)) } == "1c6b6886b71d45a6c1bb4d71e25af976a686c10ab058b6904382ad10cea7fa05")
        var tablet = Self.pair().tablet
        #expect(Self.hex(tablet.seal(Data("HELLO Tab\n".utf8))) == "536459b3e09ced1d5857f801afa1c0aee3e373f8bcf2e7ef6b07")
        #expect(Self.hex(tablet.seal(Data("PING\n".utf8))) == "f4afcab4d342284ca3f3263857c2236e8552d97308")
    }

    @Test func bothDirectionsRoundTrip() throws {
        var (tablet, mac) = Self.pair()
        for text in ["HELLO Tab\n", "CLIP 1 text/plain\noi", "PING\n"] {
            #expect(try mac.open(tablet.seal(Data(text.utf8))) == Data(text.utf8))
            #expect(try tablet.open(mac.seal(Data(text.utf8))) == Data(text.utf8))
        }
    }

    @Test func rejectsWrongPairingKey() {
        var tablet = SecureChannel(pairingKey: Data(repeating: 1, count: 32), tabletNonce: Self.tabletNonce, macNonce: Self.macNonce, role: .tablet)
        var mac = Self.pair().mac
        #expect(throws: SecureChannel.ChannelError.decryptFailed) { try mac.open(tablet.seal(Data("HELLO\n".utf8))) }
    }

    @Test func rejectsReplayedAndTamperedFrames() throws {
        var (tablet, mac) = Self.pair()
        let first = tablet.seal(Data("PING\n".utf8))
        _ = try mac.open(first)
        #expect(throws: SecureChannel.ChannelError.decryptFailed) { try mac.open(first) } // repetido
        var tampered = tablet.seal(Data("PING\n".utf8))
        tampered[0] ^= 1
        #expect(throws: SecureChannel.ChannelError.decryptFailed) { try mac.open(tampered) }
    }

    @Test func keysDependOnBothNonces() {
        var a = SecureChannel(pairingKey: Self.pairingKey, tabletNonce: Self.tabletNonce, macNonce: Self.macNonce, role: .tablet)
        var b = SecureChannel(pairingKey: Self.pairingKey, tabletNonce: Self.tabletNonce, macNonce: Data(repeating: 0xB1, count: 16), role: .tablet)
        #expect(a.seal(Data("PING\n".utf8)) != b.seal(Data("PING\n".utf8)))
    }
}
