import Foundation
import Testing
@testable import Core

@Suite("Pedido Natura · borrador y revista (M8)")
struct OrderDraftTests {
    @Test func magazineURLs() {
        #expect(NaturaMagazine.viewerURL(cycleCode: 202619, customerCode: "123")?.absoluteString
            == "https://cl.natura.digital-catalogue.com/consultoria/cl/2026/19/revista/ciclo-19/view/index.html?id_consultora=123&utm_term=web")
        #expect(NaturaMagazine.viewerURL(cycleCode: 202701, customerCode: "")?.absoluteString
            == "https://cl.natura.digital-catalogue.com/consultoria/cl/2027/01/revista/ciclo-01/view/index.html?utm_term=web")
        #expect(NaturaMagazine.pdfURL(cycleCode: 202619)?.absoluteString.hasSuffix("/ciclo-19/view/common/data/catalogue.pdf") == true)
        #expect(NaturaMagazine.viewerURL(cycleCode: 19, customerCode: "1") == nil)
    }

    @Test func suggestionsSubtractStockAndKeepCustomers() {
        let demand = [
            DraftDemand(sku: "70983", name: "Kaiak", customer: "María", quantity: 2),
            DraftDemand(sku: "# 70983", name: "Kaiak", customer: "Juan", quantity: 1),
            DraftDemand(sku: "55555", name: "Crema", customer: "Juan", quantity: 1),
        ]
        let lines = OrderDraftRules.suggestions(demand: demand, stock: ["70983": 1, "55555": 3])
        #expect(lines.count == 1)
        #expect(lines[0].quantity == 2)
        #expect(lines[0].customersLabel == "María ×2, Juan ×1")
    }

    @Test func mergeKeepsOwnLines() {
        let existing = [OrderDraftLine(sku: "1", name: "Oferta", quantity: 1, source: .offer),
                        OrderDraftLine(sku: "2", name: "Viejo encargo", quantity: 3, source: .customers)]
        let merged = OrderDraftRules.merge(existing, suggestions: [
            OrderDraftLine(sku: "1", name: "Oferta", quantity: 2, source: .customers, customers: ["Ana": 2]),
            OrderDraftLine(sku: "3", name: "Nuevo", quantity: 1, source: .customers, customers: ["Ana": 1]),
        ])
        #expect(merged.map(\.sku) == ["1", "3"])
        #expect(merged[0].quantity == 2)
        #expect(merged[0].source == .offer)
        #expect(merged[0].customers == ["Ana": 2])
    }

    @Test func pointsCapAndWhatToReduce() {
        let lines = [
            OrderDraftLine(sku: "1", name: "A", quantity: 2, source: .customers, pointsPerUnit: 40),
            OrderDraftLine(sku: "2", name: "B", quantity: 1, source: .offer, pointsPerUnit: 30),
            OrderDraftLine(sku: "3", name: "C", quantity: 3, source: .restock, pointsPerUnit: 10),
            OrderDraftLine(sku: "4", name: "D", quantity: 1, source: .restock),
        ]
        let points = OrderDraftRules.points(lines)
        #expect(points.total == 140)
        #expect(points.unknown == 1)
        #expect(OrderDraftRules.status(points: 140, limit: nil) == .noLimit)
        #expect(OrderDraftRules.status(points: 140, limit: 200) == .ok)
        #expect(OrderDraftRules.status(points: 185, limit: 200) == .near)
        #expect(OrderDraftRules.status(points: 140, limit: 100) == .over(by: 40))
        #expect(Set(OrderDraftRules.reduceFirst(lines, overBy: 40).map(\.sku)) == ["2", "3"])
        #expect(OrderDraftRules.shareText(cycleCode: 202619, lines: lines).hasPrefix("Pedido Natura ciclo 19 de 2026\n1 ×2 A"))
    }
}
