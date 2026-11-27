import Core
import DesignSystem
import Persistence
import SwiftData
import SwiftUI
import Store

/// Entrada desde Recepción: elige el ciclo del borrador (el vigente de Natura o el último de los encargos).
struct NaturaOrderDraftEntry: View {
    @Environment(LocalStore.self) private var store
    let sellerId: String

    var body: some View {
        if let cycle = store.draftCycle(sellerId: sellerId) {
            NaturaOrderDraftScreen(sellerId: sellerId, cycle: cycle)
        } else {
            ContentUnavailableView("Sin ciclo", systemImage: "calendar",
                                   description: Text("Trae tus pedidos desde Ajustes › Natura para saber el ciclo vigente."))
        }
    }
}

/// Armar el pedido Natura del ciclo (M8 etapa 2): encargos confirmados − stock, ofertas y reposición, con barra de puntos.
/// Sin conexión. El envío a Natura llega cuando se capture el flujo de GSP; mientras, se comparte la lista.
struct NaturaOrderDraftScreen: View {
    @Environment(LocalStore.self) private var store
    @Query private var drafts: [NaturaOrderDraft]
    let sellerId: String
    let cycle: Int
    @State private var limitText = ""
    @State private var adding: AddingSource?
    @State private var confirmingClear = false

    init(sellerId: String, cycle: Int) {
        self.sellerId = sellerId
        self.cycle = cycle
        let key = NaturaOrderDraft.key(sellerId: sellerId, cycle: cycle)
        _drafts = Query(filter: #Predicate<NaturaOrderDraft> { $0.key == key })
    }

    var body: some View {
        let draft = drafts.first
        let lines = draft?.lines ?? []
        let points = OrderDraftRules.points(lines)
        let status = OrderDraftRules.status(points: points.total, limit: draft?.pointsLimit)
        let total = OrderDraftRules.purchaseTotal(lines)
        List {
            Section {
                PointsBar(points: points.total, unknown: points.unknown, limit: draft?.pointsLimit, status: status)
                LabeledContent("Tope de puntos") {
                    TextField("Sin tope", text: $limitText)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 120)
                }
                LabeledContent("Compra estimada", value: (total.unknown > 0 ? "≥ " : "") + Money(pesos: total.pesos).formatted)
                if case .over(let by) = status {
                    let reduce = OrderDraftRules.reduceFirst(lines, overBy: by).map(\.name)
                    AlertBanner("Te pasas por \(by) puntos." + (reduce.isEmpty ? "" : " Baja primero: " + reduce.joined(separator: ", ") + "."),
                                tone: .danger, systemImage: "exclamationmark.triangle.fill")
                }
                let unconfirmed = store.unconfirmedCustomerOrders(sellerId: sellerId, cycle: cycle)
                if unconfirmed > 0 {
                    Text("\(unconfirmed) pedido(s) de clientes en borrador no suman: confírmalos para incluirlos.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            } header: {
                Text(CycleCode.label(cycle))
            }
            ForEach(OrderDraftSource.allCases, id: \.self) { source in
                let group = lines.filter { $0.source == source }
                Section {
                    if group.isEmpty {
                        Text(placeholder(source)).font(.footnote).foregroundStyle(.secondary)
                    }
                    ForEach(group) { line in
                        DraftLineRow(line: line) { quantity in
                            store.setDraftQuantity(sellerId: sellerId, cycle: cycle, sku: line.sku, quantity: quantity)
                        }
                    }
                    .onDelete { offsets in
                        for index in offsets {
                            store.setDraftQuantity(sellerId: sellerId, cycle: cycle, sku: group[index].sku, quantity: 0)
                        }
                    }
                } header: {
                    HStack {
                        Text(source.label)
                        Spacer()
                        if source != .customers {
                            Button("Agregar") { adding = AddingSource(source: source) }.font(.caption)
                        }
                    }
                }
            }
            Section {
                Button("Vaciar borrador", role: .destructive) { confirmingClear = true }
                    .disabled(lines.isEmpty)
            } footer: {
                Text("Enviar el pedido a Natura desde la app llega más adelante. Mientras tanto, comparte la lista y cárgala en GSP.")
            }
        }
        .navigationTitle("Armar pedido")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: OrderDraftRules.shareText(cycleCode: cycle, lines: lines)) {
                    Label("Compartir", systemImage: "square.and.arrow.up")
                }
                .disabled(lines.isEmpty)
            }
            ToolbarItem(placement: .bottomBar) {
                Button {
                    store.refreshDraftFromCustomers(sellerId: sellerId, cycle: cycle)
                    Haptics.success()
                } label: {
                    Label("Actualizar encargos", systemImage: "arrow.triangle.2.circlepath").labelStyle(.titleAndIcon)
                }
            }
        }
        .sheet(item: $adding) { item in
            DraftProductPicker(sellerId: sellerId, cycle: cycle, source: item.source)
        }
        .confirmationDialog("¿Vaciar el borrador?", isPresented: $confirmingClear, titleVisibility: .visible) {
            Button("Vaciar", role: .destructive) { store.clearDraft(sellerId: sellerId, cycle: cycle) }
        }
        .onAppear {
            let created = store.orderDraft(sellerId: sellerId, cycle: cycle)
            limitText = created.pointsLimit.map(String.init) ?? ""
        }
        .onChange(of: limitText) { _, text in
            store.setDraftPointsLimit(sellerId: sellerId, cycle: cycle, limit: Int(text.filter(\.isNumber)))
        }
    }

    private func placeholder(_ source: OrderDraftSource) -> String {
        switch source {
        case .customers: "Sin encargos confirmados de este ciclo (o ya los cubre tu stock)."
        case .offer: "Agrega ofertas del ciclo."
        case .restock: "Agrega productos para reponer tu stock."
        }
    }
}

