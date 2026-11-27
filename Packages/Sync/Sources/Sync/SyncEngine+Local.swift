import Core
import Foundation
import Persistence
import SwiftData

/// Inventario local (M2 de docs/local-first-migration.md): el iPhone es la fuente de verdad.
/// El stock es la suma de los lotes; cada salida consume lotes según el método de costeo y guarda su costo.
extension SyncEngine {
    // MARK: Modo local

    func settings(sellerId: String) -> SellerSettings {
        if let existing = fetchAll(FetchDescriptor<SellerSettings>(predicate: #Predicate { $0.sellerId == sellerId })).first {
            return existing
        }
        let created = SellerSettings(sellerId: sellerId, issueStrategy: .fifo)
        context.insert(created)
        return created
    }

    /// Desde M3 el inventario y todos los datos son locales: el backend ya no se lee ni se escribe.
    public func isLocalInventory(sellerId: String) -> Bool { true }

    public func costingMethod(sellerId: String) -> CostingMethod {
        fetchAll(FetchDescriptor<SellerSettings>(predicate: #Predicate { $0.sellerId == sellerId })).first?
            .costingMethod ?? .fifo
    }

    /// Cambia el método de costeo (local, sin conexión). Afecta las salidas futuras; las registradas no cambian.
    public func setCostingMethod(_ method: CostingMethod, sellerId: String) {
        settings(sellerId: sellerId).costingMethod = method
        save()
    }

    /// Pasa a inventario local una sola vez: el stock bajado del backend queda como lotes de saldo inicial
    /// (costo = último costo de compra; si es 0, unidad gratis). Las mutaciones pendientes se descartan porque
    /// su efecto ya está en el stock local y el backend deja de recibir cambios.
    public func adoptLocalInventoryIfNeeded(sellerId: String) {
        let current = settings(sellerId: sellerId)
        guard current.localInventoryAdoptedAt == nil else { return }
        // M3: ya no se convierte el stock del backend en lotes; el inventario sale de la importación directa
        // y de "Agregar inventario actual". Solo se marca el modo local y se vacía la cola.
        for mutation in pendingMutations(sellerId: sellerId) { context.delete(mutation) }
        current.localInventoryAdoptedAt = .now
        save()
        if current.localInventoryAdoptedAt != nil { return }
        // (Código de M2 que convertía el stock del backend en saldo inicial; ya no se alcanza.)
        let stockKey = DatasetSyncState.key(sellerId: sellerId, dataset: .stock)
        guard fetchAll(FetchDescriptor<DatasetSyncState>(predicate: #Predicate { $0.key == stockKey })).first?
            .lastSyncedAt != nil else { return }
        let items = fetchAll(FetchDescriptor<StockItem>(predicate: #Predicate { $0.sellerId == sellerId }))
        let existingLots = fetchAll(FetchDescriptor<InventoryLotRecord>(predicate: #Predicate { $0.sellerId == sellerId }))
        let withLots = Set(existingLots.map(\.productId))
        let now = Date()
        for item in items where item.operationalQuantity > 0 && !withLots.contains(item.sellerProductId) {
            let cost = product(id: item.sellerProductId)?.lastPurchasePesos ?? 0
            context.insert(InventoryLotRecord(
                sellerId: sellerId, productId: item.sellerProductId, receivedAt: now, quantity: item.operationalQuantity,
                unitCost: Money(pesos: max(cost, 0)), source: cost > 0 ? .purchased : .free, origin: .opening,
                note: "Saldo inicial al pasar a inventario local"))
            item.theoreticalQuantity = item.operationalQuantity
        }
        for mutation in pendingMutations(sellerId: sellerId) { context.delete(mutation) }
        for event in fetchAll(FetchDescriptor<InventoryEventRecord>(predicate: #Predicate { $0.sellerId == sellerId && $0.isLocal })) {
            event.isLocal = false
        }
        for product in fetchAll(FetchDescriptor<CatalogProduct>(predicate: #Predicate { $0.sellerId == sellerId })) {
            product.syncState = .synced
        }
        for sale in fetchAll(FetchDescriptor<LocalSale>(predicate: #Predicate { $0.sellerId == sellerId })) where sale.syncState != .synced {
            sale.syncState = .synced
            sale.errorMessage = nil
        }
        for customer in fetchAll(FetchDescriptor<Customer>(predicate: #Predicate { $0.sellerId == sellerId })) {
            customer.syncState = .synced
        }
        for order in fetchAll(FetchDescriptor<CustomerOrder>(predicate: #Predicate { $0.sellerId == sellerId })) {
            order.syncState = .synced
        }
        for line in fetchAll(FetchDescriptor<NaturaOrderLine>(predicate: #Predicate { $0.sellerId == sellerId })) {
            line.syncState = .synced
        }
        current.localInventoryAdoptedAt = now
        save()
        AppLog.sync.info("Inventario local adoptado")
    }

    // MARK: Lotes

    func lotRecords(productId: String) -> [InventoryLotRecord] {
        fetchAll(FetchDescriptor<InventoryLotRecord>(predicate: #Predicate { $0.productId == productId }))
    }

    /// Agrega stock como lote nuevo y recalcula el stock del producto.
    @discardableResult
    func addLot(sellerId: String, productId: String, quantity: Int, unitCost: Money?, source: CostSource,
                origin: LotOrigin, naturaOrderLineId: String? = nil, note: String? = nil, receivedAt: Date = .now,
                suggestedPesos: Int? = nil) -> InventoryLotRecord? {
        guard quantity > 0 else { return nil }
        let record = InventoryLotRecord(sellerId: sellerId, productId: productId, receivedAt: receivedAt, quantity: quantity,
                                        unitCost: unitCost, source: source, origin: origin,
                                        naturaOrderLineId: naturaOrderLineId, note: note, suggestedPesos: suggestedPesos)
        context.insert(record)
        if let product = product(id: productId), let cost = unitCost, cost.pesos > 0,
           source == .purchased || source == .manual {
            product.lastPurchasePesos = cost.pesos
        }
        refreshStock(productId: productId, sellerId: sellerId)
        return record
    }

    /// Saca unidades según el método de costeo; devuelve las asignaciones de costo.
    func consumeLots(sellerId: String, productId: String, quantity: Int) -> CostingResult {
        let records = lotRecords(productId: productId)
        let result = CostingEngine.consume(quantity, from: records.map(\.lot), method: costingMethod(sellerId: sellerId))
        let remaining = Dictionary(result.lots.map { ($0.id, $0.remaining) }, uniquingKeysWith: { first, _ in first })
        for record in records {
            if let value = remaining[record.id] { record.remaining = value }
        }
        refreshStock(productId: productId, sellerId: sellerId)
        return result
    }

    /// Stock del producto = suma de lo que queda en sus lotes.
    func refreshStock(productId: String, sellerId: String) {
        let total = lotRecords(productId: productId).reduce(0) { $0 + max($1.remaining, 0) }
        if let item = stockItem(productId: productId) {
            item.operationalQuantity = total
            item.theoreticalQuantity = total
        } else if let product = product(id: productId) {
            context.insert(StockItem(sellerProductId: productId, sellerId: sellerId, naturaSku: product.naturaSku,
                                     name: product.name, isSellable: product.isSellable,
                                     theoreticalQuantity: total, operationalQuantity: total, lastReconciledAt: nil))
        }
    }

    func availableStock(productId: String) -> Int {
        lotRecords(productId: productId).reduce(0) { $0 + max($1.remaining, 0) }
    }

    /// Evento del kardex (local, definitivo).
    func addEvent(sellerId: String, productId: String, kind: InventoryEventKind, quantity: Int, note: String?,
                  occurredAt: Date = .now) {
        context.insert(InventoryEventRecord(
            id: UUID().uuidString, sellerId: sellerId, sellerProductId: productId,
            kind: kind, quantity: quantity, note: note, occurredAt: occurredAt, isLocal: false))
    }

    /// Completa el costo de un lote desconocido y revaloriza las salidas que lo usaron.
    public func completeLotCost(lotId: String, unitCost: Money) -> ActionError? {
        guard unitCost.pesos >= 0 else { return ActionError("El costo no puede ser negativo.") }
        guard let record = fetchAll(FetchDescriptor<InventoryLotRecord>(predicate: #Predicate { $0.id == lotId })).first else {
            return ActionError("Lote no encontrado.")
        }
        record.unitCost = unitCost
        record.source = unitCost.pesos == 0 ? .free : .manual
        let sellerId = record.sellerId
        for sale in fetchAll(FetchDescriptor<LocalSale>(predicate: #Predicate { $0.sellerId == sellerId })) {
            var changed = false
            let updated = sale.lines.map { line -> SaleLineSnapshot in
                guard let allocations = line.costAllocations, allocations.contains(where: { $0.lotId == lotId }) else { return line }
                var copy = line
                let revalued = CostingEngine.revalue(allocations, completing: lotId, unitCost: unitCost)
                copy.costAllocations = revalued
                copy.costUnitPesos = Self.unitCost(of: revalued, quantity: line.quantity)
                changed = true
                return copy
            }
            if changed { sale.lines = updated }
        }
        save()
        return nil
    }

    /// Costo unitario promedio de una salida; nil si quedó algo pendiente.
    static func unitCost(of allocations: [CostAllocation], quantity: Int) -> Int? {
        guard quantity > 0, !allocations.contains(where: { $0.basis == .pending }) else { return nil }
        let total = allocations.reduce(0) { $0 + ($1.totalCost?.pesos ?? 0) }
        return Int((Double(total) / Double(quantity)).rounded())
    }

    /// Lote de una línea de pedido Natura por su valor unitario: > 0 comprado, 0 gratis, sin valor desconocido.
    func lotClassification(for line: NaturaOrderLine) -> LotClassifier.Classification {
        guard let pesos = line.purchasePesos else { return LotClassifier.Classification(source: .unknown, unitCost: nil) }
        return pesos > 0
            ? LotClassifier.Classification(source: .purchased, unitCost: Money(pesos: pesos))
            : LotClassifier.Classification(source: .free, unitCost: .zero)
    }
}
