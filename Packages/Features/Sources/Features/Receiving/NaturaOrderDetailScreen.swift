import Core
import DesignSystem
import Persistence
import SwiftData
import SwiftUI
import Sync

/// Detalle de pedido Natura (§4.6): totales, entradas de recepción y cerrar/reabrir.
struct NaturaOrderDetailScreen: View {
    @Environment(SyncEngine.self) private var sync
    @Query private var orders: [NaturaOrder]
    @State private var errorMessage: String?
    @State private var working = false
    let orderId: String
    let sellerId: String

    init(orderId: String, sellerId: String) {
        self.orderId = orderId
        self.sellerId = sellerId
        _orders = Query(filter: #Predicate<NaturaOrder> { $0.id == orderId })
    }

    var body: some View {
        if let order = orders.first {
            List {
                Section {
                    HStack(spacing: 8) {
                        MiniStat("Recibido", value: "\(order.receivedUnits)", tone: .success)
                        MiniStat("Pendiente", value: "\(order.pendingUnits)", tone: order.pendingUnits > 0 ? .warning : .neutral)
                        MiniStat("Estado", value: order.receivingStatus.label)
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                    ReceivingProgressBar(received: order.receivedUnits, total: order.receivedUnits + order.pendingUnits)
                    HStack {
                        Text(CycleCode.label(order.cycle))
                        Spacer()
                        ReviewBadge(status: order.reviewStatus)
                    }
                    .font(.subheadline)
                }

                Section {
                    NavigationLink(value: ReceivingRoute.byLine(orderId)) {
                        Label("Recibir por línea", systemImage: "list.bullet.rectangle")
                            .font(.headline).frame(minHeight: 52)
                    }
                    NavigationLink(value: ReceivingRoute.byCode(orderId)) {
                        Label("Recibir por código", systemImage: "barcode.viewfinder")
                            .font(.headline).frame(minHeight: 52)
                    }
                }
                .disabled(!order.linesLoaded)

                Section {
                    if let errorMessage { AlertBanner(errorMessage, tone: .danger) }
                    Button {
                        toggle(closed: !order.isClosed)
                    } label: {
                        HStack {
                            Text(order.isClosed ? "Reabrir pedido" : "Cerrar pedido")
                            Spacer()
                            if working { ProgressView() }
                        }
                    }
                    .disabled(working)
                } footer: {
                    if order.isClosed {
                        Text("Pedido cerrado: recepción y precios quedan bloqueados.")
                    }
                }
            }
            .navigationTitle("Pedido \(order.orderNumber)")
            .navigationBarTitleDisplayMode(.inline)
            .syncStatusToolbar(sellerId: sellerId)
            .refreshable { await sync.refreshNaturaOrder(sellerId: sellerId, orderId: orderId) }
            .task { await sync.refreshNaturaOrder(sellerId: sellerId, orderId: orderId) }
            .overlay {
                if !order.linesLoaded {
                    ContentUnavailableView("Líneas no descargadas", systemImage: "icloud.and.arrow.down",
                                           description: Text("Conéctate para descargar el detalle del pedido."))
                }
            }
        } else {
            ContentUnavailableView("Pedido no encontrado", systemImage: "tray")
        }
    }

    private func toggle(closed: Bool) {
        working = true
        errorMessage = nil
        Task {
            if let error = await sync.setReceivingClosed(sellerId: sellerId, orderId: orderId, closed: closed) {
                errorMessage = error.message
                Haptics.error()
            } else {
                Haptics.success()
            }
            working = false
        }
    }
}
