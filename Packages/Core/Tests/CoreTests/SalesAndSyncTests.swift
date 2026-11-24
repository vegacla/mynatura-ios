import Foundation
import Testing
@testable import Core

@Suite("Cart & Sync rules")
struct SalesAndSyncTests {
    let gift = PricingReason(code: "gift_manual", label: "Regalo", category: .gift)
    let discount = PricingReason(code: "discount_manual", label: "Descuento", category: .discount)

    @Test func cartLineValidation() throws {
        try CartRules.validateLine(quantity: 2, finalPrice: Money(pesos: 1000), suggested: Money(pesos: 1000),
                                   reason: nil, isSellable: true, available: 2)
        #expect(throws: SaleLineError.insufficientStock(available: 1)) {
            try CartRules.validateLine(quantity: 2, finalPrice: Money(pesos: 1000), suggested: nil,
                                       reason: nil, isSellable: true, available: 1)
        }
        #expect(throws: SaleLineError.notSellable) {
            try CartRules.validateLine(quantity: 1, finalPrice: Money(pesos: 1000), suggested: nil,
                                       reason: nil, isSellable: false, available: 5)
        }
        #expect(throws: SaleLineError.pricing(.zeroPriceRequiresGift)) {
            try CartRules.validateLine(quantity: 1, finalPrice: .zero, suggested: nil,
                                       reason: discount, isSellable: true, available: 5)
        }
    }

    @Test func eligibleReasonsFilterByCategory() {
        let reasons = [gift, discount]
        #expect(CartRules.eligibleReasons(reasons, finalPrice: .zero, suggested: Money(pesos: 10)) == [gift])
        #expect(CartRules.eligibleReasons(reasons, finalPrice: Money(pesos: 5), suggested: Money(pesos: 10)) == [discount])
        #expect(CartRules.eligibleReasons(reasons, finalPrice: Money(pesos: 10), suggested: Money(pesos: 10)).isEmpty)
    }

    @Test func clampAndTotals() {
        #expect(CartRules.clampQuantity(5, available: 3) == 3)
        #expect(CartRules.clampQuantity(0, available: 3) == 1)
        #expect(CartRules.lineTotal(quantity: 3, finalPrice: Money(pesos: 990)) == Money(pesos: 2970))
        #expect(CartRules.margin(revenue: Money(pesos: 1000), cost: Money(pesos: 600)) == Money(pesos: 400))
    }

    @Test func queueOrderIsByTypeThenFIFO() {
        struct Item { let type: MutationType; let at: Double }
        let items = [
            Item(type: .saleCreate, at: 1), Item(type: .customerCreate, at: 5),
            Item(type: .inventoryReconciliationCreate, at: 0), Item(type: .saleCreate, at: 0),
            Item(type: .customerOrderCreate, at: 2), Item(type: .catalogBarcodeAdd, at: 3),
        ]
        let sorted = SyncQueue.sorted(items, type: \.type, createdAt: { Date(timeIntervalSince1970: $0.at) })
        #expect(sorted.map(\.type) == [.customerCreate, .customerOrderCreate, .catalogBarcodeAdd,
                                         .inventoryReconciliationCreate, .saleCreate, .saleCreate])
        #expect(sorted.suffix(2).map(\.at) == [0, 1])
    }

    @Test func backoff() {
        #expect(SyncQueue.backoff(retryCount: 0) == 0)
        #expect(SyncQueue.backoff(retryCount: 1) == 1)
        #expect(SyncQueue.backoff(retryCount: 3) == 4)
        #expect(SyncQueue.backoff(retryCount: 30) == 300)
    }

    @Test func localIdReferencesAndRewrite() {
        let a = LocalID.make()
        let b = LocalID.make()
        #expect(LocalID.isLocal(a))
        let json = #"{"customerId":"\#(a)","lines":[{"sellerProductId":"\#(b)"},{"sellerProductId":"p-1"}]}"#
        #expect(LocalID.references(in: json) == [a, b])
        let rewritten = LocalID.rewrite(json, mapping: [a: "c-9"])
        #expect(rewritten.contains("c-9"))
        #expect(LocalID.references(in: rewritten) == [b])
        #expect(LocalID.references(in: "local-xyz") == [])
    }

    @Test func indicator() {
        #expect(SyncIndicator.derive(isOnline: false, isSyncing: true, pending: 2, failed: 1) == .offline(pending: 2))
        #expect(SyncIndicator.derive(isOnline: true, isSyncing: true, pending: 2, failed: 1) == .syncing)
        #expect(SyncIndicator.derive(isOnline: true, isSyncing: false, pending: 2, failed: 1) == .failed(1))
        #expect(SyncIndicator.derive(isOnline: true, isSyncing: false, pending: 2, failed: 0) == .pending(2))
        #expect(SyncIndicator.derive(isOnline: true, isSyncing: false, pending: 0, failed: 0) == .online)
        #expect(SyncIndicator.online.label == "En línea")
    }
}

