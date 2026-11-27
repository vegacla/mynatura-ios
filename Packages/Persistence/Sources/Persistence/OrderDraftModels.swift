import Core
import Foundation
import SwiftData

/// Borrador del pedido Natura de un ciclo (M8 etapa 2): local, sin conexión. Uno por ciclo.
@Model
public final class NaturaOrderDraft {
    /// "\(sellerId)|\(cycle)"
    @Attribute(.unique) public var key: String
    public var sellerId: String
    public var cycle: Int
    public var linesData: Data?
    /// Tope de puntos del nivel (a mano hasta que se lea de Natura).
    public var pointsLimit: Int?
    public var updatedAt: Date

    public init(sellerId: String, cycle: Int) {
        self.key = Self.key(sellerId: sellerId, cycle: cycle)
        self.sellerId = sellerId
        self.cycle = cycle
        self.updatedAt = .now
    }

    public static func key(sellerId: String, cycle: Int) -> String { "\(sellerId)|\(cycle)" }

    public var lines: [OrderDraftLine] {
        get { linesData.flatMap { try? JSONDecoder().decode([OrderDraftLine].self, from: $0) } ?? [] }
        set {
            linesData = try? JSONEncoder().encode(newValue)
            updatedAt = .now
        }
    }
}
