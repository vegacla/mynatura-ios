import Core
import DesignSystem
import Persistence
import SwiftData
import SwiftUI
import Store

/// Historial de ventas y obsequios (§4.4).
struct SalesHistoryScreen: View {
    @Environment(LocalStore.self) private var store
    @Query private var sales: [LocalSale]
    @Query private var reasonRecords: [PricingReasonRecord]
    @Query private var products: [CatalogProduct]
    let sellerId: String

    init(sellerId: String) {
        self.sellerId = sellerId
        _sales = Query(filter: #Predicate<LocalSale> { $0.sellerId == sellerId }, sort: \.occurredAt, order: .reverse)
        _products = Query(filter: #Predicate<CatalogProduct> { $0.sellerId == sellerId })
    }

    var body: some View {
        let reasonLabels = Dictionary(reasonRecords.map { ($0.code, $0.label) }, uniquingKeysWith: { first, _ in first })
        let imageURLs = SaleRow.imageURLs(products)
        List(sales) { sale in
            SaleRow(sale: sale, reasonLabels: reasonLabels, imageURLs: imageURLs, sellerId: sellerId)
        }
        .overlay {
            if sales.isEmpty {
                ContentUnavailableView("Sin ventas", systemImage: "clock")
            }
        }
        .navigationTitle("Ventas")
        .mainToolbar(sellerId: sellerId)
    }
}

struct SaleRow: View {
    @Environment(LocalStore.self) private var store
    let sale: LocalSale
    let reasonLabels: [String: String]
    /// Foto por producto (sellerProductId → URL).
    var imageURLs: [String: String] = [:]
    let sellerId: String

    static func imageURLs(_ products: [CatalogProduct]) -> [String: String] {
        Dictionary(products.compactMap { product in product.imageURL.map { (product.id, $0) } },
                   uniquingKeysWith: { first, _ in first })
    }

    var body: some View {
        DisclosureGroup {
            ForEach(sale.lines, id: \.self) { line in
                HStack(alignment: .top, spacing: 10) {
                    ProductPhoto(imageURLs[line.sellerProductId], size: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(line.productName).font(.subheadline)
                        HStack {
                            Text("\(line.quantity) × \(Money(pesos: line.finalPesos).formatted) · SKU \(line.naturaSku)")
                            Spacer()
                            Text(line.total.formatted).monospacedDigit()
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        if let code = line.reasonCode {
                            Text("Motivo: \(reasonLabels[code] ?? code)\(line.reasonNote.map { " · \($0)" } ?? "")")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            if sale.kind == .sale, sale.customerId != nil {
                Button(sale.onCredit ? "Quitar de por cobrar" : "Marcar como fiado (por cobrar)") {
                    _ = store.setSaleOnCredit(saleId: sale.id, onCredit: !sale.onCredit)
                }
                .font(.caption)
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(sale.customerName ?? "Sin cliente").font(.body.weight(.medium))
                        if sale.kind == .gift { StatusBadge("Obsequio", tone: .warning) }
                        if sale.onCredit { StatusBadge("Fiado", tone: .info) }
                    }
                    Text(sale.occurredAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption).foregroundStyle(.secondary)
                    if let note = sale.note {
                        Text(note).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer()
                MoneyText(sale.total).font(.body.weight(.semibold))
            }
        }
    }
}
