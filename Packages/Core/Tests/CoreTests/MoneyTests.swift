import Testing
@testable import Core

@Suite("Money")
struct MoneyTests {
    @Test(arguments: [
        (0, "$0"), (500, "$500"), (12990, "$12.990"), (1_234_567, "$1.234.567"), (-500, "-$500"),
    ])
    func formats(pesos: Int, expected: String) {
        #expect(Money(pesos: pesos).formatted == expected)
    }

    @Test func parsesNaturaAmounts() {
        #expect(Money.parse("$12.990") == Money(pesos: 12990))
        #expect(Money.parse(" 7.500 ") == Money(pesos: 7500))
        #expect(Money.parse("-") == nil)
        #expect(Money.parse("") == nil)
    }
}
