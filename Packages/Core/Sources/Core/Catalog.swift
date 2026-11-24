import Foundation

/// Origen de un producto del catálogo de la vendedora (`seller_products.source`).
public enum ProductSource: String, Sendable, Codable, CaseIterable {
    case manual
    case catalog
    case orderImport = "order_import"

    public var label: String {
        switch self {
        case .manual: "Manual"
        case .catalog: "Catálogo"
        case .orderImport: "Importado"
        }
    }
}

/// Estado de sincronización de una entidad local (§6).
public enum EntitySyncState: String, Sendable, Codable {
    case synced
    case pending
    case failed
}

/// Preferencia de salida de inventario (`/api/settings`).
public enum IssueStrategy: String, Sendable, Codable, CaseIterable {
    case fifo
    case lifo

    public var label: String {
        switch self {
        case .fifo: "FIFO"
        case .lifo: "LIFO"
        }
    }

    public var detail: String {
        switch self {
        case .fifo: "Sale primero el lote más antiguo."
        case .lifo: "Sale primero el lote más reciente."
        }
    }
}

/// Conjuntos de datos que se descargan del backend (§7.4).
public enum Dataset: String, Sendable, Codable, CaseIterable {
    case catalog
    case stock
    case settings
    case pricingReasons = "pricing_reasons"
    case sales
    case naturaOrders = "natura_orders"
    case customers
    case customerOrders = "customer_orders"

    public var label: String {
        switch self {
        case .catalog: "Catálogo"
        case .stock: "Stock"
        case .settings: "Ajustes"
        case .pricingReasons: "Motivos de precio"
        case .sales: "Ventas"
        case .naturaOrders: "Pedidos Natura"
        case .customers: "Clientes"
        case .customerOrders: "Pedidos de clientes"
        }
    }
}

public enum DatasetSyncStatus: String, Sendable, Codable {
    case idle
    case syncing
    case synced
    case failed
}

/// Búsqueda de productos por nombre, SKU o EAN (Vender y Productos).
public enum ProductSearch {
    public static func matches(query: String, name: String, sku: String, barcodes: [String]) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }

        let normalizedName = Normalize.customerName(name)
        let tokens = Normalize.customerName(trimmed).split(separator: " ")
        if !tokens.isEmpty, tokens.allSatisfy({ normalizedName.contains($0) }) {
            return true
        }

        let skuQuery = Normalize.naturaSku(trimmed).lowercased()
        if !skuQuery.isEmpty, Normalize.naturaSku(sku).lowercased().contains(skuQuery) {
            return true
        }

        let digits = Normalize.ean(trimmed)
        if digits.count >= 3, digits.count == trimmed.filter({ !$0.isWhitespace }).count {
            return barcodes.contains { Normalize.ean($0).contains(digits) }
        }
        return false
    }

    /// Coincidencia exacta de un código escaneado/tipeado (EAN o SKU), como `addFirstExactMatch` de la PWA.
    public static func isExactCodeMatch(code: String, sku: String, barcodes: [String]) -> Bool {
        let normalized = Normalize.scanCode(code)
        guard !normalized.isEmpty else { return false }
        if Normalize.naturaSku(sku).lowercased() == normalized.lowercased() { return true }
        return barcodes.contains { Normalize.ean($0) == normalized }
    }
}

/// Regla de merge del pull (§7.4): el snapshot remoto reemplaza lo local,
/// salvo entidades con mutaciones pendientes, que no se tocan.
public enum SnapshotMerge {
    public static func idsToDelete(localIds: [String], remoteIds: Set<String>, protectedIds: Set<String>) -> [String] {
        localIds.filter { !remoteIds.contains($0) && !protectedIds.contains($0) }
    }

    public static func shouldOverwrite(id: String, protectedIds: Set<String>) -> Bool {
        !protectedIds.contains(id)
    }
}
