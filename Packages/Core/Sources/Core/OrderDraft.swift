import Foundation

/// Borrador del pedido Natura del ciclo (docs/natura-order-placement.md §5.3 y §5.5, M8 etapa 2). Local, sin conexión.
public enum OrderDraftSource: String, Codable, Sendable, CaseIterable {
    /// Sugerido desde pedidos de clientes confirmados del ciclo.
    case customers
    case offer
    case restock

    public var label: String {
        switch self {
        case .customers: "Encargos"
        case .offer: "Ofertas"
        case .restock: "Reposición"
        }
    }
}

public struct OrderDraftLine: Codable, Sendable, Equatable, Identifiable {
    public var sku: String
    public var name: String
    public var quantity: Int
    public var source: OrderDraftSource
    /// Quién lo encargó: nombre → unidades (solo `customers`).
    public var customers: [String: Int]
    /// Puntos y precio de compra por unidad del ciclo (nil = desconocido).
    public var pointsPerUnit: Int?
    public var purchasePesos: Int?

    public var id: String { sku }

    public init(sku: String, name: String, quantity: Int, source: OrderDraftSource, customers: [String: Int] = [:],
                pointsPerUnit: Int? = nil, purchasePesos: Int? = nil) {
        self.sku = sku
        self.name = name
        self.quantity = quantity
        self.source = source
        self.customers = customers
        self.pointsPerUnit = pointsPerUnit
        self.purchasePesos = purchasePesos
    }

    /// "María ×2, Juan ×1"
    public var customersLabel: String {
        customers.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .map { "\($0.key) ×\($0.value)" }.joined(separator: ", ")
    }
}

/// Línea de un pedido de cliente confirmado del ciclo.
public struct DraftDemand: Sendable, Equatable {
    public let sku: String
    public let name: String
    public let customer: String
    public let quantity: Int

    public init(sku: String, name: String, customer: String, quantity: Int) {
        self.sku = sku
        self.name = name
        self.customer = customer
        self.quantity = quantity
    }
}

public enum PointsStatus: Equatable, Sendable {
    case noLimit
    case ok
    /// ≥ 90 % del tope.
    case near
    case over(by: Int)
}

public enum OrderDraftRules {
    /// Sugerido por SKU = max(0, encargos − stock libre), con quién lo encargó.
    public static func suggestions(demand: [DraftDemand], stock: [String: Int]) -> [OrderDraftLine] {
        var bySku: [String: OrderDraftLine] = [:]
        var order: [String] = []
        for item in demand where item.quantity > 0 {
            let key = Normalize.naturaSku(item.sku)
            if bySku[key] == nil {
                bySku[key] = OrderDraftLine(sku: key, name: item.name, quantity: 0, source: .customers)
                order.append(key)
            }
            bySku[key]?.quantity += item.quantity
            bySku[key]?.customers[item.customer, default: 0] += item.quantity
        }
        return order.compactMap { key in
            guard var line = bySku[key] else { return nil }
            line.quantity = max(0, line.quantity - max(stock[key] ?? 0, 0))
            return line.quantity > 0 ? line : nil
        }
    }

    /// Reemplaza las líneas de encargos por las sugerencias nuevas; conserva ofertas y reposición.
    /// Si un SKU ya estaba como oferta o reposición, se suman las unidades a esa línea y se anotan los clientes.
    public static func merge(_ lines: [OrderDraftLine], suggestions: [OrderDraftLine]) -> [OrderDraftLine] {
        var result = lines.filter { $0.source != .customers }
        for suggestion in suggestions {
            if let index = result.firstIndex(where: { $0.sku == suggestion.sku }) {
                result[index].customers = suggestion.customers
                result[index].quantity = max(result[index].quantity, suggestion.quantity)
            } else {
                result.append(suggestion)
            }
        }
        return result
    }

    /// Puntos estimados: Σ cantidad × puntos por unidad. `unknown` = líneas sin puntos conocidos (se muestra "≥").
    public static func points(_ lines: [OrderDraftLine]) -> (total: Int, unknown: Int) {
        let result = lines.reduce((0, 0)) { partial, line in
            guard line.quantity > 0 else { return partial }
            guard let points = line.pointsPerUnit else { return (partial.0, partial.1 + 1) }
            return (partial.0 + points * line.quantity, partial.1)
        }
        return (total: result.0, unknown: result.1)
    }

    public static func purchaseTotal(_ lines: [OrderDraftLine]) -> (pesos: Int, unknown: Int) {
        let result = lines.reduce((0, 0)) { partial, line in
            guard line.quantity > 0 else { return partial }
            guard let price = line.purchasePesos else { return (partial.0, partial.1 + 1) }
            return (partial.0 + price * line.quantity, partial.1)
        }
        return (pesos: result.0, unknown: result.1)
    }

    public static func status(points: Int, limit: Int?) -> PointsStatus {
        guard let limit, limit > 0 else { return .noLimit }
        if points > limit { return .over(by: points - limit) }
        if Double(points) >= Double(limit) * 0.9 { return .near }
        return .ok
    }

    /// Qué bajar primero para no pasarse: líneas propias (ofertas y reposición) con más puntos, antes que los encargos.
    public static func reduceFirst(_ lines: [OrderDraftLine], overBy: Int) -> [OrderDraftLine] {
        guard overBy > 0 else { return [] }
        let own = lines.filter { $0.source != .customers && $0.quantity > 0 && ($0.pointsPerUnit ?? 0) > 0 }
            .sorted { ($0.pointsPerUnit ?? 0) * $0.quantity > ($1.pointsPerUnit ?? 0) * $1.quantity }
        var covered = 0
        var chosen: [OrderDraftLine] = []
        for line in own where covered < overBy {
            chosen.append(line)
            covered += (line.pointsPerUnit ?? 0) * line.quantity
        }
        return chosen
    }

    /// Lista para copiar a GSP o enviar: "70983 ×2 Kaiak Clásico".
    public static func shareText(cycleCode: Int, lines: [OrderDraftLine]) -> String {
        let body = lines.filter { $0.quantity > 0 }.map { "\($0.sku) ×\($0.quantity) \($0.name)" }
        let points = points(lines)
        var text = "Pedido Natura ciclo \(cycleCode % 100) de \(cycleCode / 100)\n" + body.joined(separator: "\n")
        text += "\nPuntos estimados: \(points.unknown > 0 ? "≥ " : "")\(points.total)"
        return text
    }
}
