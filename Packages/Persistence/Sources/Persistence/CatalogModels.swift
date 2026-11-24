import Core
import Foundation
import SwiftData

/// Producto del catálogo restringido de la vendedora (`sellerProduct`), espejo de `GET /api/catalog/products`.
@Model
public final class CatalogProduct {
    /// sellerProductId
    @Attribute(.unique) public var id: String
    public var sellerId: String
    public var naturaSku: String
    public var name: String
    public var sourceRaw: String
    public var isSellable: Bool
    public var lastPurchasePesos: Int
    public var lastSuggestedSalePesos: Int?
    public var barcodes: [String]
    public var syncStateRaw: String

    public init(id: String, sellerId: String, naturaSku: String, name: String, source: ProductSource,
                isSellable: Bool, lastPurchasePesos: Int, lastSuggestedSalePesos: Int?, barcodes: [String],
                syncState: EntitySyncState = .synced) {
        self.id = id
        self.sellerId = sellerId
        self.naturaSku = naturaSku
        self.name = name
        self.sourceRaw = source.rawValue
        self.isSellable = isSellable
        self.lastPurchasePesos = lastPurchasePesos
        self.lastSuggestedSalePesos = lastSuggestedSalePesos
        self.barcodes = barcodes
        self.syncStateRaw = syncState.rawValue
    }

    public var source: ProductSource { ProductSource(rawValue: sourceRaw) ?? .manual }

    public var syncState: EntitySyncState {
        get { EntitySyncState(rawValue: syncStateRaw) ?? .synced }
        set { syncStateRaw = newValue.rawValue }
    }

    public var lastPurchase: Money { Money(pesos: lastPurchasePesos) }
    public var lastSuggestedSale: Money? { lastSuggestedSalePesos.map(Money.init(pesos:)) }
}

/// Stock por producto, espejo de `GET /api/inventory/stock-summary`.
@Model
public final class StockItem {
    @Attribute(.unique) public var sellerProductId: String
    public var sellerId: String
    public var naturaSku: String
    public var name: String
    public var isSellable: Bool
    public var theoreticalQuantity: Int
    public var operationalQuantity: Int
    public var lastReconciledAt: Date?

    public init(sellerProductId: String, sellerId: String, naturaSku: String, name: String, isSellable: Bool,
                theoreticalQuantity: Int, operationalQuantity: Int, lastReconciledAt: Date?) {
        self.sellerProductId = sellerProductId
        self.sellerId = sellerId
        self.naturaSku = naturaSku
        self.name = name
        self.isSellable = isSellable
        self.theoreticalQuantity = theoreticalQuantity
        self.operationalQuantity = operationalQuantity
        self.lastReconciledAt = lastReconciledAt
    }
}

/// Preferencias de la vendedora (`GET /api/settings`).
@Model
public final class SellerSettings {
    @Attribute(.unique) public var sellerId: String
    public var issueStrategyRaw: String

    public init(sellerId: String, issueStrategy: IssueStrategy) {
        self.sellerId = sellerId
        self.issueStrategyRaw = issueStrategy.rawValue
    }

    public var issueStrategy: IssueStrategy {
        get { IssueStrategy(rawValue: issueStrategyRaw) ?? .fifo }
        set { issueStrategyRaw = newValue.rawValue }
    }
}

/// Estado de la última descarga de cada dataset (`sync_metadata` de la PWA).
@Model
public final class DatasetSyncState {
    /// "\(sellerId)|\(dataset)"
    @Attribute(.unique) public var key: String
    public var sellerId: String
    public var datasetRaw: String
    public var statusRaw: String
    public var lastSyncedAt: Date?
    public var errorMessage: String?

    public init(sellerId: String, dataset: Dataset) {
        self.key = Self.key(sellerId: sellerId, dataset: dataset)
        self.sellerId = sellerId
        self.datasetRaw = dataset.rawValue
        self.statusRaw = DatasetSyncStatus.idle.rawValue
    }

    public static func key(sellerId: String, dataset: Dataset) -> String { "\(sellerId)|\(dataset.rawValue)" }

    public var dataset: Dataset? { Dataset(rawValue: datasetRaw) }

    public var status: DatasetSyncStatus {
        get { DatasetSyncStatus(rawValue: statusRaw) ?? .idle }
        set { statusRaw = newValue.rawValue }
    }
}
