import Core
import DesignSystem
import Persistence
import SwiftData
import SwiftUI
import Sync

/// Clientes (§4.7): segmentos Pedidos y Clientes.
public struct CustomersHomeScreen: View {
    enum Segment: Hashable { case orders, customers }
    @State private var segment: Segment = .orders
    private let sellerId: String

    public init(sellerId: String) {
        self.sellerId = sellerId
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Vista", selection: $segment) {
                    Text("Pedidos").tag(Segment.orders)
                    Text("Clientes").tag(Segment.customers)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.bottom, 8)
                switch segment {
                case .orders: CustomerOrdersListView(sellerId: sellerId)
                case .customers: CustomersListView(sellerId: sellerId)
                }
            }
            .navigationTitle("Clientes")
            .syncStatusToolbar(sellerId: sellerId)
        }
    }
}

struct CustomerOrdersListView: View {
    @Environment(SyncEngine.self) private var sync
    @Query private var orders: [CustomerOrder]
    let sellerId: String

    init(sellerId: String) {
        self.sellerId = sellerId
        _orders = Query(filter: #Predicate<CustomerOrder> { $0.sellerId == sellerId }, sort: \.orderedAt, order: .reverse)
    }

    var body: some View {
        List {
            ForEach(orders) { order in
                NavigationLink {
                    CustomerOrderEditor(sellerId: sellerId, orderId: order.id)
                } label: {
                    CustomerOrderRow(order: order)
                }
            }
        }
        .overlay {
            if orders.isEmpty {
                ContentUnavailableView("Sin pedidos de clientes", systemImage: "person.2",
                                       description: Text("Anota lo que tus clientes quieren pedir en cada ciclo."))
            }
        }
        .refreshable { await sync.syncNow(sellerId: sellerId) }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    CustomerOrderEditor(sellerId: sellerId, orderId: nil)
                } label: {
                    Label("Nuevo pedido", systemImage: "plus")
                }
            }
        }
    }
}

struct CustomerOrderRow: View {
    let order: CustomerOrder

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(order.customerDisplayName).font(.body.weight(.medium))
                Spacer()
                CustomerOrderStatusBadge(status: order.status)
                if order.syncState == .pending { Image(systemName: "icloud.slash").foregroundStyle(.secondary) }
                if order.syncState == .failed { Image(systemName: "exclamationmark.icloud.fill").foregroundStyle(StatusTone.danger.color) }
            }
            Text("\(CycleCode.label(order.cycle)) · \(order.orderedAt.formatted(date: .abbreviated, time: .omitted)) · \(order.lineCount) línea(s)")
                .font(.caption).foregroundStyle(.secondary)
            if let note = order.note {
                Text(note).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }
}

struct CustomerOrderStatusBadge: View {
    let status: CustomerOrderStatus

    var body: some View {
        switch status {
        case .draft: StatusBadge(status.label)
        case .confirmed: StatusBadge(status.label, tone: .info)
        case .fulfilled: StatusBadge(status.label, tone: .success)
        case .cancelled: StatusBadge(status.label, tone: .danger)
        }
    }
}
