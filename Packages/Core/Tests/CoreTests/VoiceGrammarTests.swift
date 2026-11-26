import Testing
@testable import Core

@Suite("Voice · segmentos y gramática")
struct VoiceGrammarTests {
    func segments(_ utterance: String) -> [[String]] {
        UtteranceSegmenter.segments(VoiceText.tokenize(utterance)).map { $0.map(\.text) }
    }

    func order(_ utterance: String) -> [VoiceCommand] {
        CommandGrammar.interpret(utterance, context: .customerOrder)
    }

    // MARK: Segmentos

    @Test func splitsOnCommasAndOnConjunctionsThatOpenALine() {
        #expect(segments("Para Juan Soto, dos del 12345 y un desodorante Humor") == [
            ["para", "juan", "soto"], ["dos", "del", "12345"], ["un", "desodorante", "humor"],
        ])
    }

    @Test func keepsConjunctionsInsideNumbersAndNames() {
        #expect(segments("treinta y cinco del 12345") == [["treinta", "y", "cinco", "del", "12345"]])
        #expect(segments("dos jabones avena y miel") == [["dos", "jabones", "avena", "y", "miel"]])
    }

    @Test func splitsAfterALineThatAlreadyHasItsCode() {
        #expect(segments("dos del 12345 y desodorante humor") == [["dos", "del", "12345"], ["desodorante", "humor"]])
    }

    @Test func noteTakesTheRestOfTheUtterance() {
        let result = segments("nota: entregar el viernes, en la tarde")
        #expect(result.count == 1)
        #expect(result.first?.first == "nota")
    }

    // MARK: Pedido de cliente

    @Test func fullCustomerOrderUtterance() {
        #expect(order("Para Juan Soto, dos del 12345 y un desodorante Humor") == [
            .setCustomer(name: "Juan Soto"),
            .addLine(quantity: 2, product: .sku("12345"), price: nil),
            .addLine(quantity: 1, product: .text("desodorante Humor"), price: nil),
        ])
    }

    @Test func customerAndCycleWithoutPauses() {
        #expect(order("Para Juan Soto dos del 12345") == [
            .setCustomer(name: "Juan Soto"),
            .addLine(quantity: 2, product: .sku("12345"), price: nil),
        ])
        #expect(order("Para Juan Soto, ciclo actual: dos 12345") == [
            .setCustomer(name: "Juan Soto"),
            .setCycle(.current),
            .addLine(quantity: 2, product: .sku("12345"), price: nil),
        ])
        #expect(order("ciclo 202619") == [.setCycle(.number(202619))])
        #expect(order("ciclo diecinueve") == [.setCycle(.number(19))])
    }

    @Test func customerHonorificsAreDropped() {
        #expect(order("para la señora Ana") == [.setCustomer(name: "Ana")])
        #expect(order("pedido de don Pedro Rojas") == [.setCustomer(name: "Pedro Rojas")])
        #expect(order("para") == [.unrecognized("para")])
    }

    @Test func codesInEveryDictationStyle() {
        let expected = VoiceCommand.addLine(quantity: 2, product: .sku("12345"), price: nil)
        #expect(order("dos del 12345") == [expected])
        #expect(order("dos 12345") == [expected])
        #expect(order("dos del uno dos tres cuatro cinco") == [expected])
        #expect(order("dos ciento veintitrés cuarenta y cinco") == [expected])
        #expect(order("agrega dos del código 12345") == [expected])
        #expect(order("12345 dos") == [expected])
        #expect(order("el 12345") == [.addLine(quantity: 1, product: .sku("12345"), price: nil)])
    }

    @Test func quantitiesAndProductNames() {
        #expect(order("dos Kaiak clásico") == [.addLine(quantity: 2, product: .text("Kaiak clásico"), price: nil)])
        #expect(order("Kaiak clásico dos") == [.addLine(quantity: 2, product: .text("Kaiak clásico"), price: nil)])
        #expect(order("una docena de jabones Ekos") == [.addLine(quantity: 12, product: .text("jabones Ekos"), price: nil)])
        #expect(order("media docena de jabones") == [.addLine(quantity: 6, product: .text("jabones"), price: nil)])
        // Un número > 99 que no es código es parte del nombre.
        #expect(order("un Kaiak 100 ml") == [.addLine(quantity: 1, product: .text("Kaiak 100 ml"), price: nil)])
    }

    @Test func linePrices() {
        #expect(order("dos Kaiak clásico a nueve noventa") == [
            .addLine(quantity: 2, product: .text("Kaiak clásico"),
                     price: ParsedPrice(amount: Money(pesos: 9990), tokenCount: 2, isShorthand: true)),
        ])
        #expect(order("un 12345 a 12.990") == [
            .addLine(quantity: 1, product: .sku("12345"),
                     price: ParsedPrice(amount: Money(pesos: 12990), tokenCount: 1, isShorthand: false)),
        ])
    }

    @Test func editingCommands() {
        #expect(order("quita el Humor") == [.removeLine(.text("Humor"))])
        #expect(order("saca el 12345") == [.removeLine(.sku("12345"))])
        #expect(order("sube a tres el Ekos") == [.setQuantity(product: .text("Ekos"), quantity: 3)])
        #expect(order("cambia el 12345 a cuatro") == [.setQuantity(product: .sku("12345"), quantity: 4)])
        #expect(order("deja dos del 12345") == [.setQuantity(product: .sku("12345"), quantity: 2)])
        #expect(order("otro más") == [.repeatLast(quantity: 1)])
        #expect(order("otros dos") == [.repeatLast(quantity: 2)])
        #expect(order("dos más") == [.repeatLast(quantity: 2)])
        #expect(order("otro Kaiak") == [.addLine(quantity: 1, product: .text("Kaiak"), price: nil)])
    }

    @Test func notesUndoAndDone() {
        #expect(order("nota: entregar el viernes, en la tarde") == [.note("entregar el viernes, en la tarde")])
        #expect(order("anota que paga en efectivo") == [.note("paga en efectivo")])
        #expect(order("deshacer") == [.undo])
        #expect(order("borra eso") == [.undo])
        #expect(order("listo") == [.done])
        #expect(order("eso es todo") == [.done])
    }

    @Test func otherContextsAreNotInterpretedYet() {
        #expect(CommandGrammar.interpret("dos Kaiak", context: .cart) == [.unrecognized("dos Kaiak")])
    }
}
