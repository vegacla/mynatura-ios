import Foundation

public enum ReceivingReviewStatus: String, Sendable, Codable {
    case draft
    case closed

    public var label: String { self == .draft ? "Borrador" : "Cerrado" }
}

public enum ReceiptOcrStatus: String, Sendable, Codable {
    case pending
    case succeeded
    case failed

    public var label: String {
        switch self {
        case .pending: "OCR pendiente"
        case .succeeded: "OCR leído"
        case .failed: "OCR falló"
        }
    }
}

extension ReceivingStatus {
    public var label: String {
        switch self {
        case .pending: "Pendiente"
        case .partial: "Parcial"
        case .complete: "Completo"
        }
    }
}

public struct ReceivingLineRef: Sendable, Equatable {
    public let id: String
    public let sku: String
    public let barcodes: [String]
    public let ordered: Int
    public let received: Int

    public init(id: String, sku: String, barcodes: [String], ordered: Int, received: Int) {
        self.id = id
        self.sku = sku
        self.barcodes = barcodes
        self.ordered = ordered
        self.received = received
    }
}

public enum ReceivingScanError: Error, Equatable, Sendable {
    case tooShort
    case notFound(code: String)

    public var message: String {
        switch self {
        case .tooShort: "El código debe tener al menos \(Normalize.minimumScanCodeLength) caracteres."
        case .notFound(let code): "El código \(code) no está en este pedido."
        }
    }
}

/// Recepción por código (§4.6, §5.5): cada lectura suma 1 a la línea cuyo SKU o EAN coincide.
public enum ReceivingScan {
    /// Devuelve la línea a incrementar. Si varias coinciden, prefiere la que aún tiene faltante.
    public static func match(code: String, lines: [ReceivingLineRef]) throws(ReceivingScanError) -> ReceivingLineRef {
        let normalized = Normalize.scanCode(code)
        guard normalized.count >= Normalize.minimumScanCodeLength else { throw .tooShort }
        let matches = lines.filter { ProductSearch.isExactCodeMatch(code: normalized, sku: $0.sku, barcodes: $0.barcodes) }
        guard let first = matches.first else { throw .notFound(code: normalized) }
        return matches.first { $0.received < $0.ordered } ?? first
    }
}

extension ReceivingRules {
    /// Nota de la conciliación creada al aplicar faltantes (§4.6).
    public static func shortageNote(orderNumber: String, units: Int) -> String {
        "Faltante confirmado en pedido \(orderNumber): \(units) unidad(es)"
    }

    /// Totales del pedido a partir de sus líneas.
    public static func totals(lines: [(ordered: Int, received: Int)]) -> (received: Int, pending: Int) {
        let received = lines.reduce(0) { $0 + min($1.received, $1.ordered) }
        let pending = lines.reduce(0) { $0 + shortage(ordered: $1.ordered, confirmed: $1.received) }
        return (received, pending)
    }

    public static func progress(received: Int, pending: Int) -> Double {
        let total = received + pending
        return total == 0 ? 0 : Double(received) / Double(total)
    }
}
