import APIClient
import Core
import Foundation
import Observation
import Persistence
import SwiftData

/// Motor de sincronización (§7). Etapa 2: pull de catálogo, stock y ajustes.
/// El push de la cola de mutaciones llega en la etapa 4.
@MainActor
@Observable
public final class SyncEngine {
    public private(set) var isPulling = false
    public private(set) var lastErrorMessage: String?

    /// Se llama cuando el backend responde 401 (la sesión expiró).
    public var onUnauthorized: (@MainActor () -> Void)?

    private let api: any APIClient
    private let context: ModelContext

    public init(api: any APIClient, context: ModelContext) {
        self.api = api
        self.context = context
    }

    // MARK: - Pull

    /// Descarga todos los datasets disponibles y los aplica a SwiftData.
    public func pullAll(sellerId: String) async {
        guard !isPulling else { return }
        isPulling = true
        defer { isPulling = false }
        lastErrorMessage = nil

        let datasets: [Dataset] = [.catalog, .stock, .settings]
        for dataset in datasets { markSyncing(sellerId: sellerId, dataset: dataset) }

        async let catalog = fetch(.catalogProducts)
        async let stock = fetch(.stockSummary)
        async let settings = fetch(.settings)
        let results = await (catalog, stock, settings)

        apply(results.0, dataset: .catalog, sellerId: sellerId) { applyCatalog($0.products, sellerId: sellerId) }
        apply(results.1, dataset: .stock, sellerId: sellerId) { applyStock($0.items, sellerId: sellerId) }
        apply(results.2, dataset: .settings, sellerId: sellerId) { applySettings($0.settings, sellerId: sellerId) }
        try? context.save()
    }

    private func fetch<R: Decodable & Sendable>(_ endpoint: Endpoint<R>) async -> Result<R, APIError> {
        do throws(APIError) {
            return .success(try await api.send(endpoint))
        } catch {
            return .failure(error)
        }
    }

    private func apply<R>(_ result: Result<R, APIError>, dataset: Dataset, sellerId: String, _ body: (R) -> Void) {
        let state = syncState(sellerId: sellerId, dataset: dataset)
        switch result {
        case .success(let value):
            body(value)
            state.status = .synced
            state.lastSyncedAt = .now
            state.errorMessage = nil
        case .failure(let error):
            state.status = .failed
            state.errorMessage = error.userMessage
            lastErrorMessage = error.userMessage
            if case .unauthorized = error { onUnauthorized?() }
        }
    }

    private func markSyncing(sellerId: String, dataset: Dataset) {
        syncState(sellerId: sellerId, dataset: dataset).status = .syncing
    }

