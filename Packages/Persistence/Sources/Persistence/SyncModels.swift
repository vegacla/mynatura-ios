import Core
import Foundation
import SwiftData

/// Mutación offline pendiente de enviar (§6, §7).
@Model
public final class PendingMutation {
    /// = clientMutationId (idempotencia).
    @Attribute(.unique) public var id: UUID
    public var typeRaw: String
    public var sellerId: String
    /// Entidad local afectada (id de venta, producto, línea, cliente, pedido…).
    public var entityKey: String
    /// JSON del DTO de entrada (más datos de ruta cuando aplica).
    public var payload: Data
    public var statusRaw: String
    public var retryCount: Int
    public var createdAt: Date
    public var nextAttemptAt: Date?
    public var lastErrorMessage: String?
    /// Productos cuyo stock/catálogo no debe pisar el pull mientras esto esté pendiente.
    public var relatedProductIds: [String]

    public init(type: MutationType, sellerId: String, entityKey: String, payload: Data, relatedProductIds: [String] = []) {
        self.id = UUID()
        self.typeRaw = type.rawValue
        self.sellerId = sellerId
        self.entityKey = entityKey
        self.payload = payload
        self.statusRaw = MutationStatus.pending.rawValue
        self.retryCount = 0
        self.createdAt = .now
        self.relatedProductIds = relatedProductIds
    }

    public var type: MutationType? { MutationType(rawValue: typeRaw) }

    public var status: MutationStatus {
        get { MutationStatus(rawValue: statusRaw) ?? .pending }
        set { statusRaw = newValue.rawValue }
    }

    public var payloadText: String { String(decoding: payload, as: UTF8.self) }
}

/// Evento de inventario para el kardex (`GET /api/inventory/activity`), o local pendiente.
@Model
public final class InventoryEventRecord {
    @Attribute(.unique) public var id: String
    public var sellerId: String
    public var sellerProductId: String
    public var kindRaw: String
    public var quantity: Int
    public var note: String?
    public var occurredAt: Date
    public var isLocal: Bool

    public init(id: String, sellerId: String, sellerProductId: String, kind: InventoryEventKind,
                quantity: Int, note: String?, occurredAt: Date, isLocal: Bool) {
        self.id = id
        self.sellerId = sellerId
        self.sellerProductId = sellerProductId
        self.kindRaw = kind.rawValue
        self.quantity = quantity
        self.note = note
        self.occurredAt = occurredAt
        self.isLocal = isLocal
    }

    public var kind: InventoryEventKind { InventoryEventKind(rawValue: kindRaw) ?? .receipt }

    public var kardexEntry: KardexEntry {
        KardexEntry(id: id, occurredAt: occurredAt, kind: kind, quantity: quantity, note: note, isPending: isLocal)
    }
}
