import Foundation

public enum InventoryEventKind: String, Sendable, Codable, CaseIterable {
    case receipt
    case reconciliation
    case sale
    /// Obsequio a terceros (precio 0): pérdida.
    case gift

    public var label: String {
        switch self {
        case .receipt: "Recepción"
        case .reconciliation: "Conciliación"
        case .sale: "Venta"
        case .gift: "Obsequio"
        }
    }
}

public struct KardexEntry: Equatable, Sendable, Identifiable {
    public let id: String
    public let occurredAt: Date
    public let kind: InventoryEventKind
    /// Con signo: recepciones +, ventas −, conciliación = delta aplicado.
    public let quantity: Int
    public let note: String?
    public let isPending: Bool

    public init(id: String, occurredAt: Date, kind: InventoryEventKind, quantity: Int, note: String?, isPending: Bool = false) {
        self.id = id
        self.occurredAt = occurredAt
        self.kind = kind
        self.quantity = quantity
        self.note = note
        self.isPending = isPending
    }
}

public struct KardexRow: Equatable, Sendable, Identifiable {
    public let entry: KardexEntry
    public let input: Int
    public let output: Int
    public let balance: Int

    public var id: String { entry.id }
}

/// Kardex con saldo corrido (§4.5): Fecha · Tipo · Nota · Entrada · Salida · Saldo.
public enum Kardex {
    /// Filas en orden cronológico ascendente.
    public static func rows(_ entries: [KardexEntry]) -> [KardexRow] {
        var balance = 0
        return entries
            .sorted { $0.occurredAt == $1.occurredAt ? $0.id < $1.id : $0.occurredAt < $1.occurredAt }
            .map { entry in
                balance += entry.quantity
                return KardexRow(entry: entry, input: max(entry.quantity, 0), output: max(-entry.quantity, 0), balance: balance)
            }
    }
}

extension StockRules {
    /// Texto "Delta esperado ±N".
    public static func deltaLabel(counted: Int, theoretical: Int) -> String {
        let delta = reconciliationDelta(counted: counted, theoretical: theoretical)
        return "Delta esperado \(delta > 0 ? "+" : "")\(delta)"
    }
}

/// Validación de EAN para asociar (backend exige ≥ 8 caracteres).
public enum BarcodeRules {
    public static let minimumLength = 8

    public static func normalized(_ value: String) -> String? {
        let ean = Normalize.ean(value)
        return ean.count >= minimumLength ? ean : nil
    }
}