@Suite("Inventory, receiving & customers")
struct InventoryReceivingCustomerTests {
    @Test func kardexRunningBalance() {
        let t = { (s: Double) in Date(timeIntervalSince1970: s) }
        let rows = Kardex.rows([
            KardexEntry(id: "s", occurredAt: t(3), kind: .sale, quantity: -2, note: nil),
            KardexEntry(id: "r", occurredAt: t(1), kind: .receipt, quantity: 5, note: "Pedido 1"),
            KardexEntry(id: "c", occurredAt: t(4), kind: .reconciliation, quantity: -1, note: "Conteo"),
        ])
        #expect(rows.map(\.balance) == [5, 3, 2])
        #expect(rows[1].output == 2 && rows[1].input == 0)
        #expect(rows[0].input == 5)
    }

    @Test func deltaLabelAndBarcode() {
        #expect(StockRules.deltaLabel(counted: 7, theoretical: 5) == "Delta esperado +2")
        #expect(StockRules.deltaLabel(counted: 3, theoretical: 5) == "Delta esperado -2")
        #expect(BarcodeRules.normalized("7908-1322") == "79081322")
        #expect(BarcodeRules.normalized("1234567") == nil)
    }

    @Test func receivingScanMatchesSkuOrEanPreferringPending() throws {
        let lines = [
            ReceivingLineRef(id: "a", sku: "70983", barcodes: ["7908132297387"], ordered: 1, received: 1),
            ReceivingLineRef(id: "b", sku: "70983", barcodes: [], ordered: 2, received: 0),
            ReceivingLineRef(id: "c", sku: "11111", barcodes: [], ordered: 1, received: 0),
        ]
        #expect(try ReceivingScan.match(code: "#70983", lines: lines).id == "b")
        #expect(try ReceivingScan.match(code: "7908132297387", lines: lines).id == "a")
        #expect(throws: ReceivingScanError.tooShort) { try ReceivingScan.match(code: "123", lines: lines) }
        #expect(throws: ReceivingScanError.notFound(code: "99999")) { try ReceivingScan.match(code: "99999", lines: lines) }
    }

    @Test func receivingTotalsAndNote() {
        let totals = ReceivingRules.totals(lines: [(ordered: 3, received: 1), (ordered: 2, received: 5)])
        #expect(totals.received == 3 && totals.pending == 2)
        #expect(ReceivingRules.progress(received: 3, pending: 1) == 0.75)
        #expect(ReceivingRules.shortageNote(orderNumber: "123", units: 2) == "Faltante confirmado en pedido 123: 2 unidad(es)")
    }

    @Test func cycleCode() {
        #expect(CycleCode.parse("202606") == 202606)
        #expect(CycleCode.parse("2026") == nil)
        #expect(CycleCode.parse("202600") == nil)
        #expect(CycleCode.parse("abc123") == nil)
        #expect(CycleCode.label(202606) == "Ciclo 6 · 2026")
    }

    @Test func customerSuggestions() {
        let names = ["María José Pérez", "Mario Soto", "Ana"]
        #expect(CustomerRules.suggestions(names, name: { $0 }, query: "mari") == ["María José Pérez", "Mario Soto"])
        #expect(CustomerRules.exactMatch(names, name: { $0 }, query: " maria  jose perez ") == "María José Pérez")
        #expect(CustomerRules.suggestions(names, name: { $0 }, query: " ").isEmpty)
    }

    @Test func marginSummary() {
        let summary = MarginSummary(revenue: Money(pesos: 1000), cost: Money(pesos: 750), units: 2, salesCount: 1)
        #expect(summary.margin == Money(pesos: 250))
        #expect(summary.marginRate == 0.25)
        #expect(MarginSummary().marginRate == nil)
    }
}
