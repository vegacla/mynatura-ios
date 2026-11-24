import Foundation

extension PricingRuleError {
    public var message: String {
        switch self {
        case .invalidQuantity: "La cantidad debe ser mayor a cero."
        case .negativePrice: "El precio no puede ser negativo."
        case .zeroPriceRequiresGift: "Precio cero requiere un motivo de regalo."
        case .belowSuggestedRequiresDiscount: "Bajo el sugerido requiere un motivo de descuento."
        }
    }
}

/// Error de una línea del carro antes de registrar la venta.
public enum SaleLineError: Error, Equatable, Sendable {
    case pricing(PricingRuleError)
    case notSellable
    case insufficientStock(available: Int)

    public var message: String {
        switch self {
        case .pricing(let error): error.message
        case .notSellable: "El producto no está habilitado para venta."
        case .insufficientStock(let available): "Stock insuficiente. Disponible: \(available)."
        }
    }
}

/// Reglas del carro (§4.3), espejo de create-sale.ts.
public enum CartRules {
    public static func lineTotal(quantity: Int, finalPrice: Money) -> Money {
        finalPrice * quantity
    }

    /// Cantidad dentro de 1…stock operativo (mínimo 1 aunque no haya stock, para que la validación lo marque).
    public static func clampQuantity(_ quantity: Int, available: Int) -> Int {
        min(max(quantity, 1), max(available, 1))
    }

    public static func validateLine(
        quantity: Int,
        finalPrice: Money,
        suggested: Money?,
        reason: PricingReason?,
        isSellable: Bool,
        available: Int
    ) throws(SaleLineError) {
        guard isSellable else { throw .notSellable }
        do throws(PricingRuleError) {
            try PricingRules.validate(quantity: quantity, finalPrice: finalPrice, suggested: suggested, reason: reason)
        } catch {
            throw .pricing(error)
        }
        guard quantity <= available else { throw .insufficientStock(available: max(available, 0)) }
    }

    /// Motivos que se ofrecen en el Picker, filtrados por la categoría requerida.
    public static func eligibleReasons(_ reasons: [PricingReason], finalPrice: Money, suggested: Money?) -> [PricingReason] {
        guard let category = PricingRules.requiredCategory(finalPrice: finalPrice, suggested: suggested) else { return [] }
        return reasons.filter { $0.category == category }
    }

    /// Margen = venta − costo.
    public static func margin(revenue: Money, cost: Money) -> Money {
        Money(pesos: revenue.pesos - cost.pesos)
    }
}

extension Money {
    public static func - (lhs: Money, rhs: Money) -> Money { Money(pesos: lhs.pesos - rhs.pesos) }
}
