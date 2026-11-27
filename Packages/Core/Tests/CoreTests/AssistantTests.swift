import Foundation
import Testing
@testable import Core

@Suite("Asistente · registro, resolución y frases (U1)")
struct AssistantTests {
    let products = [VoiceCandidate(id: "p1", name: "Kaiak Clásico", code: "70983"),
                    VoiceCandidate(id: "p2", name: "Ekos Maracuyá", code: "55555")]
    let customers = [VoiceCandidate(id: "c1", name: "Ana Rojas"), VoiceCandidate(id: "c2", name: "Juan Pérez")]

    @Test func resolvesCodesNamesAndTopics() {
        func resolve(_ text: String) -> AssistantResolution {
            AssistantResolver.resolve(text, products: products, customers: customers, barcodes: ["7891033000000": "p2"])
        }
        #expect(resolve("7891033000000") == .entity(.product("p2")))
        #expect(resolve("70983") == .entity(.product("p1")))
        #expect(resolve("# 70983") == .entity(.product("p1")))
        #expect(resolve("99999") == .none)
        #expect(resolve("kaiak") == .entity(.product("p1")))
        #expect(resolve("Ana Rojas") == .entity(.customer("c1")))
        #expect(resolve("la revista") == .entity(.magazine))
        #expect(resolve("mi crédito") == .entity(.account))
        #expect(resolve("el ciclo") == .entity(.cycle))
        #expect(resolve("zzz") == .none)
    }

    @Test func availabilityDependsOnContext() {
        let none = AssistantActions.available(for: .product("p1"), context: AssistantContext(stock: 0))
        #expect(!none.map(\.id).contains(.productAddToSale))
        let full = AssistantActions.available(for: .product("p1"), context: AssistantContext(
            stock: 3, hasOpenReceivingLine: true, hasOffer: true, hasCycle: true))
        #expect(Array(full.prefix(4).map(\.id)) == [.productStock, .productAddToSale, .productOffer, .productReceive])
        #expect(full.map(\.id).contains(.productAddToDraft))
        let customer = AssistantActions.available(for: .customer("c1"), context: AssistantContext(hasPhone: false))
        #expect(!customer.map(\.id).contains(.customerWhatsApp))
        #expect(!customer.map(\.id).contains(.customerLastOrder))
    }

    @Test func phrasesPickActions() {
        let actions = AssistantActions.available(for: .product("p1"), context: AssistantContext(stock: 2))
        #expect(AssistantActions.match("¿Y cuánto queda?", in: actions)?.id == .productStock)
        #expect(AssistantActions.match("a la venta", in: actions)?.id == .productAddToSale)
        #expect(AssistantActions.match("¿quién lo encargó?", in: actions)?.id == .productWhoOrdered)
        #expect(AssistantActions.match("hola", in: actions) == nil)
    }
}
