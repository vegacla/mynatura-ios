import Core
import Foundation
import SwiftData

/// Motivo de precio (`GET /api/sales/pricing-reasons`).
@Model
public final class PricingReasonRecord {
    @Attribute(.unique) public var code: String
    public var label: String
    public var categoryRaw: String

    public init(code: String, label: String, category: PricingReasonCategory) {
        self.code = code
        self.label = label
        self.categoryRaw = category.rawValue
    }

    public var reason: PricingReason? {
        PricingReasonCategory(rawValue: categoryRaw).map { PricingReason(code: code, label: label, category: $0) }
    }
}

/// Carro persistido (§4.3): datos generales.
@Model
public final class CartDraft {
    @Attribute(.unique) public var sellerId: String
    public var note: String
    public var customerId: String?
    public var customerName: String?
    /// Pedido de cliente que se está convirtiendo en venta (etapa 10).
    public var sourceOrderId: String?

    public init(sellerId: String, note: String = "", customerId: String? = nil, customerName: String? = nil) {
        self.sellerId = sellerId
        self.note = note
        self.customerId = customerId
        self.customerName = customerName
    }
}

/// Línea del carro persistido.
@Model
public final class CartDraftLine {
    /// "\(sellerId)|\(productId)"
    @Attribute(.unique) public var key: String
    public var sellerId: String
    public var productId: String
    public var quantity: Int
    public var finalPricePesos: Int
    public var reasonCode: String?
    public var reasonNote: String?
    public var addedAt: Date

    public init(sellerId: String, productId: String, quantity: Int, finalPricePesos: Int) {
        self.key = Self.key(sellerId: sellerId, productId: productId)
        self.sellerId = sellerId
        self.productId = productId
        self.quantity = quantity
        self.finalPricePesos = finalPricePesos
        self.addedAt = .now
    }

    public static func key(sellerId: String, productId: String) -> String { "\(sellerId)|\(productId)" }

    public var finalPrice: Money {
        get { Money(pesos: finalPricePesos) }
        set { finalPricePesos = newValue.pesos }
    }
}

/// Línea de una venta guardada localmente.
public struct SaleLineSnapshot: Codable, Sendable, Equatable, Hashable {
    public var sellerProductId: String
    public var productName: String
    public var naturaSku: String
    public var quantity: Int
    public var suggestedPesos: Int?
    public var finalPesos: Int
    public var reasonCode: String?
    public var reasonNote: String?
    public var costUnitPesos: Int?
    /// Cómo se valorizó la salida (lotes, precio de referencia, pendiente). nil en ventas antiguas del backend.
    public var costAllocations: [CostAllocation]?

    public init(sellerProductId: String, productName: String, naturaSku: String, quantity: Int,
                suggestedPesos: Int?, finalPesos: Int, reasonCode: String?, reasonNote: String?, costUnitPesos: Int? = nil,
                costAllocations: [CostAllocation]? = nil) {
        self.sellerProductId = sellerProductId
        self.productName = productName
        self.naturaSku = naturaSku
        self.quantity = quantity
        self.suggestedPesos = suggestedPesos
        self.finalPesos = finalPesos
        self.reasonCode = reasonCode
        self.reasonNote = reasonNote
        self.costUnitPesos = costUnitPesos
        self.costAllocations = costAllocations
    }

    public var total: Money { Money(pesos: finalPesos * quantity) }

    /// Asignaciones de costo; en ventas antiguas se derivan del costo unitario (o quedan pendientes).
    public var effectiveAllocations: [CostAllocation] {
        if let costAllocations { return costAllocations }
        if let costUnitPesos {
            return [CostAllocation(lotId: "legacy", quantity: quantity, unitCost: Money(pesos: costUnitPesos), basis: .lot)]
        }
        return [CostAllocation(lotId: "legacy", quantity: quantity, unitCost: nil, basis: .pending)]
    }
}

/// Venta: descargada del backend o creada en el teléfono antes de sincronizar (§6 "LocalSale").
@Model
public final class LocalSale {
    /// clientMutationId (idempotencia).
    @Attribute(.unique) public var id: String
    public var sellerId: String
    public var serverId: String?
    public var occurredAt: Date
    public var note: String?
    public var customerId: String?
    public var customerName: String?
    public var linesData: Data
    public var syncStateRaw: String
    public var errorMessage: String?
    /// Venta u obsequio a terceros (precio 0, pérdida).
    public var kindRaw: String = OutflowKind.sale.rawValue

    public init(id: String, sellerId: String, serverId: String? = nil, occurredAt: Date, note: String?,
                customerId: String?, customerName: String?, lines: [SaleLineSnapshot], syncState: EntitySyncState,
                kind: OutflowKind = .sale) {
        self.id = id
        self.sellerId = sellerId
        self.serverId = serverId
        self.occurredAt = occurredAt
        self.note = note
        self.customerId = customerId
        self.customerName = customerName
        self.linesData = (try? JSONEncoder().encode(lines)) ?? Data()
        self.syncStateRaw = syncState.rawValue
        self.kindRaw = kind.rawValue
    }

    public var kind: OutflowKind { OutflowKind(rawValue: kindRaw) ?? .sale }

    /// Líneas para el reporte de ganancias (`ProfitReport`).
    public var outflowLines: [OutflowLine] {
        lines.map {
            OutflowLine(kind: kind, productId: $0.sellerProductId, quantity: $0.quantity,
                        unitPrice: Money(pesos: $0.finalPesos), allocations: $0.effectiveAllocations)
        }
    }

    public var lines: [SaleLineSnapshot] {
        get { (try? JSONDecoder().decode([SaleLineSnapshot].self, from: linesData)) ?? [] }
        set { linesData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    public var syncState: EntitySyncState {
        get { EntitySyncState(rawValue: syncStateRaw) ?? .synced }
        set { syncStateRaw = newValue.rawValue }
    }

    public var total: Money { lines.reduce(Money.zero) { $0 + $1.total } }

    public var cost: Money? {
        var total = 0
        for line in lines {
            guard let cost = line.costUnitPesos else { return nil }
            total += cost * line.quantity
        }
        return Money(pesos: total)
    }

    public var units: Int { lines.reduce(0) { $0 + $1.quantity } }
}
