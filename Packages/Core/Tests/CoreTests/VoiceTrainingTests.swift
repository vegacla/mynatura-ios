import Testing
@testable import Core

@Suite("Voice · vocabulario propio")
struct VoiceTrainingTests {
    let products = ["Desodorante Colonia Kaiak Clásico", "Jabón en Barra Ekos Castaña"]
    let codes = ["12345", "#33333"]
    let customers = ["Ana Rojas"]

    func phrases() -> [VoicePhrase] {
        VoiceTraining.phrases(productNames: products, productCodes: codes, customerNames: customers)
    }

    @Test func shortNamesDropGenericWords() {
        #expect(VoiceTraining.shortName("Desodorante Colonia Kaiak Clásico") == "Kaiak Clásico")
        #expect(VoiceTraining.shortName("Jabón en Barra Ekos Castaña") == "Ekos Castaña")
        #expect(VoiceTraining.shortName("Kaiak") == nil)
        #expect(VoiceTraining.shortName("Crema de Manos") == "Manos")
    }

    @Test func coversNamesCodesCustomersAndCommands() {
        let texts = Set(phrases().map(\.phrase))
        #expect(texts.contains("Desodorante Colonia Kaiak Clásico"))
        #expect(texts.contains("Kaiak Clásico"))
        #expect(texts.contains("Ekos Castaña"))
        #expect(texts.contains("para Ana Rojas"))
        #expect(texts.contains("¿qué me encargó Ana Rojas?"))
        #expect(texts.contains { $0.hasSuffix("del 33333") })
        #expect(texts.contains { $0.hasPrefix("llegaron") && $0.hasSuffix("del Kaiak Clásico") })
        #expect(texts.contains("otro más"))
        #expect(texts.contains("¿cuánto vendí esta semana?"))
    }

    @Test func noDuplicatesAndPositiveCounts() {
        let all = phrases()
        let keys = all.map { Normalize.customerName($0.phrase) }
        #expect(Set(keys).count == keys.count)
        #expect(all.allSatisfy { $0.count > 0 })
        // "Ekos" es línea Natura (20) y nadie la baja.
        #expect(all.first { $0.phrase == "Ekos" }?.count == 20)
    }

    @Test func versionIsStableAndOrderIndependent() {
        let shuffled = VoiceTraining.phrases(productNames: products.reversed(), productCodes: codes.reversed(),
                                             customerNames: customers)
        #expect(VoiceTraining.version(of: phrases()) == VoiceTraining.version(of: shuffled))
        #expect(VoiceTraining.version(of: phrases()).count == 16)
        let other = VoiceTraining.phrases(productNames: products + ["Humor"], productCodes: codes, customerNames: customers)
        #expect(VoiceTraining.version(of: other) != VoiceTraining.version(of: phrases()))
    }

    @Test func respectsTheCap() {
        let many = (0..<3000).map { "Producto número \($0) especial" }
        let manyCodes = (0..<3000).map { String(10_000 + $0) }
        let manyCustomers = (0..<500).map { "Cliente \($0)" }
        let capped = VoiceTraining.phrases(productNames: many, productCodes: manyCodes, customerNames: manyCustomers)
        #expect(capped.count == VoiceTraining.maximumPhrases)
    }
}
