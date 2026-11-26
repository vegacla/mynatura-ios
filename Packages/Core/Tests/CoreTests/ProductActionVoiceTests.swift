import Testing
@testable import Core

@Suite("Foto · voz en la ficha")
struct ProductActionVoiceTests {
    @Test func intents() {
        #expect(ProductActionVoice.intent(for: "conté siete") == .inventory(count: 7))
        #expect(ProductActionVoice.intent(for: "tomar inventario") == .inventory(count: nil))
        #expect(ProductActionVoice.intent(for: "agrégalo a la venta") == .addToSale)
        #expect(ProductActionVoice.intent(for: "al pedido de la clienta") == .addToCustomerOrder)
        #expect(ProductActionVoice.intent(for: "asocia el código de barras") == .linkBarcode)
        #expect(ProductActionVoice.intent(for: "recíbelo") == .receive)
        #expect(ProductActionVoice.intent(for: "ver la ficha") == .openDetail)
        #expect(ProductActionVoice.intent(for: "hola") == nil)
    }

    @Test func mapsToAvailableButtons() {
        let opportunity = ReceivingOpportunity(orderId: "o", orderNumber: "1", lineId: "l", pending: 1)
        let actions: [ProductAction] = [.takeInventory, .linkBarcode("789"), .addToCustomerOrder, .receive(opportunity), .openDetail]
        #expect(ProductActionVoice.action(for: .receive, in: actions) == .receive(opportunity))
        #expect(ProductActionVoice.action(for: .linkBarcode, in: actions) == .linkBarcode("789"))
        #expect(ProductActionVoice.action(for: .inventory(count: 3), in: actions) == .takeInventory)
        // Sin stock no hay botón de venta.
        #expect(ProductActionVoice.action(for: .addToSale, in: actions) == nil)
    }
}
