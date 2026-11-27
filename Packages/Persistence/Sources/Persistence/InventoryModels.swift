import Core
import Foundation
import SwiftData

/// Lote de inventario local (docs/local-first-migration.md §4): fuente de verdad del stock y del costo.
@Model
public final class InventoryLotRecord {
    @Attribute(.unique) public var id: String
    public var sellerId: String
    public var productId: String
    public var receivedAt: Date
    public var quantity: Int
    public var remaining: Int
    /// nil = costo desconocido (`CostSource.unknown`).
    public var unitCostPesos: Int?
    public var sourceRaw: String
    /// Origen del lote: saldo inicial, línea de pedido Natura, conciliación o manual.
    public var originRaw: String
    public var naturaOrderLineId: String?
    public var note: String?

    public init(id: String = UUID().uuidString, sellerId: String, productId: String, receivedAt: Date, quantity: Int,
                unitCost: Money?, source: CostSource, origin: LotOrigin, naturaOrderLineId: String? = nil, note: String? = nil) {
        self.id = id
        self.sellerId = sellerId
        self.productId = productId
        self.receivedAt = receivedAt
        self.quantity = quantity
        self.remaining = quantity
        self.unitCostPesos = unitCost?.pesos
        self.sourceRaw = source.rawValue
        self.originRaw = origin.rawValue
        self.naturaOrderLineId = naturaOrderLineId
        self.note = note
    }

    public var source: CostSource {
        get { CostSource(rawValue: sourceRaw) ?? .unknown }
        set { sourceRaw = newValue.rawValue }
    }

    public var origin: LotOrigin { LotOrigin(rawValue: originRaw) ?? .manual }

    public var unitCost: Money? {
        get { unitCostPesos.map { Money(pesos: $0) } }
        set { unitCostPesos = newValue?.pesos }
    }

    /// Vista pura para el motor de costeo de `Core`.
    public var lot: InventoryLot {
        InventoryLot(id: id, productId: productId, receivedAt: receivedAt, quantity: quantity, remaining: remaining,
                     unitCost: unitCost, source: source)
    }
}

public enum LotOrigin: String, Sendable, Codable {
    /// Stock que ya existía al pasar a modo local (bajado del backend).
    case opening
    case naturaLine
    case reconciliation
    case manual
}
