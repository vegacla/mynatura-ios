import Foundation
import Testing
@testable import Core

@Suite("Costo · lotes, regalos de Natura y obsequios")
struct CostingTests {
    func day(_ month: Int, _ day: Int = 1) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: DateComponents(year: 2026, month: month, day: day))!
    }

    /// Ejemplo del plan: comprado a $3.000 (enero), 1 gratis (febrero), comprado a $3.500 (marzo); 1 unidad cada uno.
    var example: [InventoryLot] {
        [
            InventoryLot(id: "ene", productId: "p", receivedAt: day(1), quantity: 1, unitCost: Money(pesos: 3000), source: .purchased),
            InventoryLot(id: "feb", productId: "p", receivedAt: day(2), quantity: 1, unitCost: .zero, source: .free),
            InventoryLot(id: "mar", productId: "p", receivedAt: day(3), quantity: 1, unitCost: Money(pesos: 3500), source: .purchased),
        ]
    }

    // MARK: Clasificación

    @Test func classificationByUnitValue() {
        #expect(LotClassifier.classify(rawUnitValue: "$12.990") == .init(source: .purchased, unitCost: Money(pesos: 12990)))
        #expect(LotClassifier.classify(rawUnitValue: "-") == .init(source: .free, unitCost: .zero))
        #expect(LotClassifier.classify(rawUnitValue: "$0") == .init(source: .free, unitCost: .zero))
        #expect(LotClassifier.classify(rawUnitValue: "") == .init(source: .unknown, unitCost: nil))
        #expect(LotClassifier.classify(rawUnitValue: nil) == .init(source: .unknown, unitCost: nil))
        #expect(LotClassifier.classify(rawUnitValue: "consultar") == .init(source: .unknown, unitCost: nil))
        #expect(!LotClassifier.isSellableByDefault(firstSource: .free))
        #expect(LotClassifier.isSellableByDefault(firstSource: .purchased))
    }

    @Test func sampleBoughtThenFreeKeepsLastPurchaseCost() {
        let lots = [
            InventoryLot(id: "a", productId: "m", receivedAt: day(1), quantity: 5, unitCost: Money(pesos: 800), source: .purchased),
            InventoryLot(id: "b", productId: "m", receivedAt: day(2), quantity: 3, unitCost: .zero, source: .free),
        ]
        #expect(LotClassifier.lastPurchaseCost(lots) == Money(pesos: 800))
        #expect(LotClassifier.lastPurchaseCost([lots[1]]) == nil)
    }

    // MARK: Métodos

    @Test func fifoConsumesOldestAndValuesFreeAtOldestKnownPurchase() {
        let one = CostingEngine.consume(1, from: example, method: .fifo)
        #expect(one.allocations == [CostAllocation(lotId: "ene", quantity: 1, unitCost: Money(pesos: 3000), basis: .lot)])
        let two = CostingEngine.consume(2, from: example, method: .fifo)
        #expect(two.allocations.last == CostAllocation(lotId: "feb", quantity: 1, unitCost: Money(pesos: 3000), basis: .reference))
        #expect(two.knownCost == Money(pesos: 6000))
        // Con el lote de enero ya vendido, la gratis sigue valorizada con la compra más antigua (historial).
        let afterJanuary = one.lots
        let next = CostingEngine.consume(1, from: afterJanuary, method: .fifo)
        #expect(next.allocations == [CostAllocation(lotId: "feb", quantity: 1, unitCost: Money(pesos: 3000), basis: .reference)])
    }

    @Test func lifoConsumesNewestAndValuesFreeAtNewestKnownPurchase() {
        let two = CostingEngine.consume(2, from: example, method: .lifo)
        #expect(two.allocations.map(\.lotId) == ["mar", "feb"])
        #expect(two.allocations.last == CostAllocation(lotId: "feb", quantity: 1, unitCost: Money(pesos: 3500), basis: .reference))
    }

    @Test func highestPriceLeavesFreeLotLast() {
        let three = CostingEngine.consume(3, from: example, method: .highestPrice)
        #expect(three.allocations.map(\.lotId) == ["mar", "ene", "feb"])
        #expect(three.allocations.last == CostAllocation(lotId: "feb", quantity: 1, unitCost: Money(pesos: 3500), basis: .reference))
        #expect(three.knownCost == Money(pesos: 10000))
        #expect(three.lots.allSatisfy { $0.remaining == 0 })
        #expect(three.shortage == 0)
    }

    @Test func referenceCostUsesWholeHistory() {
        var depleted = example
        depleted[0].remaining = 0
        depleted[2].remaining = 0
        #expect(CostingEngine.referenceCost(history: depleted, method: .fifo) == Money(pesos: 3000))
        #expect(CostingEngine.referenceCost(history: depleted, method: .lifo) == Money(pesos: 3500))
        #expect(CostingEngine.referenceCost(history: depleted, method: .highestPrice) == Money(pesos: 3500))
    }

    @Test func shortageIsReported() {
        let result = CostingEngine.consume(5, from: example, method: .fifo)
        #expect(result.shortage == 2)
        #expect(result.allocations.reduce(0) { $0 + $1.quantity } == 3)
    }

    // MARK: Obsequios y casos especiales

    @Test func freeOnlyProductGiftedHasNoKnownCost() {
        let bag = [InventoryLot(id: "bolsa", productId: "b", receivedAt: day(1), quantity: 10, unitCost: .zero, source: .free)]
        let result = CostingEngine.consume(2, from: bag, method: .fifo)
        #expect(result.allocations == [CostAllocation(lotId: "bolsa", quantity: 2, unitCost: .zero, basis: .freeWithoutReference)])
        let line = OutflowLine(kind: .gift, productId: "b", quantity: 2, unitPrice: .zero, allocations: result.allocations)
        let report = ProfitReport.build([line])
        #expect(report.giftLoss == .zero)
        #expect(report.unitsWithoutKnownCost == 2)
    }

    @Test func zeroPriceIsAGiftNotASale() {
        #expect(OutflowRules.kind(forUnitPrice: .zero) == .gift)
        #expect(OutflowRules.kind(forUnitPrice: Money(pesos: 9990)) == .sale)
        // Un obsequio nunca registra ingreso, aunque se le pase un precio.
        #expect(OutflowLine(kind: .gift, productId: "p", quantity: 1, unitPrice: Money(pesos: 5000), allocations: []).revenue == .zero)
    }

    @Test func validation() {
        #expect(throws: OutflowError.invalidQuantity) {
            try OutflowRules.validate(quantity: 0, unitPrice: Money(pesos: 100), available: 3)
        }
        #expect(throws: OutflowError.negativePrice) {
            try OutflowRules.validate(quantity: 1, unitPrice: Money(pesos: -1), available: 3)
        }
        #expect(throws: OutflowError.insufficientStock(available: 3)) {
            try OutflowRules.validate(quantity: 4, unitPrice: Money(pesos: 100), available: 3)
        }
    }

    @Test func giftOfPaidProductIsALossAtMethodCost() {
        let result = CostingEngine.consume(1, from: example, method: .lifo)
        let gift = OutflowLine(kind: .gift, productId: "p", quantity: 1, unitPrice: .zero, allocations: result.allocations)
        let report = ProfitReport.build([gift])
        #expect(report.giftLoss == Money(pesos: 3500))
        #expect(report.profit == Money(pesos: -3500))
    }

    @Test func unknownCostIsPendingAndCanBeCompleted() {
        let lots = [InventoryLot(id: "x", productId: "u", receivedAt: day(1), quantity: 2, unitCost: nil, source: .unknown)]
        let result = CostingEngine.consume(1, from: lots, method: .fifo)
        #expect(!result.isComplete)
        #expect(result.allocations.first?.basis == .pending)
        let sale = OutflowLine(kind: .sale, productId: "u", quantity: 1, unitPrice: Money(pesos: 5000), allocations: result.allocations)
        let before = ProfitReport.build([sale])
        #expect(!before.isComplete)
        #expect(before.linesWithPendingCost == 1)

        let revalued = CostingEngine.revalue(result.allocations, completing: "x", unitCost: Money(pesos: 2000))
        let after = ProfitReport.build([OutflowLine(kind: .sale, productId: "u", quantity: 1, unitPrice: Money(pesos: 5000),
                                                    allocations: revalued)])
        #expect(after.isComplete)
        #expect(after.profit == Money(pesos: 3000))
    }

    // MARK: Reporte

    @Test func profitReportSplitsSalesCostGiftsAndReferenceUnits() {
        let fifo = CostingEngine.consume(2, from: example, method: .fifo)   // ene ($3.000) + feb (ref $3.000)
        let sale = OutflowLine(kind: .sale, productId: "p", quantity: 2, unitPrice: Money(pesos: 6990), allocations: fifo.allocations)
        let gift = CostingEngine.consume(1, from: fifo.lots, method: .fifo)  // mar ($3.500)
        let giftLine = OutflowLine(kind: .gift, productId: "p", quantity: 1, unitPrice: .zero, allocations: gift.allocations)
        let report = ProfitReport.build([sale, giftLine])
        #expect(report.revenue == Money(pesos: 13980))
        #expect(report.costOfSales == Money(pesos: 6000))
        #expect(report.grossMargin == Money(pesos: 7980))
        #expect(report.giftLoss == Money(pesos: 3500))
        #expect(report.profit == Money(pesos: 4480))
        #expect(report.unitsAtReferenceCost == 1)
        #expect(report.referenceCostAmount == Money(pesos: 3000))
        #expect(report.isComplete)
    }

    @Test func priorSalesStayOutOfProfit() {
        let fifo = CostingEngine.consume(2, from: example, method: .fifo)
        let prior = OutflowLine(kind: .priorSales, productId: "p", quantity: 2, unitPrice: Money(pesos: 5990), allocations: fifo.allocations)
        let report = ProfitReport.build([prior])
        #expect(report.revenue == .zero)
        #expect(report.profit == .zero)
        #expect(report.priorSalesEstimatedRevenue == Money(pesos: 11980))
        #expect(report.priorSalesCost == Money(pesos: 6000))
        #expect(report.priorSalesUnits == 2)
        #expect(report.unitsAtReferenceCost == 0)
    }

    @Test func costingMethodLabelsAndBridge() {
        #expect(CostingMethod(.fifo) == .fifo)
        #expect(CostingMethod(.lifo) == .lifo)
        #expect(CostingMethod.highestPrice.label == "Mayor precio")
        #expect(CostingMethod(rawValue: "highestPrice") == .highestPrice)
    }
}
