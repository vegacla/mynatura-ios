import Testing
@testable import Core

@Suite("Voice · carro de venta")
struct VoiceCartTests {
    let products = [
        VoiceCandidate(id: "humor-m", name: "Desodorante Colonia Humor Masculino", code: "11111"),
        VoiceCandidate(id: "kaiak", name: "Desodorante Colonia Kaiak Clásico", code: "12345"),
    ]
    let customers = [VoiceCandidate(id: "ana", name: "Ana Rojas")]

    func cart(_ utterance: String) -> [VoiceCommand] {
        CommandGrammar.interpret(utterance, context: .cart)
    }

    func items(_ utterance: String) -> [VoiceProposalItem] {
        VoiceProposalBuilder.build(cart(utterance), products: products, customers: customers, referenceYear: 2026).items
    }

    @Test func cartGrammar() {
        #expect(cart("dos Kaiak a nueve noventa, para la señora Ana") == [
            .addLine(quantity: 2, product: .text("Kaiak"),
                     price: ParsedPrice(amount: Money(pesos: 9990), tokenCount: 2, isShorthand: true)),
            .setCustomer(name: "Ana"),
        ])
        #expect(cart("vende un 12345") == [.addLine(quantity: 1, product: .sku("12345"), price: nil)])
        #expect(cart("quita el Humor") == [.removeLine(.text("Humor"))])
        #expect(cart("ciclo 19") == [.unrecognized("ciclo 19")])
    }

    @Test func registeringIsNeverDoneByVoice() {
        #expect(cart("registra la venta") == [.done])
        #expect(cart("cóbrale") == [.done])
    }

    @Test func stockLimitsCapAndSkip() {
        let result = VoiceOrderApplier.apply(items("cinco del 12345, un 11111"), to: VoiceOrderState(),
                                             customers: customers, limits: ["kaiak": 3, "humor-m": 0])
        #expect(result.state.lines == [VoiceOrderState.Line(productId: "kaiak", quantity: 3)])
        #expect(result.capped == 1)
        #expect(result.outOfStock == 1)
        #expect(result.applied == 1)
        #expect(result.skipped == 1)
    }

    @Test func repeatAndPricesRespectStock() {
        let initial = VoiceOrderState(lines: [VoiceOrderState.Line(productId: "kaiak", quantity: 2, finalPesos: 12990)])
        let result = VoiceOrderApplier.apply(items("otro más, otro más"), to: initial, customers: customers,
                                             limits: ["kaiak": 3])
        #expect(result.state.lines == [VoiceOrderState.Line(productId: "kaiak", quantity: 3, finalPesos: 12990)])
        #expect(result.capped == 1)
        let priced = VoiceOrderApplier.apply(items("un 12345 a 9.990"), to: VoiceOrderState(), customers: customers,
                                             limits: ["kaiak": 5])
        #expect(priced.state.lines == [VoiceOrderState.Line(productId: "kaiak", quantity: 1, finalPesos: 9990)])
    }

    @Test func cartOnlyUsesExistingCustomers() {
        let unknown = VoiceOrderApplier.apply(items("para Pedro Pablo"), to: VoiceOrderState(), customers: customers,
                                              limits: [:], allowsNewCustomer: false)
        #expect(unknown.state.customerName == "")
        #expect(unknown.skipped == 1)
        let known = VoiceOrderApplier.apply(items("para la señora Ana"), to: VoiceOrderState(), customers: customers,
                                            limits: [:], allowsNewCustomer: false)
        #expect(known.state.customerId == "ana")
        #expect(known.state.customerName == "Ana Rojas")
    }
}
