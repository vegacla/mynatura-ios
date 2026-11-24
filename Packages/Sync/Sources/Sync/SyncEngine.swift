import APIClient
import Core
import Foundation
import Observation
import Persistence
import SwiftData

/// Motor de sincronización (§7): escritura local primero + cola de mutaciones, push ordenado
/// con reintentos y pull de datasets con merge que respeta lo pendiente.
@MainActor
@Observable
public final class SyncEngine {
    public internal(set) var isPulling = false
    public internal(set) var isPushing = false
    public internal(set) var lastErrorMessage: String?
    public internal(set) var lastPushAt: Date?

    public var isSyncing: Bool { isPulling || isPushing }

    /// Se llama cuando el backend responde 401 (la sesión expiró).
    public var onUnauthorized: (@MainActor () -> Void)?

    let api: any APIClient
    let context: ModelContext
    public let connectivity: ConnectivityMonitor

    public init(api: any APIClient, context: ModelContext, connectivity: ConnectivityMonitor) {
        self.api = api
        self.context = context
        self.connectivity = connectivity
    }

    /// Push de la cola y luego pull completo.
    public func syncNow(sellerId: String) async {
        await pushPending(sellerId: sellerId)
        await pullAll(sellerId: sellerId)
    }

    /// Tras una escritura local: si hay red, intenta enviar de inmediato (§7.2 paso 4).
    func pushSoon(sellerId: String) {
        guard connectivity.isOnline else { return }
        Task { await self.pushPending(sellerId: sellerId) }
    }

    func save() {
        do {
            try context.save()
        } catch {
            AppLog.sync.error("Error guardando SwiftData: \(String(describing: error), privacy: .public)")
        }
    }

    func handle(_ error: APIError) {
        lastErrorMessage = error.userMessage
        if case .unauthorized = error { onUnauthorized?() }
    }

    func fetch<R: Decodable & Sendable>(_ endpoint: Endpoint<R>) async -> Result<R, APIError> {
        do throws(APIError) {
            return .success(try await api.send(endpoint))
        } catch {
            return .failure(error)
        }
    }

    // MARK: - Consultas comunes

    func fetchAll<T: PersistentModel>(_ descriptor: FetchDescriptor<T>) -> [T] {
        (try? context.fetch(descriptor)) ?? []
    }

    func pendingMutations(sellerId: String) -> [PendingMutation] {
        fetchAll(FetchDescriptor<PendingMutation>(predicate: #Predicate { $0.sellerId == sellerId }))
    }

    /// Productos con mutaciones pendientes o fallidas: el pull no pisa su stock/catálogo (§7.4).
    func protectedProductIds(sellerId: String) -> Set<String> {
        var ids = Set(pendingMutations(sellerId: sellerId).flatMap(\.relatedProductIds))
        let products = fetchAll(FetchDescriptor<CatalogProduct>(predicate: #Predicate { $0.sellerId == sellerId }))
        ids.formUnion(products.filter { $0.syncState != .synced }.map(\.id))
        return ids
    }

    func product(id: String) -> CatalogProduct? {
        fetchAll(FetchDescriptor<CatalogProduct>(predicate: #Predicate { $0.id == id })).first
    }

    func stockItem(productId: String) -> StockItem? {
        fetchAll(FetchDescriptor<StockItem>(predicate: #Predicate { $0.sellerProductId == productId })).first
    }

    func product(sku: String, sellerId: String) -> CatalogProduct? {
        let normalized = Normalize.naturaSku(sku).lowercased()
        return fetchAll(FetchDescriptor<CatalogProduct>(predicate: #Predicate { $0.sellerId == sellerId }))
            .first { Normalize.naturaSku($0.naturaSku).lowercased() == normalized }
    }

    /// Ajusta el stock local (§5.4 "stock local offline").
    func adjustStock(productId: String, sellerId: String, delta: Int) {
        if let item = stockItem(productId: productId) {
            item.operationalQuantity = max(item.operationalQuantity + delta, 0)
            item.theoreticalQuantity = max(item.theoreticalQuantity + delta, 0)
        } else if let product = product(id: productId), delta > 0 {
            context.insert(StockItem(sellerProductId: productId, sellerId: sellerId, naturaSku: product.naturaSku,
                                     name: product.name, isSellable: product.isSellable,
                                     theoreticalQuantity: delta, operationalQuantity: delta, lastReconciledAt: nil))
        }
    }

    /// Evento local para el kardex mientras la mutación esté pendiente.
    func addLocalEvent(mutationId: UUID, sellerId: String, productId: String, kind: InventoryEventKind, quantity: Int, note: String?) {
        context.insert(InventoryEventRecord(
            id: "\(mutationId.uuidString)|\(productId)|\(UUID().uuidString)", sellerId: sellerId, sellerProductId: productId,
            kind: kind, quantity: quantity, note: note, occurredAt: .now, isLocal: true))
    }

    func removeLocalEvents(mutationId: UUID) {
        let prefix = mutationId.uuidString + "|"
        for event in fetchAll(FetchDescriptor<InventoryEventRecord>(predicate: #Predicate { $0.isLocal }))
        where event.id.hasPrefix(prefix) {
            context.delete(event)
        }
    }

    /// Inserta una mutación en la misma transacción que el cambio local (§7.2).
    @discardableResult
    func enqueue(_ type: MutationType, sellerId: String, entityKey: String, payload: some Encodable,
                 relatedProductIds: [String] = []) -> PendingMutation {
        let mutation = PendingMutation(type: type, sellerId: sellerId, entityKey: entityKey,
                                       payload: PayloadCoding.encode(payload), relatedProductIds: relatedProductIds)
        context.insert(mutation)
        AppLog.sync.info("Encolada \(type.rawValue, privacy: .public) \(entityKey, privacy: .public)")
        return mutation
    }

    /// Mutación pendiente (no en envío) del mismo tipo y entidad, para fusionar cambios (LWW).
    func coalescible(_ type: MutationType, entityKey: String, sellerId: String) -> PendingMutation? {
        pendingMutations(sellerId: sellerId).first {
            $0.type == type && $0.entityKey == entityKey && $0.status != .syncing
        }
    }
}
