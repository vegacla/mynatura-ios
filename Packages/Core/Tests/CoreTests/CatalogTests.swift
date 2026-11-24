import Testing
@testable import Core

@Suite("Catalog")
struct CatalogTests {
    let name = "Desodorante Colonia Kaiak Masculino"
    let sku = "70983"
    let barcodes = ["7908132297387"]

    @Test func emptyQueryMatchesAll() {
        #expect(ProductSearch.matches(query: "  ", name: name, sku: sku, barcodes: barcodes))
    }

    @Test func matchesNameTokensIgnoringAccentsAndOrder() {
        #expect(ProductSearch.matches(query: "kaiak desodorante", name: name, sku: sku, barcodes: barcodes))
        #expect(ProductSearch.matches(query: "MASCULÍNO", name: "masculino", sku: sku, barcodes: []))
        #expect(!ProductSearch.matches(query: "ekos", name: name, sku: sku, barcodes: barcodes))
    }

    @Test func matchesSkuAndEan() {
        #expect(ProductSearch.matches(query: "#7098", name: name, sku: sku, barcodes: barcodes))
        #expect(ProductSearch.matches(query: "2297387", name: name, sku: "1", barcodes: barcodes))
        #expect(!ProductSearch.matches(query: "12", name: name, sku: "1", barcodes: barcodes))
    }

    @Test func exactCodeMatch() {
        #expect(ProductSearch.isExactCodeMatch(code: " 7908132297387 ", sku: sku, barcodes: barcodes))
        #expect(ProductSearch.isExactCodeMatch(code: "#70983", sku: sku, barcodes: barcodes))
        #expect(!ProductSearch.isExactCodeMatch(code: "7098", sku: sku, barcodes: barcodes))
        #expect(!ProductSearch.isExactCodeMatch(code: "", sku: sku, barcodes: barcodes))
    }

    @Test func snapshotMergeKeepsProtected() {
        let deleted = SnapshotMerge.idsToDelete(localIds: ["a", "b", "c"], remoteIds: ["a"], protectedIds: ["c"])
        #expect(deleted == ["b"])
        #expect(!SnapshotMerge.shouldOverwrite(id: "c", protectedIds: ["c"]))
        #expect(SnapshotMerge.shouldOverwrite(id: "a", protectedIds: ["c"]))
    }

    @Test func rawValuesMatchBackend() {
        #expect(ProductSource(rawValue: "order_import") == .orderImport)
        #expect(ProductSource.orderImport.label == "Importado")
        #expect(IssueStrategy(rawValue: "lifo") == .lifo)
    }
}
