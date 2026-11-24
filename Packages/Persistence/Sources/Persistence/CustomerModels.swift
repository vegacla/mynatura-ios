import Core
import Foundation
import SwiftData

/// Cliente de la consultora (`/api/customers`). Puede crearse offline con id local.
@Model
public final class Customer {
    @Attribute(.unique) public var id: String
    public var sellerId: String
    public var displayName: String
    public var normalizedName: String
    public var rut: String?
    public var phone: String?
    public var notes: String?
    public var updatedAt: Date
    public var syncStateRaw: String

    public init(id: String, sellerId: String, displayName: String, rut: String?, phone: String?, notes: String?,
                updatedAt: Date = .now, syncState: EntitySyncState = .synced) {
        self.id = id
        self.sellerId = sellerId
        self.displayName = displayName
        self.normalizedName = Normalize.customerName(displayName)
        self.rut = rut
        self.phone = phone
        self.notes = notes
        self.updatedAt = updatedAt
        self.syncStateRaw = syncState.rawValue
    }

    public var syncState: EntitySyncState {
        get { EntitySyncState(rawValue: syncStateRaw) ?? .synced }
        set { syncStateRaw = newValue.rawValue }
    }

    public func rename(_ name: String) {
        displayName = name
        normalizedName = Normalize.customerName(name)
    }
}

/// Línea de pedido de cliente.
public struct CustomerOrderLineSnapshot: Codable, Sendable, Equatable, Hashable, Identifiable {
    public var id: String
    public var sellerProductId: String
    public var productName: String
    public var naturaSku: String
    public var quantity: Int
    public var suggestedPesos: Int?
    public var finalPesos: Int?
    public var note: String?

    public init(id: String = UUID().uuidString, sellerProductId: String, productName: String, naturaSku: String,
                quantity: Int, suggestedPesos: Int?, finalPesos: Int?, note: String? = nil) {
        self.id = id
        self.sellerProductId = sellerProductId
        self.productName = productName
        self.naturaSku = naturaSku
        self.quantity = quantity
        self.suggestedPesos = suggestedPesos
        self.finalPesos = finalPesos
        self.note = note
    }
}

/// Pedido de cliente por ciclo (intención de compra, no mueve stock).
@Model
public final class CustomerOrder {
    @Attribute(.unique) public var id: String
    public var sellerId: String
    public var customerId: String
    public var customerDisplayName: String
    public var cycle: Int
    public var statusRaw: String
    public var note: String?
    public var orderedAt: Date
    public var updatedAt: Date
    public var lineCount: Int
    public var linesData: Data?
    public var syncStateRaw: String

    public init(id: String, sellerId: String, customerId: String, customerDisplayName: String, cycle: Int,
                status: CustomerOrderStatus, note: String?, orderedAt: Date, updatedAt: Date = .now,
                syncState: EntitySyncState = .synced) {
        self.id = id
        self.sellerId = sellerId
        self.customerId = customerId
        self.customerDisplayName = customerDisplayName
        self.cycle = cycle
        self.statusRaw = status.rawValue
        self.note = note
        self.orderedAt = orderedAt
        self.updatedAt = updatedAt
        self.lineCount = 0
        self.syncStateRaw = syncState.rawValue
    }

    public var status: CustomerOrderStatus {
        get { CustomerOrderStatus(rawValue: statusRaw) ?? .draft }
        set { statusRaw = newValue.rawValue }
    }

    public var syncState: EntitySyncState {
        get { EntitySyncState(rawValue: syncStateRaw) ?? .synced }
        set { syncStateRaw = newValue.rawValue }
    }

    /// nil = aún no se descargó el detalle.
    public var lines: [CustomerOrderLineSnapshot]? {
        get { linesData.flatMap { try? JSONDecoder().decode([CustomerOrderLineSnapshot].self, from: $0) } }
        set {
            linesData = newValue.flatMap { try? JSONEncoder().encode($0) }
            if let newValue { lineCount = newValue.count }
        }
    }
}
