import Foundation
import Testing
@testable import Core

@Suite("Boleta · OCR local (M4)")
struct ReceiptOcrTests {
    /// Palabras de una fila: (texto, x inicial) con ancho proporcional al largo.
    private func row(_ y: Double, _ items: [(String, Double)], confidence: Double = 0.9) -> [OcrWord] {
        items.map { text, x in
            OcrWord(text: text, minX: x, maxX: x + Double(text.count) * 0.008, minY: y, maxY: y + 0.02, confidence: confidence)
        }
    }

    private var receipt: [OcrWord] {
        row(0.10, [("Código", 0.05), ("Descripción", 0.15), ("Cant.", 0.50), ("Precio", 0.58), ("Normal", 0.64),
                   ("Precio", 0.72), ("Ciclo", 0.78), ("Precio", 0.86), ("Venta", 0.92)])
        + row(0.15, [("70983", 0.05), ("Kaiak", 0.15), ("Clásico", 0.21), ("2", 0.51), ("25.980", 0.60),
                     ("19.990", 0.74), ("39.980", 0.88)])
        // Vision suele entregar la columna de precios un poco desplazada en altura.
        + row(0.205, [("12345", 0.05), ("Bolsa", 0.15), ("regalo", 0.20), ("1", 0.51)])
        + row(0.212, [("3.990", 0.60), ("3.490", 0.74), ("3.990", 0.88)])
        + row(0.30, [("Subtotal", 0.15), ("43.970", 0.88)])
    }

    @Test func groupsWordsIntoRows() {
        let lines = ReceiptOcr.lines(from: receipt)
        #expect(lines.count == 4)
        #expect(lines[2].text == "12345 Bolsa regalo 1 3.990 3.490 3.990")
    }

    @Test func extractsRowsByColumns() {
        let rows = ReceiptOcr.extractRows(from: receipt)
        #expect(rows.count == 2)
        #expect(rows[0].naturaSku == "70983")
        #expect(rows[0].description == "Kaiak Clásico")
        #expect(rows[0].quantity == 2)
        #expect(rows[0].priceNormalPesos == 25980)
        #expect(rows[0].priceCyclePesos == 19990)
        #expect(rows[0].priceSalePesos == 39980)
        #expect(rows[1].naturaSku == "12345")
        #expect(rows[1].priceCyclePesos == 3490)
    }

    @Test func fallsBackToRawTextWithoutHeader() {
        let rows = ReceiptOcr.extractRows(rawText: "Pedido 811111100\n70983 Kaiak Clásico 2 25.980 19.990 39.980\n| 55555 Crema 1 $4.990 |")
        #expect(rows.count == 2)
        #expect(rows[0] == ReceiptOcrRow(naturaSku: "70983", description: "Kaiak Clásico", quantity: 2,
                                         priceNormalPesos: 25980, priceCyclePesos: 19990, priceSalePesos: 39980,
                                         rawText: "70983 Kaiak Clásico 2 25.980 19.990 39.980", confidence: 0.55))
        #expect(rows[1].quantity == 1)
        #expect(rows[1].priceNormalPesos == 4990)
        #expect(rows[1].priceCyclePesos == nil)
    }

    @Test func dedupesBySkuKeepingBestConfidence() {
        let words = row(0.1, [("Código", 0.05), ("Descripción", 0.15), ("Cant.", 0.5), ("Precio", 0.58), ("Normal", 0.64),
                               ("Precio", 0.72), ("Ciclo", 0.78)])
            + row(0.2, [("70983", 0.05), ("Kaiak", 0.15), ("1", 0.51), ("9.990", 0.74)], confidence: 0.5)
            + row(0.3, [("70983", 0.05), ("Kaiak", 0.15), ("1", 0.51), ("8.990", 0.74)], confidence: 0.8)
        let rows = ReceiptOcr.extractRows(from: words)
        #expect(rows.count == 1)
        #expect(rows[0].priceCyclePesos == 8990)
    }

    @Test func suggestedSalePriceRules() {
        func make(_ quantity: Int?, normal: Int?, cycle: Int?, sale: Int?) -> ReceiptOcrRow {
            ReceiptOcrRow(naturaSku: "1", description: "x", quantity: quantity, priceNormalPesos: normal,
                          priceCyclePesos: cycle, priceSalePesos: sale, rawText: "", confidence: 1)
        }
        // Total del ciclo divisible por la cantidad ⇒ precio unitario.
        #expect(ReceiptOcr.suggestedSalePrice(make(2, normal: nil, cycle: 39980, sale: nil)) == 19990)
        // Si no divide, se prueba con el de venta.
        #expect(ReceiptOcr.suggestedSalePrice(make(3, normal: nil, cycle: 10000, sale: 30000)) == 10000)
        // Si nada divide, el de ciclo tal cual.
        #expect(ReceiptOcr.suggestedSalePrice(make(3, normal: nil, cycle: 10001, sale: 10001)) == 10001)
        // Solo venta: vale con cantidad 1 y distinto del normal.
        #expect(ReceiptOcr.suggestedSalePrice(make(1, normal: 5000, cycle: nil, sale: 4500)) == 4500)
        #expect(ReceiptOcr.suggestedSalePrice(make(1, normal: 4500, cycle: nil, sale: 4500)) == nil)
        #expect(ReceiptOcr.suggestedSalePrice(make(nil, normal: nil, cycle: nil, sale: nil)) == nil)
    }

    @Test func matchesOrderLinesAndCapsQuantity() {
        let rows = [
            ReceiptOcrRow(naturaSku: "70983", description: "Kaiak", quantity: 5, priceNormalPesos: nil, priceCyclePesos: 19990,
                          priceSalePesos: nil, rawText: "", confidence: 0.9),
            ReceiptOcrRow(naturaSku: "99999", description: "Otro", quantity: 1, priceNormalPesos: nil, priceCyclePesos: 1990,
                          priceSalePesos: nil, rawText: "", confidence: 0.9),
            ReceiptOcrRow(naturaSku: "11111", description: "Sin datos", quantity: nil, priceNormalPesos: nil,
                          priceCyclePesos: nil, priceSalePesos: nil, rawText: "", confidence: 0.9),
        ]
        let lines = [ReceiptOcrOrderLine(id: "l1", naturaSku: "# 70983", quantity: 2),
                     ReceiptOcrOrderLine(id: "l2", naturaSku: "11111", quantity: 1)]
        let match = ReceiptOcr.match(rows: rows, lines: lines)
        #expect(match.proposals == [ReceiptOcrProposal(lineId: "l1", naturaSku: "# 70983", suggestedPesos: 19990,
                                                       receivedQuantity: 2, confidence: 0.9)])
        #expect(match.unmatchedSkus == ["99999"])
        #expect(match.status == .succeeded)
        #expect(ReceiptOcr.match(rows: [], lines: lines).status == .failed)
    }

    @Test func scorePrefersReceiptText() {
        #expect(ReceiptOcr.score(text: "Código Descripción Cant. Precio Ciclo 70983 19.990") >
                ReceiptOcr.score(text: "olbiC oicerP 38907"))
    }
}
