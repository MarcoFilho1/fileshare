import Foundation
import Security

/// Pareamento no Mac: o id (não é segredo) fica nas preferências; a chave fica no Keychain.
enum PairingStore {
    private static let service = "dev.marcofilho.fileshare.pairing"
    private static let account = "tablet"

    static var macId: String {
        if let id = UserDefaults.standard.string(forKey: "macId") { return id }
        let id = UUID().uuidString.lowercased()
        UserDefaults.standard.set(id, forKey: "macId")
        return id
    }

    enum KeyLookup {
        case found(Data)
        /// Nunca pareou, ou o tablet foi esquecido.
        case missing
        /// A chave existe, mas o macOS não a entregou (acesso às Chaves negado, Chaves trancadas…).
        /// Não é o mesmo que "não pareado": abrir o pareamento aqui apagaria a chave boa.
        case failed(OSStatus)
    }

    /// Pode bloquear enquanto o macOS pergunta se o app pode usar as Chaves: chame fora da thread principal.
    static func loadKey() -> KeyLookup {
        var result: AnyObject?
        let status = SecItemCopyMatching([
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
        ] as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let key = result as? Data else { return .failed(status) }
            return .found(key)
        case errSecItemNotFound: return .missing
        default: return .failed(status)
        }
    }

    @discardableResult
    static func saveKey(_ key: Data) -> Bool {
        deleteKey()
        return SecItemAdd([
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecAttrLabel: "FileShare: pareamento com o tablet",
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData: key,
        ] as CFDictionary, nil) == errSecSuccess
    }

    static func deleteKey() {
        SecItemDelete([kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account] as CFDictionary)
    }
}
