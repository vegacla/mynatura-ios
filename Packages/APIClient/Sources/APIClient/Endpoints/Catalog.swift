import Foundation

// Espejo de backend/src/modules/catalog, inventory y settings (rutas *-routes.ts).

public struct CatalogProductDTO: Codable, Sendable, Equatable {
    public let id: String
    public let naturaSku: String
    public let name: String
    /// "manual" | "catalog" | "order_import"
    public let source: String
    public let isSellable: Bool
    public let lastPurchaseUnitPriceCents: Int
    public let lastSuggestedSaleUnitPriceCents: Int?
    public let barcodes: [String]

    public init(id: String, naturaSku: String, name: String, source: String, isSellable: Bool,
                lastPurchaseUnitPriceCents: Int, lastSuggestedSaleUnitPriceCents: Int?, barcodes: [String]) {
        self.id = id
        self.naturaSku = naturaSku
        self.name = name
        self.source = source
        self.isSellable = isSellable
        self.lastPurchaseUnitPriceCents = lastPurchaseUnitPriceCents
        self.lastSuggestedSaleUnitPriceCents = lastSuggestedSaleUnitPriceCents
        self.barcodes = barcodes
    }
}

public struct CatalogProductsResponseDTO: Codable, Sendable, Equatable {
    public let products: [CatalogProductDTO]
}

public struct CatalogProductResponseDTO: Codable, Sendable, Equatable {
    public let product: CatalogProductDTO
}

public struct StockSummaryItemDTO: Codable, Sendable, Equatable {
    public let sellerProductId: String
    public let naturaSku: String
    public let name: String
    public let isSellable: Bool
    public let theoreticalQuantity: Int
    public let operationalQuantity: Int
    public let lastReconciledAt: Date?
}

public struct StockSummaryResponseDTO: Codable, Sendable, Equatable {
    public let items: [StockSummaryItemDTO]
}

public struct SellerSettingsDTO: Codable, Sendable, Equatable {
    /// "fifo" | "lifo"
    public let inventoryIssueStrategy: String

    public init(inventoryIssueStrategy: String) {
        self.inventoryIssueStrategy = inventoryIssueStrategy
    }
}

public struct SettingsResponseDTO: Codable, Sendable, Equatable {
    public let settings: SellerSettingsDTO
}

public extension Endpoint where Response == CatalogProductsResponseDTO {
    static var catalogProducts: Self { Endpoint(path: "/api/catalog/products") }
}

public extension Endpoint where Response == StockSummaryResponseDTO {
    static var stockSummary: Self { Endpoint(path: "/api/inventory/stock-summary") }
}

public extension Endpoint where Response == SettingsResponseDTO {
    static var settings: Self { Endpoint(path: "/api/settings") }

    static func updateSettings(inventoryIssueStrategy: String) -> Self {
        Endpoint(method: .put, path: "/api/settings",
                 json: SellerSettingsDTO(inventoryIssueStrategy: inventoryIssueStrategy))
    }
}
