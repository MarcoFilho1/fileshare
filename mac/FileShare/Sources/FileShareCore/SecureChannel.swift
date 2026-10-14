import CryptoKit
import Foundation

/// Criptografia da sessão. A chave de pareamento (lida pelo QR) nunca cifra nada diretamente:
/// cada conexão deriva duas chaves novas com HKDF-SHA256 a partir dela e dos nonces dos dois lados,
/// e cada quadro vai com ChaCha20-Poly1305 e um contador por sentido (protege contra repetição).
public struct SecureChannel {
    public enum Role { case mac, tablet }

    public enum ChannelError: Error, Equatable {
        case decryptFailed
    }

    private let sendKey: SymmetricKey
    private let receiveKey: SymmetricKey
    private var sendCounter: UInt64 = 0
    private var receiveCounter: UInt64 = 0

    public init(pairingKey: Data, tabletNonce: Data, macNonce: Data, role: Role) {
        let (tabletToMac, macToTablet) = Self.deriveKeys(pairingKey: pairingKey, tabletNonce: tabletNonce, macNonce: macNonce)
        sendKey = role == .mac ? macToTablet : tabletToMac
        receiveKey = role == .mac ? tabletToMac : macToTablet
    }

    static func deriveKeys(pairingKey: Data, tabletNonce: Data, macNonce: Data) -> (tabletToMac: SymmetricKey, macToTablet: SymmetricKey) {
        let ikm = SymmetricKey(data: pairingKey)
        let salt = tabletNonce + macNonce
        func key(_ info: String) -> SymmetricKey {
            HKDF<SHA256>.deriveKey(inputKeyMaterial: ikm, salt: salt, info: Data(info.utf8), outputByteCount: 32)
        }
        return (key("fileshare v1 tablet->mac"), key("fileshare v1 mac->tablet"))
    }

    static func nonce(_ counter: UInt64) -> ChaChaPoly.Nonce {
        var bytes = Data(count: 4)
        withUnsafeBytes(of: counter.bigEndian) { bytes.append(contentsOf: $0) }
        return try! ChaChaPoly.Nonce(data: bytes)
    }

    /// Cifra um quadro: texto cifrado + tag de 16 bytes (o nonce é o contador, implícito).
    public mutating func seal(_ plaintext: Data) -> Data {
        let box = try! ChaChaPoly.seal(plaintext, using: sendKey, nonce: Self.nonce(sendCounter))
        sendCounter += 1
        var out = Data(box.ciphertext) // o ciphertext é uma fatia; normaliza para índices a partir de 0
        out.append(box.tag)
        return out
    }

    public mutating func open(_ frame: Data) throws -> Data {
        guard frame.count >= 16 else { throw ChannelError.decryptFailed }
        do {
            let box = try ChaChaPoly.SealedBox(nonce: Self.nonce(receiveCounter),
                                               ciphertext: frame.dropLast(16), tag: frame.suffix(16))
            let plaintext = try ChaChaPoly.open(box, using: receiveKey)
            receiveCounter += 1
            return plaintext
        } catch {
            throw ChannelError.decryptFailed
        }
    }

    public static func randomBytes(_ count: Int) -> Data {
        var g = SystemRandomNumberGenerator()
        return Data((0..<count).map { _ in UInt8.random(in: .min ... .max, using: &g) })
    }
}
