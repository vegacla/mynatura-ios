import Core
import DesignSystem
import Persistence
import SwiftData
import SwiftUI
import Store

/// "Agregar inventario actual" (una vez, docs/local-first-migration.md §7.1): se cuenta lo que hay hoy;
/// la diferencia con lo comprado queda como ventas previas (FIFO), con ingreso estimado al precio sugerido.
struct InitialInventoryScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(LocalStore.self) private var store
    @Query private var products: [CatalogProduct]
    @Query private var stock: [StockItem]
    let sellerId: String

    @State private var counts: [String: Int] = [:]
    @State private var searchText = ""
    @State private var scanning = false
    @State private var confirming = false
    @State private var message: (text: String, isError: Bool)?

    init(sellerId: String) {
        self.sellerId = sellerId
        _products = Query(filter: #Predicate<CatalogProduct> { $0.sellerId == sellerId }, sort: \.name)
        _stock = Query(filter: #Predicate<StockItem> { $0.sellerId == sellerId })
    }

    private var purchased: [String: Int] {
        Dictionary(stock.map { ($0.sellerProductId, $0.operationalQuantity) }, uniquingKeysWith: { first, _ in first })
    }

    /// Productos comprados alguna vez, más los que ya se contaron.
    private var rows: [CatalogProduct] {
        let purchased = purchased
        return products.filter { (purchased[$0.id] ?? 0) > 0 || (counts[$0.id] ?? 0) > 0 }
            .filter { ProductSearch.matches(query: searchText, name: $0.name, sku: $0.naturaSku, barcodes: $0.barcodes) }
    }

    private var totals: (counted: Int, purchased: Int) {
        let purchased = purchased
        let ids = Set(purchased.keys).union(counts.keys)
        return (ids.reduce(0) { $0 + (counts[$1] ?? 0) }, ids.reduce(0) { $0 + (purchased[$1] ?? 0) })
    }

    var body: some View {
        let purchased = purchased
        List {
            Section {
                Text("Cuenta lo que tienes hoy. Escanea cada unidad (suma 1) o ajusta a mano. Lo que no cuentes se considera vendido antes de usar la app.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if let message {
                    AlertBanner(message.text, tone: message.isError ? .danger : .success)
                }
                let totals = totals
                LabeledContent("Contado", value: "\(totals.counted) de \(totals.purchased) comprados")
            }
            Section("Productos") {
                ForEach(rows) { product in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(product.name).font(.subheadline.weight(.medium))
                        Text("SKU \(product.naturaSku) · comprado \(purchased[product.id] ?? 0)")
                            .font(.caption).foregroundStyle(.secondary)
                        QuantityStepper("Hoy tengo", value: Binding(
                            get: { counts[product.id] ?? 0 },
                            set: { counts[product.id] = max($0, 0) }), in: 0...9999)
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: "Nombre, SKU o EAN")
        .navigationTitle("Inventario actual")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ScannerButton { scanning = true }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Guardar") { confirming = true }
            }
        }
        .sheet(isPresented: $scanning) {
            ScannerSheet(title: "Contar inventario", continuous: true) { code in count(code) }
        }
        .confirmationDialog("¿Registrar el inventario actual?", isPresented: $confirming, titleVisibility: .visible) {
            Button("Registrar") { save() }
        } message: {
            let totals = totals
            Text("\(max(totals.purchased - totals.counted, 0)) unidad(es) quedarán como ventas previas, estimadas a su precio sugerido. Se hace una sola vez.")
        }
    }

    private func count(_ code: String) {
        let match = products.first { ProductSearch.isExactCodeMatch(code: code, sku: $0.naturaSku, barcodes: $0.barcodes) }
        guard let match else {
            message = ("No conozco el código \(code). Búscalo y súmalo a mano.", true)
            Haptics.error()
            return
        }
        counts[match.id, default: 0] += 1
        message = ("\(match.name): \(counts[match.id] ?? 0)", false)
        Haptics.tap()
    }

    private func save() {
        switch store.setInitialInventory(sellerId: sellerId, counts: counts) {
        case .success(let summary):
            message = (summary, false)
            Haptics.success()
            dismiss()
        case .failure(let error):
            message = (error.message, true)
            Haptics.error()
        }
    }
}
