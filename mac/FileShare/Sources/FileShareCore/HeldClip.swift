import Foundation

/// Última cópia feita no Mac enquanto o tablet estava fora (tela apagada, Wi-Fi caiu…).
/// Só a mais recente importa, e ela expira: ninguém quer colar algo copiado horas atrás.
public struct HeldClip {
    public static let lifetime: TimeInterval = 10 * 60

    public private(set) var payload: ClipPayload?
    public private(set) var copiedAt: Date?

    public init() {}

    public mutating func hold(_ payload: ClipPayload, copiedAt: Date) {
        self.payload = payload
        self.copiedAt = copiedAt
    }

    /// Entrega e esvazia; nil se não havia nada ou se expirou.
    public mutating func take(now: Date) -> (payload: ClipPayload, copiedAt: Date)? {
        defer { discard() }
        guard let payload, let copiedAt, now.timeIntervalSince(copiedAt) <= Self.lifetime else { return nil }
        return (payload, copiedAt)
    }

    public mutating func discard() {
        payload = nil
        copiedAt = nil
    }
}
