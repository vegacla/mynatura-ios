import Core
import Foundation
import SwiftData

/// Pedido Natura importado (`GET /api/natura/orders`).
@Model
public final class NaturaOrder {
    @Attribute(.unique) public var id: String
    public var sellerId: String
    public var orderNumber: String
    public var cycle: Int
    public var subCycle: String?
    public var orderedAt: Date
    public var deliveredAt: Date?
    public var statusName: String
    public var itemsQuantity: Int
    public var totalValuePesos: Int
    public var ocrStatusRaw: String?
    public var ocrProcessedAt: Date?
    public var receivingClosedAt: Date?
    public var reviewStatusRaw: String
    public var receivedUnits: Int
    public var pendingUnits: Int
    public var linesLoaded: Bool

    public init(id: String, sellerId: String, orderNumber: String, cycle: Int, orderedAt: Date) {
        self.id = id
        self.sellerId = sellerId
        self.orderNumber = orderNumber
        self.cycle = cycle
        self.orderedAt = orderedAt
        self.statusName = ""
        self.itemsQuantity = 0
        self.totalValuePesos = 0
        self.reviewStatusRaw = ReceivingReviewStatus.draft.rawValue
        self.receivedUnits = 0
        self.pendingUnits = 0
        self.linesLoaded = false
    }

    public var reviewStatus: ReceivingReviewStatus {
        get { ReceivingReviewStatus(rawValue: reviewStatusRaw) ?? .draft }
        set { reviewStatusRaw = newValue.rawValue }
    }

    public var isClosed: Bool { reviewStatus == .closed }

    public var receivingStatus: ReceivingStatus {
        ReceivingStatus.derive(receivedUnits: receivedUnits, pendingUnits: pendingUnits)
    }
}

/// Línea de pedido Natura (detalle `GET /api/natura/orders/:id`).
@Model
public final class NaturaOrderLine {
    @Attribute(.unique) public var id: String
    public var orderId: String
    public var sellerId: String
    public var position: Int
    public var naturaSku: String
    public var productName: String
    public var quantity: Int
    public var purchasePesos: Int?
    public var suggestedPesos: Int?
    public var proposedSuggestedPesos: Int?
    public var receivedQuantity: Int
    public var proposedReceivedQuantity: Int?
    public var receivedConfirmedAt: Date?
    public var barcodes: [String]
    public var syncStateRaw: String

    public init(id: String, orderId: String, sellerId: String, position: Int, naturaSku: String, productName: String, quantity: Int) {
        self.id = id
        self.orderId = orderId
        self.sellerId = sellerId
        self.position = position
        self.naturaSku = naturaSku
        self.productName = productName
        self.quantity = quantity
        self.receivedQuantity = 0
        self.barcodes = []
        self.syncStateRaw = EntitySyncState.synced.rawValue
    }

    public var syncState: EntitySyncState {
        get { EntitySyncState(rawValue: syncStateRaw) ?? .synced }
        set { syncStateRaw = newValue.rawValue }
    }

    public var shortage: Int { ReceivingRules.shortage(ordered: quantity, confirmed: receivedQuantity) }

    public var scanRef: ReceivingLineRef {
        ReceivingLineRef(id: id, sku: naturaSku, barcodes: barcodes, ordered: quantity, received: receivedQuantity)
    }
}