private struct AddingSource: Identifiable {
    let source: OrderDraftSource
    var id: String { source.rawValue }
}

private struct PointsBar: View {
    let points: Int
    let unknown: Int
    let limit: Int?
    let status: PointsStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Puntos")
                Spacer()
                Text((unknown > 0 ? "≥ " : "") + "\(points)" + (limit.map { " / \($0)" } ?? ""))
                    .font(.body.monospacedDigit().weight(.semibold))
            }
            if let limit {
                ProgressView(value: Double(min(points, limit)), total: Double(limit)).tint(color)
            }
            if unknown > 0 {
                Text("\(unknown) producto(s) sin puntos conocidos.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var color: Color {
        switch status {
        case .over: StatusTone.danger.color
        case .near: StatusTone.warning.color
        case .ok, .noLimit: StatusTone.success.color
        }
    }
}

private struct DraftLineRow: View {
    let line: OrderDraftLine
    let onChange: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(line.name).font(.subheadline.weight(.medium)).lineLimit(2)
            HStack(spacing: 8) {
                Text("SKU \(line.sku)")
                if let points = line.pointsPerUnit { Text("\(points) pts c/u") }
                if let price = line.purchasePesos { Text(Money(pesos: price).formatted) }
            }
            .font(.caption).foregroundStyle(.secondary)
            if !line.customers.isEmpty {
                Text(line.customersLabel).font(.caption).foregroundStyle(StatusTone.info.color)
            }
            QuantityStepper("Cantidad", value: Binding(get: { line.quantity }, set: onChange), in: 0...99)
        }
        .padding(.vertical, 2)
    }
}

/// Elegir productos del ciclo para agregar (ofertas o reposición).
private struct DraftProductPicker: View {
    @Environment(LocalStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Query private var products: [CatalogProduct]
    @State private var search = ""
    @State private var added: Set<String> = []
    let sellerId: String
    let cycle: Int
    let source: OrderDraftSource

    init(sellerId: String, cycle: Int, source: OrderDraftSource) {
        self.sellerId = sellerId
        self.cycle = cycle
        self.source = source
        _products = Query(filter: #Predicate<CatalogProduct> { $0.sellerId == sellerId }, sort: \.name)
    }

    var body: some View {
        let query = Normalize.customerName(search)
        let candidates = products.filter { product in
            let inScope = source == .offer ? product.hasOffer(inCycle: cycle) : true
            return inScope && (query.isEmpty || Normalize.customerName(product.name).contains(query) || product.naturaSku.contains(query))
        }
        NavigationStack {
            List(candidates.prefix(200)) { product in
                Button {
                    store.addDraftProduct(sellerId: sellerId, cycle: cycle, productId: product.id, source: source)
                    added.insert(product.id)
                    Haptics.tap()
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(product.name).font(.subheadline).foregroundStyle(.primary).lineLimit(2)
                            HStack(spacing: 8) {
                                Text("SKU \(product.naturaSku)")
                                if product.cycleCode == cycle, let points = product.cyclePoints { Text("\(points) pts") }
                                if let offer = product.cycleOfferText, product.cycleCode == cycle { Text(offer) }
                            }
                            .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: added.contains(product.id) ? "checkmark.circle.fill" : "plus.circle")
                            .foregroundStyle(added.contains(product.id) ? StatusTone.success.color : Color.accentColor)
                    }
                }
            }
            .searchable(text: $search, prompt: "Nombre o código")
            .navigationTitle(source == .offer ? "Ofertas del ciclo" : "Agregar producto")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Listo") { dismiss() } }
            }
            .overlay {
                if candidates.isEmpty {
                    ContentUnavailableView(source == .offer ? "Sin ofertas guardadas" : "Sin resultados", systemImage: "tag",
                                           description: Text(source == .offer ? "Se leen al traer tus pedidos desde Ajustes › Natura." : "Prueba con otro nombre o código."))
                }
            }
        }
    }
}
