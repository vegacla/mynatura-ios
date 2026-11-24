import Testing
@testable import Core

@Suite("Receiving & Stock")
struct ReceivingAndStockTests {
    @Test func receivingStatus() {
        #expect(ReceivingStatus.derive(receivedUnits: 0, pendingUnits: 5) == .pending)
        #expect(ReceivingStatus.derive(receivedUnits: 2, pendingUnits: 3) == .partial)
        #expect(ReceivingStatus.derive(receivedUnits: 5, pendingUnits: 0) == .complete)
    }

    @Test func shortageAndSuggestedCount() {
        #expect(ReceivingRules.shortage(ordered: 5, confirmed: 3) == 2)
        #expect(ReceivingRules.shortage(ordered: 5, confirmed: 7) == 0)
        #expect(ReceivingRules.suggestedCount(operationalStock: 4, shortage: 2) == 2)
        #expect(ReceivingRules.suggestedCount(operationalStock: 1, shortage: 2) == 0)
    }

    @Test func cycleNormalization() {
        #expect(NaturaCycle.normalize(raw: 202606, referenceYear: 2020) == NaturaCycle(year: 2026, cycle: 6))
        #expect(NaturaCycle.normalize(raw: 6, referenceYear: 2026).code == 202606)
    }

    @Test func reconciliationDelta() {
        #expect(StockRules.reconciliationDelta(counted: 3, theoretical: 5) == -2)
    }

    @Test func localOperationalStock() {
        #expect(StockRules.localOperationalStock(serverOperational: 5, pendingSoldUnits: 2, pendingReconciledCount: nil) == 3)
        #expect(StockRules.localOperationalStock(serverOperational: 5, pendingSoldUnits: 1, pendingReconciledCount: 2) == 1)
    }
}
