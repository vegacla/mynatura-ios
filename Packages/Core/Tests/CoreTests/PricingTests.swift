import Testing
@testable import Core

@Suite("PricingRules")
struct PricingTests {
    let gift = PricingReason(code: "gift_manual", label: "Regalo", category: .gift)
    let discount = PricingReason(code: "discount_manual", label: "Descuento", category: .discount)
    let suggested = Money(pesos: 10000)

    @Test func atSuggestedNeedsNoReason() throws {
        try PricingRules.validate(quantity: 1, finalPrice: suggested, suggested: suggested, reason: nil)
        #expect(!PricingRules.requiresReason(finalPrice: suggested, suggested: suggested))
    }

    @Test func aboveSuggestedNeedsNoReason() throws {
        try PricingRules.validate(quantity: 1, finalPrice: Money(pesos: 12000), suggested: suggested, reason: nil)
    }

    @Test func belowSuggestedRequiresDiscount() throws {
        #expect(throws: PricingRuleError.belowSuggestedRequiresDiscount) {
            try PricingRules.validate(quantity: 1, finalPrice: Money(pesos: 8000), suggested: suggested, reason: nil)
        }
        #expect(throws: PricingRuleError.belowSuggestedRequiresDiscount) {
            try PricingRules.validate(quantity: 1, finalPrice: Money(pesos: 8000), suggested: suggested, reason: gift)
        }
        try PricingRules.validate(quantity: 1, finalPrice: Money(pesos: 8000), suggested: suggested, reason: discount)
    }

    @Test func zeroPriceRequiresGift() throws {
        #expect(throws: PricingRuleError.zeroPriceRequiresGift) {
            try PricingRules.validate(quantity: 1, finalPrice: .zero, suggested: suggested, reason: discount)
        }
        #expect(throws: PricingRuleError.zeroPriceRequiresGift) {
            try PricingRules.validate(quantity: 1, finalPrice: .zero, suggested: nil, reason: nil)
        }
        try PricingRules.validate(quantity: 1, finalPrice: .zero, suggested: nil, reason: gift)
    }

    @Test func withoutSuggestedAnyPositivePriceIsValid() throws {
        try PricingRules.validate(quantity: 2, finalPrice: Money(pesos: 1), suggested: nil, reason: nil)
    }

    @Test func rejectsInvalidQuantity() {
        #expect(throws: PricingRuleError.invalidQuantity) {
            try PricingRules.validate(quantity: 0, finalPrice: suggested, suggested: suggested, reason: nil)
        }
    }
}
