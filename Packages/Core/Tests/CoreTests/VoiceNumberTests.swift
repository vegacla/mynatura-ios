import Testing
@testable import Core

@Suite("Voice · números")
struct VoiceNumberTests {
    func number(_ phrase: String) -> ParsedNumber? {
        SpanishNumberParser.parse(VoiceText.tokenize(phrase), at: 0)
    }

    func price(_ phrase: String) -> ParsedPrice? {
        SpanishNumberParser.parsePrice(VoiceText.tokenize(phrase), at: 0)
    }

    @Test func tokenizeKeepsDigitGroupingAndSplitsPunctuation() {
        let tokens = VoiceText.tokenize("Para Juan, dos del 12.345.")
        #expect(tokens.map(\.text) == ["para", "juan", ",", "dos", "del", "12.345", "."])
        #expect(tokens[1].raw == "Juan")
        #expect(tokens[2].isSeparator)
    }

    @Test func cardinals() {
        #expect(SpanishNumberParser.value(of: "doce mil novecientos noventa") == 12990)
        #expect(SpanishNumberParser.value(of: "ciento veintitrés") == 123)
        #expect(SpanishNumberParser.value(of: "treinta y cinco") == 35)
        #expect(SpanishNumberParser.value(of: "veintiún") == 21)
        #expect(SpanishNumberParser.value(of: "mil quinientos") == 1500)
        #expect(SpanishNumberParser.value(of: "dos mil") == 2000)
        #expect(SpanishNumberParser.value(of: "un") == 1)
        #expect(SpanishNumberParser.value(of: "una") == 1)
        #expect(SpanishNumberParser.value(of: "cero") == 0)
        #expect(SpanishNumberParser.value(of: "kaiak") == nil)
    }

    @Test func cardinalStopsWhereANewNumberStarts() {
        // "dos tres" son dos números, no 23.
        #expect(number("dos tres")?.value == 2)
        #expect(number("dos tres")?.tokenCount == 1)
        // "ciento veintitrés cuarenta y cinco" → 123, luego 45.
        #expect(number("ciento veintitrés cuarenta y cinco")?.value == 123)
        #expect(number("ciento veintitrés cuarenta y cinco")?.tokenCount == 2)
        // "y" que no une decenas con unidades no es parte del número.
        #expect(number("dos y tres")?.tokenCount == 1)
    }

    @Test func digitLiterals() {
        #expect(number("12345") == ParsedNumber(value: 12345, digits: "12345", tokenCount: 1, isDigitSequence: true))
        #expect(number("12.990")?.value == 12990)
        #expect(number("$9.990")?.value == 9990)
    }

    @Test func spelledDigitsKeepLeadingZeros() {
        #expect(number("uno dos tres cuatro cinco")
            == ParsedNumber(value: 12345, digits: "12345", tokenCount: 5, isDigitSequence: true))
        #expect(number("cero siete cero nueve ocho tres")?.digits == "070983")
        // Dos dígitos sueltos no son un código.
        #expect(number("uno dos")?.isDigitSequence == false)
    }

    @Test func prices() {
        #expect(price("nueve mil novecientos noventa") == ParsedPrice(amount: Money(pesos: 9990), tokenCount: 4, isShorthand: false))
        #expect(price("diez lucas") == ParsedPrice(amount: Money(pesos: 10000), tokenCount: 2, isShorthand: false))
        #expect(price("9.990 pesos") == ParsedPrice(amount: Money(pesos: 9990), tokenCount: 2, isShorthand: false))
    }

    @Test func shorthandPricesAreFlagged() {
        #expect(price("nueve noventa") == ParsedPrice(amount: Money(pesos: 9990), tokenCount: 2, isShorthand: true))
        #expect(price("doce novecientos noventa") == ParsedPrice(amount: Money(pesos: 12990), tokenCount: 3, isShorthand: true))
    }
}
