import Core
import DesignSystem
import Persistence
import SwiftData
import SwiftUI
import Sync

/// Vender (POS, §4.2): productos vendibles con stock, búsqueda, escáner y carro.
public struct SellScreen: View {
    @Environment(\.modelContext) private var context
    @Query private var products: [CatalogProduct]
    @Query private var stock: [StockItem]
    @Query private var cartLines: [CartDraftLine]
    @Environment(SyncEngine.self) private var sync
    @State private var searchText = ""
    @State private var showingCart = false
    @State private var showingScanner = false
    @State private var message: (text: String, isError: Bool)?
    private let sellerId: String

    public init(sellerId: String) {
        self.sellerId = sellerId
        _products = Query(filter: #Predicate<CatalogProduct> { $0.sellerId == sellerId && $0.isSellable }, sort: \.name)
        _stock = Query(filter: #Predicate<StockItem> { $0.sellerId == sellerId })
        _cartLines = Query(filter: #Predicate<CartDraftLine> { $0.sellerId == sellerId })
    }

    private var stockById: [String: Int] {
        Dictionary(stock.map { ($0.sellerProductId, $0.operationalQuantity) }, uniquingKeysWith: { first, _ in first })
    }

    private var cartUnits: Int { cartLines.reduce(0) { $0 + $1.quantity } }

    public var body: some View {
        NavigationStack {
            let stockById = stockById
            let available = products.filter { (stockById[$0.id] ?? 0) > 0 }
            let filtered = available.filter {
                ProductSearch.matches(query: searchText, name: $0.name, sku: $0.naturaSku, barcodes: $0.barcodes)
            }
            List {
                if let message {
                    AlertBanner(message.text, tone: message.isError ? .danger : .success,
                                systemImage: message.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .listRowSeparator(.hidden)
                }
                ForEach(filtered) { product in
                    SellRow(product: product, available: stockById[product.id] ?? 0) { add(product, available: stockById[product.id] ?? 0) }
                }
            }
            .listStyle(.plain)
            .overlay {
                if available.isEmpty {
                    ContentUnavailableView("Sin productos con stock", systemImage: "cart",
                                           description: Text("Recibe un pedido Natura o concilia el stock para poder vender."))
                } else if filtered.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                }
            }
            .searchable(text: $searchText, prompt: "Nombre, SKU o EAN")
            .onSubmit(of: .search) { addExactMatch(searchText) }
            .refreshable { await sync.syncNow(sellerId: sellerId) }
            .navigationTitle("Vender")
            .syncStatusToolbar(sellerId: sellerId)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    ScannerButton { showingScanner = true }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        SalesHistoryScreen(sellerId: sellerId)
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                    .accessibilityLabel("Historial de ventas")
                }
            }
            .safeAreaInset(edge: .bottom) {
                if cartUnits > 0 {
                    Button {
                        showingCart = true
                    } label: {
                        Label("Carro · \(cartUnits) unidad(es)", systemImage: "cart.fill")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .padding()
                    .background(.bar)
                }
            }
            .sheet(isPresented: $showingCart) {
                CartSheet(sellerId: sellerId)
            }
            .sheet(isPresented: $showingScanner) {
                ScannerSheet(title: "Escanear producto", continuous: false) { code in addExactMatch(code) }
            }
        }
    }

    private func add(_ product: CatalogProduct, available: Int) {
        if Cart.add(product, available: available, sellerId: sellerId, context: context) {
            Haptics.success()
            message = nil
        } else {
            Haptics.error()
            message = ("No hay más stock de \(product.name).", true)
        }
    }

    /// Enter o escaneo: agrega el producto cuyo EAN/SKU coincide exactamente (addFirstExactMatch).
    private func addExactMatch(_ code: String) {
        guard let product = products.first(where: { ProductSearch.isExactCodeMatch(code: code, sku: $0.naturaSku, barcodes: $0.barcodes) }) else {
            Haptics.error()
            message = ("No se encontró un producto vendible con el código \(Normalize.scanCode(code)).", true)
            return
        }
        add(product, available: stockById[product.id] ?? 0)
        if message == nil {
            message = ("Agregado: \(product.name)", false)
            searchText = ""
        }
    }
}

private struct SellRow: View {
    let product: CatalogProduct
    let available: Int
    let onAdd: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(product.name).font(.body.weight(.medium)).lineLimit(2)
                HStack(spacing: 6) {
                    Text("SKU \(product.naturaSku)")
                    if let first = product.barcodes.first {
                        Text(first + (product.barcodes.count > 1 ? " +\(product.barcodes.count - 1)" : ""))
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    MoneyText(product.lastSuggestedSale).font(.subheadline.weight(.semibold))
                    Text("\(available) disp.").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if available > 0 {
                Button("Agregar", action: onAdd)
                    .buttonStyle(.bordered)
                    .frame(minHeight: 44)
            } else {
                Text("Sin stock").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
