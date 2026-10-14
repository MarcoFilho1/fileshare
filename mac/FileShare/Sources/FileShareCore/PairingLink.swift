import Foundation

/// Conteúdo do QR de pareamento: fileshare://pair?v=1&id=<id do Mac>&name=<nome>&k=<chave base64url>.
/// O tablet abre esse link pela câmera; a chave só existe no QR, no Keychain do Mac e no Keystore do tablet.
public enum PairingLink {
    public static func url(macId: String, name: String, key: Data) -> String {
        var c = URLComponents()
        c.scheme = "fileshare"
        c.host = "pair"
        c.queryItems = [
            URLQueryItem(name: "v", value: "1"),
            URLQueryItem(name: "id", value: macId),
            URLQueryItem(name: "name", value: name),
            URLQueryItem(name: "k", value: base64url(key)),
        ]
        return c.string!
    }

    static func base64url(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
