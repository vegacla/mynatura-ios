import Core
import DesignSystem
import Persistence
import SwiftData
import SwiftUI
import Store

/// Recepción (§4.6): lista de pedidos Natura entregados.
public struct ReceivingScreen: View {
    @Environment(LocalStore.self) private var store
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
                NavigationLink(value: ReceivingRoute.order(order.id)) {
                    NaturaOrderRow(order: order)
                }
            }
            // Rutas por valor: cada pantalla se construye solo al navegar (no una por fila).
            .navigationDestination(for: ReceivingRoute.self) { route in
                switch route {
                case .order(let id): NaturaOrderDetailScreen(orderId: id, sellerId: sellerId)
                case .byLine(let id): ReceiveByLineScreen(orderId: id, sellerId: sellerId)
                case .byCode(let id): ReceiveByCodeScreen(orderId: id, sellerId: sellerId)
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
            .navigationTitle("Recepción")
            .mainToolbar(sellerId: sellerId)
        }
    }
}

enum ReceivingRoute: Hashable {
    case order(String)
    case byLine(String)
    case byCode(String)
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
