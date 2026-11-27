import Core
import DesignSystem
import Persistence
import SwiftData
import SwiftUI

/// Ofertas del ciclo vigente (M6, GSP `cardSection`): descuentos, promociones y regalos, por categoría.
/// Se leen al traer pedidos de Natura y quedan guardadas para verlas sin conexión.
struct CycleOffersScreen: View {
    @Query private var products: [CatalogProduct]
    @Query private var settings: [SellerSettings]
    @State private var search = ""
    let sellerId: String

    init(sellerId: String) {
        self.sellerId = sellerId
        _products = Query(filter: #Predicate<CatalogProduct> { $0.sellerId == sellerId }, sort: \.name)
        _settings = Query(filter: #Predicate<SellerSettings> { $0.sellerId == sellerId })
    }

    var body: some View {
        let cycle = settings.first?.currentCycleCode
        let query = Normalize.customerName(search)
        let offers = products.filter {
            $0.hasOffer(inCycle: cycle)
                && (query.isEmpty || Normalize.customerName($0.name).contains(query) || $0.naturaSku.contains(query))
        }
        let groups = Dictionary(grouping: offers) { $0.category ?? "Sin categoría" }
        List {
            ForEach(groups.keys.sorted(), id: \.self) { category in
                Section(category) {
                    ForEach(groups[category] ?? []) { product in
                        OfferRow(product: product)
                    }
                }
            }
        }
        .searchable(text: $search, prompt: "Buscar oferta")
        .navigationTitle(cycle.map { "Ofertas · \(CycleCode.label($0))" } ?? "Ofertas del ciclo")
        .overlay {
            if offers.isEmpty {
                ContentUnavailableView(search.isEmpty ? "Sin ofertas guardadas" : "Sin resultados", systemImage: "tag",
                                       description: Text(search.isEmpty ? "Se leen al traer tus pedidos desde Ajustes › Natura." : "Prueba con otro nombre o código."))
            }
        }
    }
}

private struct OfferRow: View {
    let product: CatalogProduct

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(product.name).font(.subheadline.weight(.medium)).lineLimit(2)
                Spacer()
                if let percent = product.cycleDiscountPercent, percent > 0 {
                    StatusBadge("-\(percent)%", tone: .success)
                }
            }
            if let text = product.cycleOfferText {
                Text(text).font(.caption).foregroundStyle(StatusTone.info.color)
            }
            HStack(spacing: 8) {
                Text("SKU \(product.naturaSku)")
                if let purchase = product.cyclePurchasePesos {
                    if let regular = product.cycleRegularPurchasePesos {
                        Text("Compra \(Money(pesos: purchase).formatted) (antes \(Money(pesos: regular).formatted))")
                    } else {
                        Text("Compra \(Money(pesos: purchase).formatted)")
                    }
                }
                if let resale = product.cycleResalePesos { Text("Venta \(Money(pesos: resale).formatted)") }
                if let points = product.cyclePoints { Text("\(points) pts") }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
