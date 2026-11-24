import Core
import DesignSystem
import Persistence
import SwiftData
import SwiftUI

/// Detalle de producto (§4.5). Etapa 2: lectura. EAN, conciliación y kardex se editan en la etapa 5.
struct ProductDetailScreen: View {
    @Query private var products: [CatalogProduct]
    @Query private var stock: [StockItem]

    init(productId: String) {
        _products = Query(filter: #Predicate<CatalogProduct> { $0.id == productId })
        _stock = Query(filter: #Predicate<StockItem> { $0.sellerProductId == productId })
    }

    var body: some View {
        if let product = products.first {
            content(product: product, stock: stock.first)
        } else {
            ContentUnavailableView("Producto no encontrado", systemImage: "shippingbox")
        }
    }

    private func content(product: CatalogProduct, stock: StockItem?) -> some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(product.name).font(.headline)
                    HStack(spacing: 6) {
                        Text("SKU \(product.naturaSku)").font(.subheadline).foregroundStyle(.secondary)
                        SellableBadge(isSellable: product.isSellable)
                        StatusBadge(product.source.label)
                    }
                }
                LabeledContent("Precio compra") { MoneyText(product.lastPurchase) }
                LabeledContent("Precio sugerido") { MoneyText(product.lastSuggestedSale) }
            }

            Section("Stock") {
                HStack(spacing: 8) {
                    MiniStat("Operativo", value: "\(stock?.operationalQuantity ?? 0)")
                    MiniStat("Teórico", value: "\(stock?.theoreticalQuantity ?? 0)")
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                if let date = stock?.lastReconciledAt {
                    LabeledContent("Última conciliación", value: date.formatted(date: .abbreviated, time: .shortened))
                }
            }

            Section("EAN asociados") {
                if product.barcodes.isEmpty {
                    Text("Sin EAN").foregroundStyle(.secondary)
                } else {
                    ForEach(product.barcodes, id: \.self) { ean in
                        Text(ean).monospacedDigit()
                    }
                }
            }
        }
        .navigationTitle("Producto")
        .navigationBarTitleDisplayMode(.inline)
    }
}
