import Core
import Foundation
import Observation
import Persistence
import SwiftData

/// Store local (M7 de docs/local-first-migration.md): el iPhone es la fuente de verdad. Cada acción escribe directo
/// en SwiftData (sin cola ni servidor); lo de Natura se trae bajo demanda.
@MainActor
@Observable
public final class LocalStore {
    /// Último error al guardar (para Diagnóstico).
    public internal(set) var lastErrorMessage: String?

    let context: ModelContext
    public let connectivity: ConnectivityMonitor

    public init(context: ModelContext, connectivity: ConnectivityMonitor) {
        self.context = context
        self.connectivity = connectivity
    }

    func save() {
        do {
            try context.save()
        } catch {
            lastErrorMessage = "No se pudo guardar: \(error.localizedDescription)"
            AppLog.sync.error("Error guardando SwiftData: \(String(describing: error), privacy: .public)")
        }
    }

    // MARK: - Consultas comunes

    func fetchAll<T: PersistentModel>(_ descriptor: FetchDescriptor<T>) -> [T] {
        (try? context.fetch(descriptor)) ?? []
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

    /// Restos de la cola del backend (anterior a M7): se descartan.
    func clearLegacyQueue(sellerId: String) {
        for mutation in fetchAll(FetchDescriptor<PendingMutation>(predicate: #Predicate { $0.sellerId == sellerId })) {
            context.delete(mutation)
        }
    }
}
