import Foundation

/// Tipos de mutación de la cola del backend (§7.1). Desde M7 no se usan: quedan para leer la cola antigua y descartarla.
/// Tipos de mutación offline (§7.1). `catalog.product.quick` es propio de la app iOS
/// (creación rápida de producto offline, §4.7) y usa `POST /api/catalog/products/quick`.
public enum MutationType: String, Sendable, Codable, CaseIterable {
    case customerCreate = "customer.create"
    case customerUpdate = "customer.update"
    case catalogProductQuick = "catalog.product.quick"
    case customerOrderCreate = "customer-order.create"
    case customerOrderUpdate = "customer-order.update"
    case catalogBarcodeAdd = "catalog.barcode.add"
    case receivingLineConfirm = "receiving.line.confirm"
    case inventoryReconciliationCreate = "inventory.reconciliation.create"
    case saleCreate = "sale.create"

    /// Orden determinista de push (§7.3): customer → customer-order → barcode → receiving → reconciliation → sale.
    public var syncRank: Int {
        switch self {
        case .customerCreate: 0
        case .customerUpdate: 1
        case .catalogProductQuick: 2
        case .customerOrderCreate: 3
        case .customerOrderUpdate: 4
        case .catalogBarcodeAdd: 5
        case .receivingLineConfirm: 6
        case .inventoryReconciliationCreate: 7
        case .saleCreate: 8
        }
    }

    public var label: String {
        switch self {
        case .customerCreate: "Cliente nuevo"
        case .customerUpdate: "Cliente editado"
        case .catalogProductQuick: "Producto nuevo"
        case .customerOrderCreate: "Pedido de cliente nuevo"
        case .customerOrderUpdate: "Pedido de cliente editado"
        case .catalogBarcodeAdd: "EAN agregado"
        case .receivingLineConfirm: "Recepción de línea"
        case .inventoryReconciliationCreate: "Conciliación"
        case .saleCreate: "Venta"
        }
    }
}

public enum MutationStatus: String, Sendable, Codable {
    case pending
    case syncing
    case failed
}

public enum SyncQueue {
    /// Ordena por tipo (§7.3) y luego FIFO por fecha de creación.
    public static func sorted<T>(_ items: [T], type: (T) -> MutationType, createdAt: (T) -> Date) -> [T] {
        items.sorted { lhs, rhs in
            let left = type(lhs).syncRank
            let right = type(rhs).syncRank
            if left != right { return left < right }
            return createdAt(lhs) < createdAt(rhs)
        }
    }

    /// Backoff exponencial: 1 s, 2 s, 4 s… tope 5 min.
    public static func backoff(retryCount: Int) -> TimeInterval {
        guard retryCount > 0 else { return 0 }
        let exponent = min(retryCount - 1, 20)
        return min(pow(2, Double(exponent)), 300)
    }
}

/// IDs creados en el dispositivo antes de sincronizar (§7.6).
public enum LocalID {
    public static let prefix = "local-"

    public static func make() -> String { prefix + UUID().uuidString.lowercased() }

    public static func isLocal(_ id: String) -> Bool { id.hasPrefix(prefix) }

    /// IDs locales mencionados en un texto (payload JSON).
    public static func references(in text: String) -> Set<String> {
        var result = Set<String>()
        var searchRange = text.startIndex..<text.endIndex
        while let range = text.range(of: prefix, range: searchRange) {
            let end = text.index(range.upperBound, offsetBy: 36, limitedBy: text.endIndex) ?? text.endIndex
            let candidate = String(text[range.lowerBound..<end])
            if candidate.count == prefix.count + 36, UUID(uuidString: String(candidate.dropFirst(prefix.count))) != nil {
                result.insert(candidate)
            }
            searchRange = range.upperBound..<text.endIndex
        }
        return result
    }

    /// Reemplaza IDs locales por los del servidor en un payload.
    public static func rewrite(_ text: String, mapping: [String: String]) -> String {
        mapping.reduce(text) { partial, pair in partial.replacingOccurrences(of: pair.key, with: pair.value) }
    }
}
