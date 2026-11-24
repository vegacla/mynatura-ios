import Core
import DesignSystem
import Persistence
import SwiftData
import SwiftUI
import Sync

/// Historial de ventas (§4.4), con ventas locales pendientes/fallidas.
struct SalesHistoryScreen: View {
    @Environment(SyncEngine.self) private var sync
    @Query private var sales: [LocalSale]
    @Query private var reasonRecords: [PricingReasonRecord]
    let sellerId: String

    init(sellerId: String) {
        self.sellerId = sellerId
        _sales = Query(filter: #Predicate<LocalSale> { $0.sellerId == sellerId }, sort: \.occurredAt, order: .reverse)
    }

    var body: some View {
        let reasonLabels = Dictionary(reasonRecords.map { ($0.code, $0.label) }, uniquingKeysWith: { first, _ in first })
        List(sales) { sale in
            SaleRow(sale: sale, reasonLabels: reasonLabels, sellerId: sellerId)
        }
        .overlay {
            if sales.isEmpty {
                ContentUnavailableView("Sin ventas", systemImage: "clock")
            }
        }
        .refreshable { await sync.syncNow(sellerId: sellerId) }
        .navigationTitle("Ventas")
        .syncStatusToolbar(sellerId: sellerId)
    }
}

struct SaleRow: View {
    let sale: LocalSale
    let reasonLabels: [String: String]
    let sellerId: String

    var body: some View {
        DisclosureGroup {
            ForEach(sale.lines, id: \.self) { line in
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
            if sale.syncState == .failed {
                if let message = sale.errorMessage {
                    AlertBanner(message, tone: .danger)
                }
                NavigationLink("Revisar venta") { SaleReviewScreen(saleId: sale.id, sellerId: sellerId) }
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(sale.customerName ?? "Sin cliente").font(.body.weight(.medium))
                    Text(sale.occurredAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption).foregroundStyle(.secondary)
                    if let note = sale.note {
                        Text(note).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer()
                switch sale.syncState {
                case .pending: Image(systemName: "icloud.slash").foregroundStyle(.secondary).accessibilityLabel("Sin sincronizar")
                case .failed: Image(systemName: "exclamationmark.icloud.fill").foregroundStyle(StatusTone.danger.color).accessibilityLabel("Falló")
                case .synced: EmptyView()
                }
                MoneyText(sale.total).font(.body.weight(.semibold))
                    .foregroundStyle(sale.syncState == .failed ? StatusTone.danger.color : Color.primary)
            }
        }
    }
}

/// "Revisar venta" (§7.5): editar cantidades y reenviar, o descartar. Nunca se pisa sola.
struct SaleReviewScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SyncEngine.self) private var sync
    @Query private var sales: [LocalSale]
    @Query private var mutations: [PendingMutation]
    @State private var quantities: [String: Int] = [:]
    @State private var errorMessage: String?
    @State private var confirmingDiscard = false
    let saleId: String
    let sellerId: String

    init(saleId: String, sellerId: String) {
        self.saleId = saleId
        self.sellerId = sellerId
        _sales = Query(filter: #Predicate<LocalSale> { $0.id == saleId })
        _mutations = Query(filter: #Predicate<PendingMutation> { $0.entityKey == saleId })
    }

    var body: some View {
        if let sale = sales.first {
            Form {
                if let message = sale.errorMessage {
                    Section { AlertBanner(message, tone: .danger) }
                }
                Section("Líneas") {
                    ForEach(sale.lines, id: \.sellerProductId) { line in
                        VStack(alignment: .leading) {
                            Text(line.productName).font(.subheadline)
                            QuantityStepper("Cantidad", value: Binding(
                                get: { quantities[line.sellerProductId] ?? line.quantity },
                                set: { quantities[line.sellerProductId] = $0 }), in: 0...999)
                        }
                    }
                } footer: {
                    Text("Deja en 0 las líneas que quieras quitar.")
                }
                if let errorMessage {
                    Section { AlertBanner(errorMessage, tone: .danger) }
                }
                Section {
                    Button("Reenviar venta") {
                        let lines = sale.lines.map { line -> SaleLineSnapshot in
                            var copy = line
                            copy.quantity = quantities[line.sellerProductId] ?? line.quantity
                            return copy
                        }
                        if let error = sync.resubmitSale(sellerId: sellerId, saleId: saleId, lines: lines) {
                            errorMessage = error.message
                        } else {
                            dismiss()
                        }
                    }
                    Button("Descartar venta", role: .destructive) { confirmingDiscard = true }
                }
            }
            .navigationTitle("Revisar venta")
            .confirmationDialog("¿Descartar esta venta?", isPresented: $confirmingDiscard, titleVisibility: .visible) {
                Button("Descartar", role: .destructive) {
                    if let mutation = mutations.first { sync.discard(mutation, sellerId: sellerId) }
                    dismiss()
                }
            } message: {
                Text("Se borra del iPhone y se devuelve el stock local.")
            }
        } else {
            ContentUnavailableView("Venta no encontrada", systemImage: "cart")
        }
    }
}
