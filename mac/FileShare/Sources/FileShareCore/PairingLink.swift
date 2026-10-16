import Foundation

/// Conteúdo do QR de pareamento:
/// https://marcofilho1.github.io/fileshare/pair/#v=1&id=<id do Mac>&name=<nome>&k=<chave base64url>
///
/// É um link de site para funcionar mesmo sem o app no tablet: a página (site/pair) abre o FileShare
/// com fileshare://pair?<mesmos campos> ou, se ele não estiver instalado, mostra como instalar.
/// Tudo vai depois do "#", parte que o navegador nunca envia ao servidor: a chave só existe no QR,
/// no Keychain do Mac e no Keystore do tablet.
public enum PairingLink {
    public static let page = "https://marcofilho1.github.io/fileshare/pair/"

    public static func url(macId: String, name: String, key: Data) -> String {
        page + "#" + fields(macId: macId, name: name, key: key)
    }

    /// Link direto para o app (o que a página abre): fileshare://pair?v=1&...
    public static func appURL(macId: String, name: String, key: Data) -> String {
        "fileshare://pair?" + fields(macId: macId, name: name, key: key)
    }

    static func fields(macId: String, name: String, key: Data) -> String {
        var c = URLComponents()
        c.queryItems = [
            URLQueryItem(name: "v", value: "1"),
            URLQueryItem(name: "id", value: macId),
            URLQueryItem(name: "name", value: name),
            URLQueryItem(name: "k", value: base64url(key)),
        ]
        return c.percentEncodedQuery!
    }

    static func base64url(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
