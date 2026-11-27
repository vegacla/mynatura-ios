import Foundation
import Testing
@testable import Core

@Suite("Voz · navegación y frases no entendidas")
struct VoiceNavigationTests {
    private func ask(_ text: String) -> [VoiceCommand] { CommandGrammar.interpret(text, context: .global) }

    @Test func destinations() {
        #expect(ask("ir a recepción") == [.navigate(.receiving)])
        #expect(ask("abre la revista") == [.navigate(.magazine)])
        #expect(ask("muéstrame las ofertas") == [.navigate(.offers)])
        #expect(ask("abre ganancias") == [.navigate(.profit)])
        #expect(ask("abre el pedido del ciclo") == [.navigate(.orderDraft)])
        #expect(ask("abre el pedido de María José") == [.navigate(.customerOrder(name: "María José"))])
        #expect(ask("ve a vender") == [.navigate(.sell)])
        #expect(ask("abre mi cuenta") == [.navigate(.account)])
        // Sin verbo de navegación sigue siendo consulta.
        #expect(ask("¿cuánto crédito tengo?") == [.query(.credit)])
    }

    @Test func phraseLog() {
        let now = Date(timeIntervalSince1970: 0)
        var log = UnrecognizedPhrases.appending("hola", to: [], date: now)
        log = UnrecognizedPhrases.appending("hola", to: log, date: now)
        log = UnrecognizedPhrases.appending("  ", to: log, date: now)
        log = UnrecognizedPhrases.appending("chao", to: log, date: now)
        #expect(log.map(\.text) == ["chao", "hola"])
        let full = (0..<60).reduce([UnrecognizedPhrases.Entry]()) { UnrecognizedPhrases.appending("f\($1)", to: $0, date: now) }
        #expect(full.count == UnrecognizedPhrases.capacity)
        #expect(full.first?.text == "f59")
    }
}