    private func syncState(sellerId: String, dataset: Dataset) -> DatasetSyncState {
        let key = DatasetSyncState.key(sellerId: sellerId, dataset: dataset)
        let descriptor = FetchDescriptor<DatasetSyncState>(predicate: #Predicate { $0.key == key })
        if let existing = try? context.fetch(descriptor).first { return existing }
        let state = DatasetSyncState(sellerId: sellerId, dataset: dataset)
        context.insert(state)
        return state
    }

    // MARK: - Merge

    /// Ids de productos con cambios locales sin sincronizar (no se pisan, §7.4).
    private func protectedProductIds(sellerId: String) -> Set<String> {
        let products = (try? context.fetch(FetchDescriptor<CatalogProduct>(
            predicate: #Predicate { $0.sellerId == sellerId }))) ?? []
        return Set(products.filter { $0.syncState != .synced }.map(\.id))
    }

    func applyCatalog(_ remote: [CatalogProductDTO], sellerId: String) {
        let local = (try? context.fetch(FetchDescriptor<CatalogProduct>(
            predicate: #Predicate { $0.sellerId == sellerId }))) ?? []
        let protected = Set(local.filter { $0.syncState != .synced }.map(\.id))
        let byId = Dictionary(local.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        for id in SnapshotMerge.idsToDelete(localIds: local.map(\.id), remoteIds: Set(remote.map(\.id)), protectedIds: protected) {
            if let product = byId[id] { context.delete(product) }
        }
        for dto in remote where SnapshotMerge.shouldOverwrite(id: dto.id, protectedIds: protected) {
            let source = ProductSource(rawValue: dto.source) ?? .manual
            if let product = byId[dto.id] {
                product.naturaSku = dto.naturaSku
                product.name = dto.name
                product.sourceRaw = source.rawValue
                product.isSellable = dto.isSellable
                product.lastPurchasePesos = dto.lastPurchaseUnitPriceCents
                product.lastSuggestedSalePesos = dto.lastSuggestedSaleUnitPriceCents
                product.barcodes = dto.barcodes
                product.syncState = .synced
            } else {
                context.insert(CatalogProduct(
                    id: dto.id, sellerId: sellerId, naturaSku: dto.naturaSku, name: dto.name, source: source,
                    isSellable: dto.isSellable, lastPurchasePesos: dto.lastPurchaseUnitPriceCents,
                    lastSuggestedSalePesos: dto.lastSuggestedSaleUnitPriceCents, barcodes: dto.barcodes))
            }
        }
    }

    func applyStock(_ remote: [StockSummaryItemDTO], sellerId: String) {
        let local = (try? context.fetch(FetchDescriptor<StockItem>(
            predicate: #Predicate { $0.sellerId == sellerId }))) ?? []
        let protected = protectedProductIds(sellerId: sellerId)
        let byId = Dictionary(local.map { ($0.sellerProductId, $0) }, uniquingKeysWith: { first, _ in first })

        for id in SnapshotMerge.idsToDelete(localIds: local.map(\.sellerProductId),
                                            remoteIds: Set(remote.map(\.sellerProductId)), protectedIds: protected) {
            if let item = byId[id] { context.delete(item) }
        }
        for dto in remote where SnapshotMerge.shouldOverwrite(id: dto.sellerProductId, protectedIds: protected) {
            if let item = byId[dto.sellerProductId] {
                item.naturaSku = dto.naturaSku
                item.name = dto.name
                item.isSellable = dto.isSellable
                item.theoreticalQuantity = dto.theoreticalQuantity
                item.operationalQuantity = dto.operationalQuantity
                item.lastReconciledAt = dto.lastReconciledAt
            } else {
                context.insert(StockItem(
                    sellerProductId: dto.sellerProductId, sellerId: sellerId, naturaSku: dto.naturaSku,
                    name: dto.name, isSellable: dto.isSellable, theoreticalQuantity: dto.theoreticalQuantity,
                    operationalQuantity: dto.operationalQuantity, lastReconciledAt: dto.lastReconciledAt))
            }
        }
    }

    func applySettings(_ remote: SellerSettingsDTO, sellerId: String) {
        let strategy = IssueStrategy(rawValue: remote.inventoryIssueStrategy) ?? .fifo
        let descriptor = FetchDescriptor<SellerSettings>(predicate: #Predicate { $0.sellerId == sellerId })
        if let existing = try? context.fetch(descriptor).first {
            existing.issueStrategy = strategy
        } else {
            context.insert(SellerSettings(sellerId: sellerId, issueStrategy: strategy))
        }
    }

    // MARK: - Ajustes (solo online)

    /// Cambia FIFO/LIFO en el backend. Devuelve un mensaje de error o nil.
    public func updateIssueStrategy(_ strategy: IssueStrategy, sellerId: String) async -> String? {
        do throws(APIError) {
            let response = try await api.send(.updateSettings(inventoryIssueStrategy: strategy.rawValue))
            applySettings(response.settings, sellerId: sellerId)
            try? context.save()
            return nil
        } catch {
            if case .unauthorized = error { onUnauthorized?() }
            return error.userMessage
        }
    }
}
