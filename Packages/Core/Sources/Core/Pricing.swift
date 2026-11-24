public enum PricingReasonCategory: String, Sendable, Codable {
    case gift
    case discount
}

public struct PricingReason: Hashable, Sendable, Codable {
    public let code: String
    public let label: String
    public let category: PricingReasonCategory

    public init(code: String, label: String, category: PricingReasonCategory) {
        self.code = code
        self.label = label
        self.category = category
    }
}

public enum PricingRuleError: Error, Equatable, Sendable {
    case invalidQuantity
    case negativePrice
    case zeroPriceRequiresGift
    case belowSuggestedRequiresDiscount
}

/// Reglas de precio de venta, espejo de backend/src/modules/sales/application/create-sale.ts.
public enum PricingRules {
    /// ¿La línea necesita que el usuario elija un motivo?
    public static func requiresReason(finalPrice: Money, suggested: Money?) -> Bool {
        if finalPrice == .zero { return true }
        guard let suggested else { return false }
        return finalPrice < suggested
    }

    /// Categoría de motivo admitida para el precio indicado (nil = no se requiere motivo).
    public static func requiredCategory(finalPrice: Money, suggested: Money?) -> PricingReasonCategory? {
        if finalPrice == .zero { return .gift }
        if let suggested, finalPrice < suggested { return .discount }
        return nil
    }

    public static func validate(
        quantity: Int,
        finalPrice: Money,
        suggested: Money?,
        reason: PricingReason?
    ) throws(PricingRuleError) {
        guard quantity > 0 else { throw .invalidQuantity }
        guard finalPrice.pesos >= 0 else { throw .negativePrice }

        switch requiredCategory(finalPrice: finalPrice, suggested: suggested) {
        case .gift:
            guard reason?.category == .gift else { throw .zeroPriceRequiresGift }
        case .discount:
            guard reason?.category == .discount else { throw .belowSuggestedRequiresDiscount }
        case nil:
            break
        }
    }
}
