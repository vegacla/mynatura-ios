import Foundation

public enum CustomerOrderStatus: String, Sendable, Codable, CaseIterable {
    case draft
    case confirmed
    case fulfilled
    case cancelled

    public var label: String {
        switch self {
        case .draft: "Borrador"
        case .confirmed: "Confirmado"
        case .fulfilled: "Cumplido"
        case .cancelled: "Cancelado"
        }
    }
}

/// Ciclo Natura en formato AAAACC (p. ej. 202606).
public enum CycleCode {
    public static func parse(_ text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count == 6, trimmed.allSatisfy(\.isASCIIDigit), let value = Int(trimmed) else { return nil }
        let year = value / 100
        let cycle = value % 100
        guard (2000...2099).contains(year), (1...99).contains(cycle) else { return nil }
        return value
    }

    public static func label(_ code: Int) -> String {
        let cycle = NaturaCycle.normalize(raw: code, referenceYear: 0)
        return "Ciclo \(cycle.cycle) · \(cycle.year)"
    }
}

public enum CustomerRules {
    /// Coincidencias para autocompletar por nombre normalizado (§4.7).
    public static func suggestions<T>(_ customers: [T], name: (T) -> String, query: String, limit: Int = 5) -> [T] {
        let normalized = Normalize.customerName(query)
        guard !normalized.isEmpty else { return [] }
        return Array(customers.filter { Normalize.customerName(name($0)).contains(normalized) }.prefix(limit))
    }

    /// Cliente existente con exactamente el mismo nombre normalizado.
    public static func exactMatch<T>(_ customers: [T], name: (T) -> String, query: String) -> T? {
        let normalized = Normalize.customerName(query)
        guard !normalized.isEmpty else { return nil }
        return customers.first { Normalize.customerName(name($0)) == normalized }
    }

    public static func isValidName(_ name: String) -> Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// Reportes de margen (etapa 10).
public struct MarginSummary: Equatable, Sendable {
    public var revenue: Money
    public var cost: Money
    public var units: Int
    public var salesCount: Int

    public init(revenue: Money = .zero, cost: Money = .zero, units: Int = 0, salesCount: Int = 0) {
        self.revenue = revenue
        self.cost = cost
        self.units = units
        self.salesCount = salesCount
    }

    public var margin: Money { revenue - cost }

    /// Margen sobre venta (0…1), nil si no hubo ventas.
    public var marginRate: Double? {
        revenue.pesos == 0 ? nil : Double(margin.pesos) / Double(revenue.pesos)
    }
}
