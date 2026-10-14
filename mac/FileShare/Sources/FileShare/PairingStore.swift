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

    static func loadKey() -> Data? {
        var result: AnyObject?
        let status = SecItemCopyMatching([
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
        ] as CFDictionary, &result)
        return status == errSecSuccess ? result as? Data : nil
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
