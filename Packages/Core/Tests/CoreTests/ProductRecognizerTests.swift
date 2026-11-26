import Testing
@testable import Core

@Suite("Foto · reconocimiento y acciones")
struct ProductRecognizerTests {
    let catalog = [
        RecognizableProduct(id: "kaiak", name: "Desodorante Colonia Kaiak Clásico", sku: "12345", barcodes: ["7908132297387"]),
        RecognizableProduct(id: "humor-m", name: "Desodorante Colonia Humor Masculino", sku: "11111", barcodes: []),
        RecognizableProduct(id: "humor-f", name: "Desodorante Colonia Humor Femenino", sku: "22222", barcodes: []),
        RecognizableProduct(id: "ekos", name: "Jabón en Barra Ekos Castaña", sku: "33333", barcodes: []),
    ]

    @Test func explicitNaturaCodes() {
        #expect(ProductRecognizer.naturaCodes(in: ["KAIAK (12345)", "Cód. 33333", "Código: 1234567", "Ref 99999"])
            == ["12345", "33333", "1234567", "99999"])
        // EAN, precios y números cortos no son códigos Natura explícitos.
        #expect(ProductRecognizer.naturaCodes(in: ["7908132297387", "$12.990", "(123)", "100 ml"]).isEmpty)
    }

    @Test func looseNumbersSkipPricesAndEans() {
        #expect(ProductRecognizer.looseNumbers(in: ["lote 54321", "$12990", "12.990", "7908132297387", "#22222."]) == ["54321", "22222"])
    }

    @Test func barcodeWins() {
        let result = ProductRecognizer.recognize(barcodes: ["7908132297387"], textLines: [], catalog: catalog)
        #expect(result.match == .found("kaiak"))
        #expect(result.candidates.first?.reasons == [.barcode("7908132297387")])
        #expect(result.unknownBarcodes.isEmpty)
    }

    @Test func naturaCodeFromText() {
        let result = ProductRecognizer.recognize(barcodes: [], textLines: ["EKOS", "jabón castaña (33333)"], catalog: catalog)
        #expect(result.match == .found("ekos"))
        #expect(result.candidates.first?.reasons.contains(.naturaCode("33333")) == true)
    }

    @Test func nameOnlyAndAmbiguity() {
        let kaiak = ProductRecognizer.recognize(barcodes: [], textLines: ["NATURA", "KAIAK", "desodorante colonia clásico"],
                                                catalog: catalog)
        #expect(kaiak.match == .found("kaiak"))
        let humor = ProductRecognizer.recognize(barcodes: [], textLines: ["HUMOR", "desodorante colonia"], catalog: catalog)
        #expect(humor.match == .ambiguous(["humor-m", "humor-f"]))
    }

    @Test func genericWordsAloneDoNotMatch() {
        let result = ProductRecognizer.recognize(barcodes: [], textLines: ["desodorante colonia 100 ml"], catalog: catalog)
        #expect(result.match == .notFound)
    }

    @Test func unknownBarcodeIsOfferedForLinking() {
        let result = ProductRecognizer.recognize(barcodes: ["7891111111111"], textLines: ["Ekos castaña"], catalog: catalog)
        #expect(result.match == .found("ekos"))
        #expect(result.unknownBarcodes == ["7891111111111"])
    }

    @Test func notFoundKeepsWhatWasRead() {
        let result = ProductRecognizer.recognize(barcodes: [], textLines: ["Tododia Algodón", "Cód. 76543"], catalog: catalog)
        #expect(result.match == .notFound)
        #expect(result.readCodes == ["76543"])
        #expect(result.labelName == "Tododia Algodón")
        #expect(ProductActions.whenNotFound(result) == [.createProduct(sku: "76543", name: "Tododia Algodón")])
    }

    @Test func agreeingSignalsAddConfidence() {
        let both = ProductRecognizer.recognize(barcodes: ["7908132297387"], textLines: ["Kaiak (12345)"], catalog: catalog)
        #expect(both.candidates.first?.score == 1)
        let codeAndName = ProductRecognizer.recognize(barcodes: [], textLines: ["Kaiak clásico (12345)"], catalog: catalog)
        #expect((codeAndName.candidates.first?.score ?? 0) > 0.97)
    }

    @Test func availableActions() {
        let opportunity = ReceivingOpportunity(orderId: "o1", orderNumber: "123456", lineId: "l1", pending: 2)
        let full = ProductActions.available(for: ProductActionContext(
            isSellable: true, available: 3, unknownBarcodes: ["7891111111111"], receiving: [opportunity]))
        #expect(full == [.takeInventory, .linkBarcode("7891111111111"), .addToSale, .addToCustomerOrder,
                         .receive(opportunity), .openDetail])
        let minimal = ProductActions.available(for: ProductActionContext(
            isSellable: true, available: 0, unknownBarcodes: [],
            receiving: [ReceivingOpportunity(orderId: "o1", orderNumber: "1", lineId: "l1", pending: 0)]))
        #expect(minimal == [.takeInventory, .addToCustomerOrder, .openDetail])
        #expect(ProductAction.receive(opportunity).id == "receive-l1")
    }
}
