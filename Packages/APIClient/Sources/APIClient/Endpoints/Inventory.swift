import Foundation

// Espejo de inventory-routes.ts y catalog-routes.ts (escrituras).

public struct CreateReconciliationInputDTO: Codable, Sendable, Equatable {
    public let sellerProductId: String
    public let countedQuantity: Int
    public let reasonNote: String?
    /// ISO 8601
    public let reconciledAt: String

    public init(sellerProductId: String, countedQuantity: Int, reasonNote: String?, reconciledAt: String) {
        self.sellerProductId = sellerProductId
        self.countedQuantity = countedQuantity
        self.reasonNote = reasonNote
        self.reconciledAt = reconciledAt
    }
}

public struct ReconciliationDTO: Codable, Sendable, Equatable {
    public let id: String
    public let sellerProductId: String
    public let countedQuantity: Int
    public let theoreticalQuantityBefore: Int
    public let deltaApplied: Int
    public let reasonNote: String?
    public let reconciledAt: Date
}

public struct ReconciliationResponseDTO: Codable, Sendable, Equatable {
    public let reconciliation: ReconciliationDTO
}

public struct InventoryEventDTO: Codable, Sendable, Equatable {
    public let id: String
    /// "receipt" | "reconciliation" | "sale"
    public let type: String
    public let sellerProductId: String
    public let naturaSku: String
    public let productName: String
    public let quantity: Int
    public let note: String?
    public let occurredAt: Date
}

public struct InventoryActivityResponseDTO: Codable, Sendable, Equatable {
    public let events: [InventoryEventDTO]
}

public struct AddBarcodeInputDTO: Codable, Sendable, Equatable {
    public let ean: String

    public init(ean: String) {
        self.ean = ean
    }
}

public struct QuickProductInputDTO: Codable, Sendable, Equatable {
    public let naturaSku: String
    public let name: String

    public init(naturaSku: String, name: String) {
        self.naturaSku = naturaSku
        self.name = name
    }
}

public struct MasterProductLookupDTO: Codable, Sendable, Equatable {
    public struct Product: Codable, Sendable, Equatable {
        public let naturaSku: String?
        public let name: String?
    }

    public let found: Bool
    public let product: Product?
}

public extension Endpoint where Response == ReconciliationResponseDTO {
    static func createReconciliation(_ input: CreateReconciliationInputDTO) -> Self {
        Endpoint(method: .post, path: "/api/inventory/reconciliations", json: input)
    }
}

public extension Endpoint where Response == InventoryActivityResponseDTO {
    static var inventoryActivity: Self { Endpoint(path: "/api/inventory/activity") }
}

public extension Endpoint where Response == CatalogProductResponseDTO {
    static func addBarcode(sellerProductId: String, ean: String) -> Self {
        Endpoint(method: .post, path: "/api/catalog/products/\(PathEscape.segment(sellerProductId))/barcodes",
                 json: AddBarcodeInputDTO(ean: ean))
    }

    static func quickProduct(naturaSku: String, name: String) -> Self {
        Endpoint(method: .post, path: "/api/catalog/products/quick",
                 json: QuickProductInputDTO(naturaSku: naturaSku, name: name))
    }
}

public extension Endpoint where Response == MasterProductLookupDTO {
    static func masterProductLookup(sku: String) -> Self {
        Endpoint(path: "/api/catalog/master-products/lookup", query: [QueryItem("sku", sku)])
    }
}

public enum PathEscape {
    public static func segment(_ value: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}
