import Core
import DesignSystem
import Persistence
import SwiftData
import SwiftUI
import Sync

/// Recepción (§4.6): lista de pedidos Natura entregados.
public struct ReceivingScreen: View {
    @Environment(SyncEngine.self) private var sync
    @Query private var orders: [NaturaOrder]
    @State private var searchText = ""
    private let sellerId: String

    public init(sellerId: String) {
        self.sellerId = sellerId
        _orders = Query(filter: #Predicate<NaturaOrder> { $0.sellerId == sellerId }, sort: \.orderedAt, order: .reverse)
    }

    public var body: some View {
        NavigationStack {
            let filtered = orders.filter { searchText.isEmpty || $0.orderNumber.localizedCaseInsensitiveContains(searchText) }
            List(filtered) { order in
                NavigationLink {
                    NaturaOrderDetailScreen(orderId: order.id, sellerId: sellerId)
                } label: {
                    NaturaOrderRow(order: order)
                }
            }
            .overlay {
                if orders.isEmpty {
                    ContentUnavailableView("Sin pedidos Natura", systemImage: "tray",
                                           description: Text("Importa tus pedidos entregados en Ajustes › Sincronización Natura."))
                } else if filtered.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                }
            }
            .searchable(text: $searchText, prompt: "Número de pedido")
            .refreshable { await sync.syncNow(sellerId: sellerId) }
            .navigationTitle("Recepción")
            .syncStatusToolbar(sellerId: sellerId)
        }
    }
}

struct NaturaOrderRow: View {
    let order: NaturaOrder

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Pedido \(order.orderNumber)").font(.body.weight(.medium))
                Spacer()
                ReviewBadge(status: order.reviewStatus)
            }
            HStack(spacing: 6) {
                Text(CycleCode.label(order.cycle))
                if let delivered = order.deliveredAt {
                    Text("· Entrega \(delivered.formatted(date: .abbreviated, time: .omitted))")
                }
                if let ocr = order.ocrStatus { OcrBadge(status: ocr) }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            ReceivingProgressBar(received: order.receivedUnits, total: order.receivedUnits + order.pendingUnits)
        }
        .padding(.vertical, 2)
    }
}

struct ReviewBadge: View {
    let status: ReceivingReviewStatus

    var body: some View {
        StatusBadge(status.label, tone: status == .closed ? .success : .neutral,
                    systemImage: status == .closed ? "lock.fill" : nil)
    }
}

struct OcrBadge: View {
    let status: ReceiptOcrStatus

    var body: some View {
        switch status {
        case .pending: StatusBadge(status.label, tone: .warning)
        case .succeeded: StatusBadge(status.label, tone: .success)
        case .failed: StatusBadge(status.label, tone: .danger)
        }
    }
}

struct ReceivingStatusBadge: View {
    let status: ReceivingStatus

    var body: some View {
        switch status {
        case .pending: StatusBadge(status.label, tone: .neutral)
        case .partial: StatusBadge(status.label, tone: .warning)
        case .complete: StatusBadge(status.label, tone: .success)
        }
    }
}
