import Core
import Foundation
import SwiftData
import Testing
@testable import Persistence

@Suite("Respaldo JSON (M5)")
@MainActor
struct BackupTests {
    // El contenedor debe seguir vivo mientras se usa su contexto.
    private let sourceContainer: ModelContainer
    private let targetContainer: ModelContainer

    init() throws {
        sourceContainer = try PersistenceController.makeContainer(inMemory: true)
        targetContainer = try PersistenceController.makeContainer(inMemory: true)
    }

    private func seed(_ context: ModelContext, sellerId: String) throws {
        let settings = SellerSettings(sellerId: sellerId, issueStrategy: .fifo)
        settings.costingMethod = .highestPrice
        settings.initialInventoryAt = Date(timeIntervalSince1970: 1_700_000_000)
        context.insert(settings)
        let product = CatalogProduct(id: "p1", sellerId: sellerId, naturaSku: "70983", name: "Kaiak", source: .orderImport,
                                     isSellable: true, lastPurchasePesos: 15000, lastSuggestedSalePesos: 19990,
                                     barcodes: ["7891033000000"])
        product.category = "Perfumería"
        context.insert(product)
        context.insert(StockItem(sellerProductId: "p1", sellerId: sellerId, naturaSku: "70983", name: "Kaiak",
                                 isSellable: true, theoreticalQuantity: 2, operationalQuantity: 2, lastReconciledAt: nil))
        let lot = InventoryLotRecord(id: "l1", sellerId: sellerId, productId: "p1", receivedAt: .now, quantity: 3,
                                     unitCost: Money(pesos: 15000), source: .purchased, origin: .naturaLine,
                                     naturaOrderLineId: "nl1", suggestedPesos: 19990)
        lot.remaining = 2
        context.insert(lot)
        context.insert(LocalSale(id: "s1", sellerId: sellerId, occurredAt: .now, note: "Ana", customerId: "c1",
                                 customerName: "Ana", lines: [
                                     SaleLineSnapshot(sellerProductId: "p1", productName: "Kaiak", naturaSku: "70983",
                                                      quantity: 1, suggestedPesos: 19990, finalPesos: 18990, reasonCode: nil,
                                                      reasonNote: nil, costUnitPesos: 15000),
                                 ], syncState: .synced, kind: .sale))
        context.insert(Customer(id: "c1", sellerId: sellerId, displayName: "Ana Pérez", rut: nil, phone: "+56911111111", notes: nil))
        let order = NaturaOrder(id: "o1", sellerId: sellerId, orderNumber: "811111100", cycle: 202618, orderedAt: .now)
        order.reviewStatus = .closed
        context.insert(order)
        let line = NaturaOrderLine(id: "nl1", orderId: "o1", sellerId: sellerId, position: 0, naturaSku: "70983",
                                   productName: "Kaiak", quantity: 3)
        line.receivedQuantity = 3
        line.purchasePesos = 15000
        context.insert(line)
        context.insert(PendingMutation(type: .saleCreate, sellerId: sellerId, entityKey: "s1", payload: Data()))
        try context.save()
    }

    @Test func roundTripReplacesDataAndKeepsSession() throws {
        let source = sourceContainer.mainContext
        try seed(source, sellerId: "old-seller")
        let backup = try BackupService.makeBackup(context: source, sellerId: "old-seller", appVersion: "1.0.0 (1)")
        let data = try BackupService.encode(backup)
        let decoded = try BackupService.decode(data)
        #expect(decoded.products == backup.products)
        #expect(decoded.sales.map(\.lines) == backup.sales.map(\.lines))
        #expect(abs(decoded.exportedAt.timeIntervalSince(backup.exportedAt)) < 0.001)
        #expect(decoded.counts == BackupCounts(products: 1, lots: 1, sales: 1, customers: 1, customerOrders: 0,
                                               naturaOrders: 1, naturaLines: 1, events: 0))

        let target = targetContainer.mainContext
        target.insert(SessionSummary(sellerId: "new-seller", customerCode: "123", displayName: "Consultora"))
        target.insert(CatalogProduct(id: "other", sellerId: "new-seller", naturaSku: "1", name: "Se borra", source: .manual,
                                     isSellable: true, lastPurchasePesos: 0, lastSuggestedSalePesos: nil, barcodes: []))
        try target.save()
        try BackupService.restore(decoded, context: target, sellerId: "new-seller")

        let products = try target.fetch(FetchDescriptor<CatalogProduct>())
        #expect(products.map(\.id) == ["p1"])
        #expect(products.first?.sellerId == "new-seller")
        #expect(products.first?.category == "Perfumería")
        let lots = try target.fetch(FetchDescriptor<InventoryLotRecord>())
        #expect(lots.first?.remaining == 2)
        #expect(lots.first?.source == .purchased)
        #expect(try target.fetch(FetchDescriptor<LocalSale>()).first?.lines.first?.finalPesos == 18990)
        #expect(try target.fetch(FetchDescriptor<NaturaOrder>()).first?.isClosed == true)
        #expect(try target.fetch(FetchDescriptor<NaturaOrderLine>()).first?.receivedQuantity == 3)
        let settings = try target.fetch(FetchDescriptor<SellerSettings>())
        #expect(settings.first?.costingMethod == .highestPrice)
        #expect(settings.first?.lastBackupAt == decoded.exportedAt)
        // La cola no viaja en el respaldo; la sesión se conserva.
        #expect(try target.fetch(FetchDescriptor<PendingMutation>()).isEmpty)
        #expect(try target.fetch(FetchDescriptor<SessionSummary>()).count == 1)
    }

    @Test func rejectsForeignOrNewerFiles() {
        #expect(throws: BackupError.notABackup) { try BackupService.decode(Data(#"{"hola":1}"#.utf8)) }
        #expect(throws: BackupError.notABackup) { try BackupService.decode(Data("no es json".utf8)) }
        #expect(throws: BackupError.newerVersion(99)) {
            try BackupService.decode(Data(#"{"format":"mynatura-backup","version":99}"#.utf8))
        }
    }
}
