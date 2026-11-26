import Testing
@testable import Core

@Suite("Voice · coincidencias")
struct VoiceMatcherTests {
    let products = [
        VoiceCandidate(id: "humor-m", name: "Desodorante Colonia Humor Masculino", code: "11111"),
        VoiceCandidate(id: "humor-f", name: "Desodorante Colonia Humor Femenino", code: "22222"),
        VoiceCandidate(id: "kaiak", name: "Desodorante Colonia Kaiak Clásico", code: "12345"),
        VoiceCandidate(id: "ekos", name: "Jabón en Barra Ekos Castaña", code: "33333"),
    ]

    let customers = [
        VoiceCandidate(id: "juan", name: "Juan Soto Pérez"),
        VoiceCandidate(id: "juana", name: "Juana Díaz"),
        VoiceCandidate(id: "maria", name: "María Soto"),
        VoiceCandidate(id: "ana", name: "Ana Rojas"),
    ]

    @Test func phoneticKeys() {
        #expect(VoiceText.phoneticKey("Humor") == VoiceText.phoneticKey("umor"))
        #expect(VoiceText.phoneticKey("ecos") == VoiceText.phoneticKey("Ekos"))
        #expect(VoiceText.phoneticKey("Chronos") == VoiceText.phoneticKey("cronos"))
        #expect(VoiceText.phoneticKey("vaya") == VoiceText.phoneticKey("baya"))
        #expect(VoiceText.phoneticKey("llama") == "yama")
    }

    @Test func editDistance() {
        #expect(VoiceText.editDistance("kaiak", "kayak") == 1)
        #expect(VoiceText.editDistance("", "abc") == 3)
        #expect(VoiceText.editDistance("ekos", "ekos") == 0)
    }

    @Test func codeMatchesExactly() {
        #expect(ProductMatcher.resolve(.sku("12345"), in: products) == .found("kaiak"))
        #expect(ProductMatcher.resolve(.sku("#12345"), in: products) == .found("kaiak"))
        #expect(ProductMatcher.resolve(.sku("1234"), in: products) == .notFound)
    }

    @Test func transcriptionErrorsStillMatch() {
        #expect(ProductMatcher.resolve(.text("e cos castaña"), in: products) == .found("ekos"))
        #expect(ProductMatcher.resolve(.text("kayak clasico"), in: products) == .found("kaiak"))
        #expect(ProductMatcher.resolve(.text("kaiak"), in: products) == .found("kaiak"))
    }

    @Test func nearTiesAreAmbiguous() {
        #expect(ProductMatcher.resolve(.text("desodorante umor"), in: products) == .ambiguous(["humor-m", "humor-f"]))
    }

    @Test func unknownProductIsNotFound() {
        #expect(ProductMatcher.resolve(.text("perfume xyz"), in: products) == .notFound)
    }

    @Test func aliasesCount() {
        let withAlias = [VoiceCandidate(id: "mb", name: "Mamãe e Bebê Colonia", code: "44444", aliases: ["mamá y bebé"])]
        #expect(ProductMatcher.resolve(.text("mamá y bebé"), in: withAlias) == .found("mb"))
    }

    @Test func customers() {
        #expect(CustomerMatcher.resolve(name: "juan soto", in: customers) == .found("juan"))
        #expect(CustomerMatcher.resolve(name: "la señora Ana", in: customers) == .found("ana"))
        #expect(CustomerMatcher.resolve(name: "Pedro", in: customers) == .notFound)
    }

    @Test func exactNameBeatsPartialMatches() {
        let list = [VoiceCandidate(id: "a", name: "Juan"), VoiceCandidate(id: "b", name: "Juan Soto")]
        #expect(CustomerMatcher.resolve(name: "Juan", in: list) == .found("a"))
        let twoJuans = [VoiceCandidate(id: "a", name: "Juan Soto"), VoiceCandidate(id: "b", name: "Juan Pérez")]
        #expect(CustomerMatcher.resolve(name: "Juan", in: twoJuans) == .ambiguous(["a", "b"]))
    }
}
