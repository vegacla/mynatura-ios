import Core
import DesignSystem
import Persistence
import SwiftData
import SwiftUI
import Store

enum CatalogRoute: Hashable {
    case product(id: String)
}

/// Productos (§4.5): catálogo visible con búsqueda por nombre/SKU/EAN. Funciona offline desde SwiftData.
public struct ProductsScreen: View {
    @Environment(LocalStore.self) private var store
    @Query private var products: [CatalogProduct]
    @Query private var stock: [StockItem]
    @State private var searchText = ""
    @State private var path = NavigationPath()
    private let sellerId: String

    public init(sellerId: String) {
        self.sellerId = sellerId
        _products = Query(filter: #Predicate<CatalogProduct> { $0.sellerId == sellerId }, sort: \.name)
        _stock = Query(filter: #Predicate<StockItem> { $0.sellerId == sellerId })
    }

    private var stockById: [String: StockItem] {
        Dictionary(stock.map { ($0.sellerProductId, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private var filtered: [CatalogProduct] {
        products.filter {
            ProductSearch.matches(query: searchText, name: $0.name, sku: $0.naturaSku, barcodes: $0.barcodes)
        }
    }

    public var body: some View {
        NavigationStack(path: $path) {
            let stockById = stockById
            List(filtered) { product in
                NavigationLink(value: CatalogRoute.product(id: product.id)) {
                    ProductRow(product: product, stock: stockById[product.id])
                }
            }
            .listStyle(.insetGrouped)
            .overlay {
                if products.isEmpty {
                    ContentUnavailableView(
                        "Sin productos", systemImage: "shippingbox",
                        description: Text("Trae tus pedidos desde Ajustes › Natura: el catálogo se arma con tus pedidos y el catálogo del ciclo."))
                } else if filtered.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                }
            }
            .searchable(text: $searchText, prompt: "Nombre, SKU o EAN")
            .navigationTitle("Productos")
            .mainToolbar(sellerId: sellerId)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    ProductPhotoButton(sellerId: sellerId)
                }
            }
            .navigationDestination(for: CatalogRoute.self) { route in
                switch route {
                case .product(let id):
                    ProductDetailScreen(productId: id, sellerId: sellerId)
                }
            }
        }
    }
}

struct ProductRow: View {
    let product: CatalogProduct
    let stock: StockItem?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ProductPhoto(product.imageURL, size: 52)
            details
        }
        .padding(.vertical, 2)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(product.name).font(.body.weight(.medium)).lineLimit(2)
                Spacer()
                Text("\(stock?.operationalQuantity ?? 0)")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle((stock?.operationalQuantity ?? 0) > 0 ? Color.primary : Color.secondary)
                    .accessibilityLabel("Stock \(stock?.operationalQuantity ?? 0)")
            }
            HStack(spacing: 6) {
                Text("SKU \(product.naturaSku)").font(.caption).foregroundStyle(.secondary)
                SellableBadge(isSellable: product.isSellable)
                StatusBadge(product.source.label)
            }
            HStack(spacing: 12) {
                (Text("Compra ") + Text(product.lastPurchase.formatted).monospacedDigit())
                (Text("Sugerido ") + Text(product.lastSuggestedSale?.formatted ?? "—").monospacedDigit())
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            if let category = product.category {
                Text(product.cycleCode.map { "\(category) · \(CycleCode.label($0))" } ?? category)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct SellableBadge: View {
    let isSellable: Bool

    var body: some View {
        StatusBadge(isSellable ? "Vendible" : "No vendible", tone: isSellable ? .success : .neutral)
    }
}
