import Core
import DesignSystem
import Persistence
import SwiftData
import SwiftUI
import Store

/// Carro (§4.3): líneas, precio final, motivo, cliente, nota y registro.
struct CartSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(LocalStore.self) private var store
    @Query private var lines: [CartDraftLine]
    @Query private var products: [CatalogProduct]
    @Query private var stock: [StockItem]
    @Query private var reasonRecords: [PricingReasonRecord]
    @Query private var drafts: [CartDraft]
    @State private var errorMessage: String?
    @State private var choosingCustomer = false
    @State private var dictating = false
    @State private var voiceMessage: String?
    let sellerId: String

    init(sellerId: String) {
        self.sellerId = sellerId
        _lines = Query(filter: #Predicate<CartDraftLine> { $0.sellerId == sellerId }, sort: \.addedAt)
        _products = Query(filter: #Predicate<CatalogProduct> { $0.sellerId == sellerId })
        _stock = Query(filter: #Predicate<StockItem> { $0.sellerId == sellerId })
        _reasonRecords = Query(sort: \.label)
        _drafts = Query(filter: #Predicate<CartDraft> { $0.sellerId == sellerId })
    }

    private var productById: [String: CatalogProduct] {
        Dictionary(products.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private var stockById: [String: Int] {
        Dictionary(stock.map { ($0.sellerProductId, $0.operationalQuantity) }, uniquingKeysWith: { first, _ in first })
    }

    private var total: Money {
        lines.reduce(Money.zero) { $0 + CartRules.lineTotal(quantity: $1.quantity, finalPrice: $1.finalPrice) }
    }

    var body: some View {
        NavigationStack {
            let productById = productById
            let stockById = stockById
            let reasons = reasonRecords.compactMap(\.reason)
            Form {
                if lines.isEmpty {
                    ContentUnavailableView("Carro vacío", systemImage: "cart")
                }
                ForEach(lines) { line in
                    if let product = productById[line.productId] {
                        CartLineEditor(line: line, product: product, available: stockById[line.productId] ?? 0, reasons: reasons)
                    }
                }
                .onDelete { offsets in
                    for index in offsets { context.delete(lines[index]) }
                    try? context.save()
                }

                if let draft = drafts.first {
                    Section("Venta") {
                        Button {
                            choosingCustomer = true
                        } label: {
                            LabeledContent("Cliente", value: draft.customerName ?? "Sin cliente")
                        }
                        .foregroundStyle(.primary)
                        TextField("Nota general (opcional)", text: Binding(
                            get: { draft.note }, set: { draft.note = $0 }), axis: .vertical)
                        LabeledContent("Total") {
                            MoneyText(total).font(.title3.weight(.bold))
                        }
                    }
                }

                if let voiceMessage {
                    Section { AlertBanner(voiceMessage, tone: .info, systemImage: "mic.fill") }
                }
                if let errorMessage {
                    Section { AlertBanner(errorMessage, tone: .danger) }
                }

                Section {
                    Button(action: register) {
                        Text("Registrar venta").bold().frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(lines.isEmpty)
                    .listRowBackground(Color.clear)
                } footer: {
                    if !store.connectivity.isOnline {
                        Text("Sin conexión: la venta se guarda en el iPhone y se sincroniza sola al volver la red.")
                    }
                }
            }
            .navigationTitle("Carro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cerrar") { dismiss() } }
                ToolbarItem(placement: .bottomBar) {
                    Button { dictating = true } label: { Label("Dictar", systemImage: "mic.fill").labelStyle(.titleAndIcon) }
                }
                ToolbarItem(placement: .destructiveAction) {
                    Button("Vaciar", role: .destructive) { Cart.clear(sellerId: sellerId, context: context) }
                        .disabled(lines.isEmpty)
                }
            }
            .onAppear { _ = Cart.draft(sellerId: sellerId, context: context) }
            .sheet(isPresented: $dictating) {
                CartVoiceSheet(sellerId: sellerId) { summary in voiceMessage = summary }
                    .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $choosingCustomer) {
                CustomerPickerSheet(sellerId: sellerId) { customer in
                    let draft = Cart.draft(sellerId: sellerId, context: context)
                    draft.customerId = customer?.id
                    draft.customerName = customer?.displayName
                    try? context.save()
                }
            }
        }
    }

    private func register() {
        errorMessage = nil
        let draft = Cart.draft(sellerId: sellerId, context: context)
        let saleLines = lines.map {
            SaleDraftLine(productId: $0.productId, quantity: $0.quantity, finalPrice: $0.finalPrice,
                          reasonCode: $0.reasonCode, reasonNote: $0.reasonNote)
        }
        let sourceOrderId = draft.sourceOrderId
        switch store.registerSale(sellerId: sellerId, lines: saleLines, note: draft.note,
                                 customerId: draft.customerId, customerName: draft.customerName) {
        case .success:
            if let sourceOrderId {
                store.setCustomerOrderStatus(sellerId: sellerId, orderId: sourceOrderId, status: .fulfilled)
            }
            Cart.clear(sellerId: sellerId, context: context)
            Haptics.success()
            dismiss()
        case .failure(let error):
            Haptics.error()
            errorMessage = error.message
        }
    }
}

/// Edición de una línea: cantidad (máx. stock), precio final, motivo si corresponde.
private struct CartLineEditor: View {
    @Environment(\.modelContext) private var context
    @Bindable var line: CartDraftLine
    let product: CatalogProduct
    let available: Int
    let reasons: [PricingReason]

    var body: some View {
        let eligible = CartRules.eligibleReasons(reasons, finalPrice: line.finalPrice, suggested: product.lastSuggestedSale)
        Section {
            VStack(alignment: .leading, spacing: 2) {
                Text(product.name).font(.headline)
                Text("SKU \(product.naturaSku) · \(available) disp.").font(.caption).foregroundStyle(.secondary)
            }
            QuantityStepper("Cantidad", value: $line.quantity, in: 1...max(available, 1))
            LabeledContent("Precio final") {
                MoneyField("Precio final", money: Binding(get: { line.finalPrice }, set: { line.finalPrice = $0 }))
                    .frame(maxWidth: 140)
            }
            HStack {
                Text("Sugerido: \(product.lastSuggestedSale?.formatted ?? "—")")
                Spacer()
                Text(CartRules.lineTotal(quantity: line.quantity, finalPrice: line.finalPrice).formatted)
                    .monospacedDigit()
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            if !eligible.isEmpty {
                Picker("Motivo", selection: Binding(get: { line.reasonCode }, set: { line.reasonCode = $0 })) {
                    Text("Elegir…").tag(String?.none)
                    ForEach(eligible, id: \.code) { reason in
                        Text(reason.label).tag(Optional(reason.code))
                    }
                }
                TextField("Observación (opcional)", text: Binding(get: { line.reasonNote ?? "" }, set: { line.reasonNote = $0 }))
            }
        }
        .onChange(of: eligible.map(\.code)) { _, codes in
            if let code = line.reasonCode, !codes.contains(code) { line.reasonCode = nil }
        }
        .onDisappear { try? context.save() }
    }
}
