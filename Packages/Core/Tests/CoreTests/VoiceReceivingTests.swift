import Testing
@testable import Core

@Suite("Voice · recepción y conciliación")
struct VoiceReceivingTests {
    func receiving(_ utterance: String) -> [VoiceCommand] {
        CommandGrammar.interpret(utterance, context: .receiving)
    }

    func counting(_ utterance: String) -> [VoiceCommand] {
        CommandGrammar.interpret(utterance, context: .reconciliation)
    }

    let lines = [
        VoiceCandidate(id: "l-kaiak", name: "Desodorante Colonia Kaiak Clásico", code: "87654"),
        VoiceCandidate(id: "l-ekos", name: "Jabón en Barra Ekos Castaña", code: "33333"),
    ]

    // MARK: Gramática de recepción

    @Test func receivedQuantities() {
        #expect(receiving("llegaron cuatro del 87654") == [.receive(product: .sku("87654"), amount: .received(4))])
        #expect(receiving("87654 cuatro") == [.receive(product: .sku("87654"), amount: .received(4))])
        #expect(receiving("del Kaiak llegaron dos") == [.receive(product: .text("Kaiak"), amount: .received(2))])
        #expect(receiving("llegaron cuatro") == [.receive(product: nil, amount: .received(4))])
        #expect(receiving("no llegó el 12345") == [.receive(product: .sku("12345"), amount: .received(0))])
    }

    @Test func missingCompleteAndIncrements() {
        #expect(receiving("del Kaiak llegaron dos, falta uno") == [
            .receive(product: .text("Kaiak"), amount: .received(2)),
            .receive(product: nil, amount: .missing(1)),
        ])
        #expect(receiving("falta uno del 87654") == [.receive(product: .sku("87654"), amount: .missing(1))])
        #expect(receiving("del 87654 faltan dos") == [.receive(product: .sku("87654"), amount: .missing(2))])
        #expect(receiving("falta el Ekos") == [.receive(product: .text("Ekos"), amount: .missing(1))])
        #expect(receiving("llegó completo el Ekos") == [.receive(product: .text("Ekos"), amount: .complete)])
        #expect(receiving("Kaiak completo") == [.receive(product: .text("Kaiak"), amount: .complete)])
        #expect(receiving("otro más") == [.receive(product: nil, amount: .increment(1))])
        #expect(receiving("uno más del 87654") == [.receive(product: .sku("87654"), amount: .increment(1))])
        #expect(receiving("otros dos del 87654") == [.receive(product: .sku("87654"), amount: .increment(2))])
        #expect(receiving("llegó el Kaiak") == [.receive(product: .text("Kaiak"), amount: .increment(1))])
    }

    @Test func moreAfterANumberStaysInTheLine() {
        let segments = UtteranceSegmenter.segments(VoiceText.tokenize("uno más del 87654")).map { $0.map(\.text) }
        #expect(segments == [["uno", "mas", "del", "87654"]])
    }

    @Test func receivingSeveralLinesAndControlWords() {
        #expect(receiving("llegaron dos del 87654 y tres del 33333") == [
            .receive(product: .sku("87654"), amount: .received(2)),
            .receive(product: .sku("33333"), amount: .received(3)),
        ])
        #expect(receiving("listo") == [.done])
        #expect(receiving("deshacer") == [.undo])
        #expect(receiving("llegó") == [.unrecognized("llegó")])
    }

    // MARK: Gramática de conciliación

    @Test func physicalCounts() {
        #expect(counting("conté siete") == [.physicalCount(7)])
        #expect(counting("son doce unidades") == [.physicalCount(12)])
        #expect(counting("hay ciento veinte") == [.physicalCount(120)])
        #expect(counting("no hay ninguno") == [.physicalCount(0)])
        #expect(counting("cero") == [.physicalCount(0)])
        #expect(counting("15") == [.physicalCount(15)])
        #expect(counting("nota: dos venían rotos") == [.note("dos venían rotos")])
        #expect(counting("conté varios") == [.unrecognized("conté varios")])
    }

    // MARK: Propuestas y aplicación

    func proposal(_ utterance: String, previous: String? = nil) -> VoiceProposal {
        VoiceProposalBuilder.build(receiving(utterance), products: lines, customers: [], referenceYear: 2026,
                                   previousProductId: previous)
    }

    @Test func missingWithoutProductUsesTheLastLine() {
        #expect(proposal("del Kaiak llegaron dos, falta uno").items.map(\.action) == [
            .receive(reference: .text("Kaiak"), amount: .received(2), match: .found("l-kaiak")),
            .receive(reference: nil, amount: .missing(1), match: .found("l-kaiak")),
        ])
        #expect(proposal("otro más").items.map(\.action) == [.receive(reference: nil, amount: .increment(1), match: .notFound)])
        #expect(proposal("otro más", previous: "l-ekos").items.map(\.action)
            == [.receive(reference: nil, amount: .increment(1), match: .found("l-ekos"))])
    }

    @Test func receivingTargets() {
        func check(_ amount: ReceiveAmount, ordered: Int, received: Int, _ quantity: Int, capped: Bool) {
            let outcome = VoiceReceivingApplier.target(amount, ordered: ordered, received: received)
            #expect(outcome.quantity == quantity)
            #expect(outcome.capped == capped)
        }
        check(.received(4), ordered: 5, received: 0, 4, capped: false)
        check(.received(9), ordered: 5, received: 0, 5, capped: true)
        check(.missing(1), ordered: 5, received: 0, 4, capped: false)
        check(.complete, ordered: 5, received: 2, 5, capped: false)
        check(.increment(1), ordered: 5, received: 5, 5, capped: true)
    }

    @Test func applyReceiving() {
        let current = [
            VoiceReceivingLine(id: "l-kaiak", ordered: 5, received: 0),
            VoiceReceivingLine(id: "l-ekos", ordered: 3, received: 1),
        ]
        let items = proposal("del Kaiak llegaron cinco, falta uno, llegó completo el Ekos, algo raro").items
        let result = VoiceReceivingApplier.apply(items, to: current)
        #expect(result.lines == [
            VoiceReceivingLine(id: "l-kaiak", ordered: 5, received: 4),
            VoiceReceivingLine(id: "l-ekos", ordered: 3, received: 3),
        ])
        #expect(result.applied == 3)
        #expect(result.skipped == 1)
        #expect(result.capped == 0)
    }

    @Test func countChipsAreApplicable() {
        let built = VoiceProposalBuilder.build(counting("conté siete"), products: [], customers: [], referenceYear: 2026)
        #expect(built.items.map(\.action) == [.count(7)])
        #expect(built.items.first?.action.isApplicable == true)
    }
}
