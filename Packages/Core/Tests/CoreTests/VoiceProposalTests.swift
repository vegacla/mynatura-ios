import Testing
@testable import Core

@Suite("Voice · propuestas y aplicación")
struct VoiceProposalTests {
    let products = [
        VoiceCandidate(id: "humor-m", name: "Desodorante Colonia Humor Masculino", code: "11111"),
        VoiceCandidate(id: "humor-f", name: "Desodorante Colonia Humor Femenino", code: "22222"),
        VoiceCandidate(id: "kaiak", name: "Desodorante Colonia Kaiak Clásico", code: "12345"),
    ]
    let customers = [
        VoiceCandidate(id: "juan", name: "Juan Soto Pérez"),
        VoiceCandidate(id: "ana", name: "Ana Rojas"),
    ]

    func proposal(_ utterance: String, firstId: Int = 0) -> VoiceProposal {
        VoiceProposalBuilder.build(CommandGrammar.interpret(utterance, context: .customerOrder),
                                   products: products, customers: customers, referenceYear: 2026, firstId: firstId)
    }

    @Test func buildsResolvedChips() {
        let result = proposal("Para Juan Soto, ciclo diecinueve, dos del 12345 y un desodorante Humor")
        #expect(result.items.map(\.action) == [
            .customer(spoken: "Juan Soto", match: .found("juan")),
            .cycle(202619),
            .addLine(quantity: 2, reference: .sku("12345"), price: nil, match: .found("kaiak")),
            .addLine(quantity: 1, reference: .text("desodorante Humor"), price: nil, match: .ambiguous(["humor-m", "humor-f"])),
        ])
        #expect(result.items.map(\.id) == [0, 1, 2, 3])
        #expect(proposal("dos del 12345", firstId: 7).items.first?.id == 7)
    }

    @Test func applicabilityAndChoices() {
        let ambiguous = VoiceAction.addLine(quantity: 1, reference: .text("humor"), price: nil, match: .ambiguous(["humor-m", "humor-f"]))
        #expect(!ambiguous.isApplicable)
        #expect(ambiguous.choices == ["humor-m", "humor-f"])
        let chosen = ambiguous.resolving(with: "humor-f")
        #expect(chosen.isApplicable)
        #expect(chosen == .addLine(quantity: 1, reference: .text("humor"), price: nil, match: .found("humor-f")))
        // Un cliente no encontrado es un cliente nuevo: se puede aplicar.
        #expect(VoiceAction.customer(spoken: "Pedro", match: .notFound).isApplicable)
        #expect(!VoiceAction.unrecognized("bla").isApplicable)
    }

    @Test func undoAndDone() {
        let undone = proposal("dos del 12345, deshacer")
        #expect(undone.items.isEmpty)
        #expect(!undone.undoRequested)
        #expect(proposal("deshacer").undoRequested)
        #expect(proposal("dos del 12345, listo").finishRequested)
    }

    @Test func cycleCodes() {
        #expect(VoiceProposalBuilder.cycleCode(202619, referenceYear: 2026) == 202619)
        #expect(VoiceProposalBuilder.cycleCode(19, referenceYear: 2026) == 202619)
        #expect(VoiceProposalBuilder.cycleCode(500, referenceYear: 2026) == nil)
        #expect(proposal("ciclo quinientos").items.map(\.action) == [.unrecognized("ciclo 500")])
    }

    @Test func applyToOrderState() {
        let initial = VoiceOrderState(customerName: "", cycle: 202618, note: "",
                                      lines: [VoiceOrderState.Line(productId: "humor-m", quantity: 1, finalPesos: 8990)])
        let items = proposal("Para la señora Ana, ciclo actual, dos del 12345 a nueve noventa, otro más, quita el 11111, nota: paga el viernes").items
        let result = VoiceOrderApplier.apply(items, to: initial, customers: customers)
        #expect(result.state.customerId == "ana")
        #expect(result.state.customerName == "Ana Rojas")
        #expect(result.state.cycle == 202618)
        #expect(result.state.lines == [VoiceOrderState.Line(productId: "kaiak", quantity: 3, finalPesos: 9990)])
        #expect(result.state.note == "paga el viernes")
        #expect(result.applied == 6)
        #expect(result.skipped == 0)
    }

    @Test func applySkipsWhatNeedsAChoice() {
        let items = proposal("un desodorante Humor y algo raro 99999").items
        let result = VoiceOrderApplier.apply(items, to: VoiceOrderState(), customers: customers)
        #expect(result.state.lines.isEmpty)
        #expect(result.skipped == items.count)
    }

    @Test func newCustomerAndQuantityChanges() {
        let items = proposal("para Pedro Pablo, dos del 12345, sube a cinco el 12345, otros dos").items
        let result = VoiceOrderApplier.apply(items, to: VoiceOrderState(), customers: customers)
        #expect(result.state.customerId == nil)
        #expect(result.state.customerName == "Pedro Pablo")
        #expect(result.state.lines == [VoiceOrderState.Line(productId: "kaiak", quantity: 7)])
    }

    @Test func repeatLastWithoutALineIsSkipped() {
        let result = VoiceOrderApplier.apply(proposal("otro más").items, to: VoiceOrderState(), customers: customers)
        #expect(result.applied == 0)
        #expect(result.skipped == 1)
    }

    @Test func vocabularyIsDeduplicatedAndCapped() {
        let terms = VoiceVocabulary.contextualStrings(productNames: ["Kaiak", "Crema Ekos", "crema ekos"],
                                                      customerNames: ["Ana Rojas", "  "], limit: 100)
        #expect(terms.first == "Natura")
        #expect(terms.filter { $0.lowercased() == "kaiak" }.count == 1)
        #expect(terms.contains("Ana Rojas"))
        #expect(terms.filter { Normalize.customerName($0) == "crema ekos" }.count == 1)
        #expect(VoiceVocabulary.contextualStrings(productNames: [], customerNames: [], limit: 3).count == 3)
    }
}
