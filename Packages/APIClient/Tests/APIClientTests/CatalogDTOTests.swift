import Foundation
import Testing
@testable import APIClient

@Suite("Catalog DTOs")
struct CatalogDTOTests {
    @Test func decodesCatalog() throws {
        let json = #"{"products":[{"id":"p1","naturaSku":"70983","name":"Kaiak","source":"order_import","isSellable":true,"lastPurchaseUnitPriceCents":9990,"lastSuggestedSaleUnitPriceCents":null,"barcodes":["7908132297387"]}]}"#
        let response = try JSONCoding.decoder.decode(CatalogProductsResponseDTO.self, from: Data(json.utf8))
        #expect(response.products.first?.lastSuggestedSaleUnitPriceCents == nil)
        #expect(response.products.first?.barcodes == ["7908132297387"])
    }

    @Test func decodesStockWithNullableDate() throws {
        let json = #"{"items":[{"sellerProductId":"p1","naturaSku":"1","name":"A","isSellable":true,"theoreticalQuantity":5,"operationalQuantity":4,"lastReconciledAt":"2026-11-20T15:04:05.123Z"},{"sellerProductId":"p2","naturaSku":"2","name":"B","isSellable":false,"theoreticalQuantity":0,"operationalQuantity":0,"lastReconciledAt":null}]}"#
        let response = try JSONCoding.decoder.decode(StockSummaryResponseDTO.self, from: Data(json.utf8))
        #expect(response.items[0].lastReconciledAt != nil)
        #expect(response.items[1].lastReconciledAt == nil)
    }

    @Test func updateSettingsEndpoint() throws {
        let endpoint = Endpoint<SettingsResponseDTO>.updateSettings(inventoryIssueStrategy: "lifo")
        #expect(endpoint.method == .put)
        #expect(String(data: endpoint.body ?? Data(), encoding: .utf8) == #"{"inventoryIssueStrategy":"lifo"}"#)
    }
}
