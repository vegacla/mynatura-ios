import Core
import DesignSystem
import Persistence
import SwiftData
import SwiftUI
import Sync

/// Editor de pedido de cliente (§4.7), optimizado para hablar con el cliente. 100 % offline.
struct CustomerOrderEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(SyncEngine.self) private var sync
    @Environment(AppRouter.self) private var router
    @Query private var customers: [Customer]
    @Query private var products: [CatalogProduct]
    @Query private var orders: [CustomerOrder]
    let sellerId: String
    let orderId: String?
    /// Abre el dictado al aparecer (Atajo "Nuevo pedido en MyNatura").
    var startDictating = false

    @State private var loaded = false
    @State private var customerName = ""
    @State private var selectedCustomerId: String?
    @State private var cycleText = ""
    @State private var status: CustomerOrderStatus = .draft
    @State private var note = ""
    @State private var lines: [CustomerOrderLineSnapshot] = []
    @State private var productQuery = ""
    @State private var quickName = ""
    @State private var errorMessage: String?
    @State private var savedMessage: String?
    @State private var showVoice = false
    @State private var voiceUndo: VoiceUndoSnapshot?
    @State private var voiceMessage: String?

    /// Estado previo al último dictado aplicado, para "Deshacer dictado".
    private struct VoiceUndoSnapshot {
        let customerName: String
        let selectedCustomerId: String?
        let cycleText: String
        let note: String
        let lines: [CustomerOrderLineSnapshot]
    }

    init(sellerId: String, orderId: String?, startDictating: Bool = false) {
        self.sellerId = sellerId
        self.orderId = orderId
        self.startDictating = startDictating
        _customers = Query(filter: #Predicate<Customer> { $0.sellerId == sellerId }, sort: \.displayName)
        _products = Query(filter: #Predicate<CatalogProduct> { $0.sellerId == sellerId }, sort: \.name)
        let key = orderId ?? ""
        _orders = Query(filter: #Predicate<CustomerOrder> { $0.id == key })
    }

    private var selectedCustomer: Customer? { customers.first { $0.id == selectedCustomerId } }

    var body: some View {
        Form {
            customerSection
            Section("Ciclo y estado") {
                TextField("Ciclo (AAAACC, ej. 202606)", text: $cycleText)
                    .keyboardType(.numberPad)
                if !cycleText.isEmpty, CycleCode.parse(cycleText) == nil {
                    Text("Formato AAAACC, por ejemplo 202606.").font(.caption).foregroundStyle(StatusTone.danger.color)
                }
                Picker("Estado", selection: $status) {
                    ForEach(CustomerOrderStatus.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                TextField("Nota", text: $note, axis: .vertical)
            }
            if let voiceMessage {
                Section {
                    AlertBanner(voiceMessage, tone: .info, systemImage: "mic.fill")
                    if voiceUndo != nil {
                        Button("Deshacer dictado", role: .destructive) { undoVoice() }
                    }
                }
            }
            productSearchSection
            linesSection
            if let errorMessage { Section { AlertBanner(errorMessage, tone: .danger) } }
            if let savedMessage { Section { AlertBanner(savedMessage, tone: .success, systemImage: "checkmark.circle.fill") } }
            if let order = orders.first, order.status != .fulfilled, order.status != .cancelled, !lines.isEmpty {
                Section {
                    Button("Convertir en venta") { convertToSale(order) }
                } footer: {
                    Text("Carga las líneas en el carro de Vender con este cliente. Al registrar la venta el pedido queda Cumplido.")
                }
            }
        }
        .navigationTitle(orderId == nil ? "Nuevo pedido" : "Pedido")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Guardar", action: save) }
            ToolbarItem(placement: .bottomBar) {
                Button {
                    showVoice = true
                } label: {
                    Label("Dictar", systemImage: "mic.fill")
                        .labelStyle(.titleAndIcon)
                }
            }
        }
        .sheet(isPresented: $showVoice) {
            CustomerOrderVoiceSheet(
                products: productCandidates,
                customers: customerCandidates,
                productLabels: productLabels,
                referenceYear: voiceReferenceYear,
                vocabulary: VoiceVocabulary.contextualStrings(productNames: products.map(\.name),
                                                              customerNames: customers.map(\.displayName)),
                canUndoLastApply: voiceUndo != nil,
                onApply: { applyVoice($0) },
                onUndoLastApply: { undoVoice() })
            .presentationDetents([.medium, .large])
        }
        .task {
            loadIfNeeded()
            if startDictating, !showVoice, voiceUndo == nil, lines.isEmpty { showVoice = true }
            if let orderId {
                await sync.refreshCustomerOrder(sellerId: sellerId, orderId: orderId)
                if lines.isEmpty, let fresh = orders.first?.lines { lines = fresh }
            }
        }
    }

    // MARK: Secciones

    private var customerSection: some View {
        Section {
            TextField("Nombre del cliente", text: $customerName)
                .textContentType(.name)
                .onChange(of: customerName) { _, newValue in
                    if let selected = selectedCustomer, Normalize.customerName(selected.displayName) != Normalize.customerName(newValue) {
                        selectedCustomerId = nil
                    }
                    if selectedCustomerId == nil,
                       let exact = CustomerRules.exactMatch(customers, name: \.displayName, query: newValue) {
                        selectedCustomerId = exact.id
                    }
                }
            if selectedCustomerId == nil {
                ForEach(CustomerRules.suggestions(customers, name: \.displayName, query: customerName)) { customer in
                    Button {
                        selectedCustomerId = customer.id
                        customerName = customer.displayName
                    } label: {
                        Label(customer.displayName, systemImage: "person.crop.circle")
                    }
                }
            }
        } header: {
            Text("Cliente")
        } footer: {
            if selectedCustomerId != nil {
                Label("Cliente seleccionado", systemImage: "checkmark.circle.fill").foregroundStyle(StatusTone.success.color)
            } else if CustomerRules.isValidName(customerName) {
                Label("Cliente nuevo: se creará al guardar", systemImage: "person.badge.plus")
            }
        }
    }

    private var productSearchSection: some View {
        Section("Agregar producto") {
            TextField("Buscar por nombre o SKU", text: $productQuery)
                .textInputAutocapitalization(.never)
            let query = productQuery.trimmingCharacters(in: .whitespaces)
            if !query.isEmpty {
                let matches = products.filter { ProductSearch.matches(query: query, name: $0.name, sku: $0.naturaSku, barcodes: $0.barcodes) }
                ForEach(matches.prefix(8)) { product in
                    Button {
                        addLine(product)
                    } label: {
                        VStack(alignment: .leading) {
                            Text(product.name).foregroundStyle(.primary)
                            Text("SKU \(product.naturaSku) · \(product.lastSuggestedSale?.formatted ?? "—")")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                if matches.isEmpty {
                    Text("No está en tu catálogo. Créalo rápido:").font(.caption).foregroundStyle(.secondary)
                    TextField("Nombre del producto", text: $quickName)
                    Button("Crear SKU \(Normalize.naturaSku(query)) y agregar") { quickCreate(sku: query) }
                        .disabled(quickName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private var linesSection: some View {
        Section("Líneas (\(lines.count))") {
            ForEach($lines) { $line in
                VStack(alignment: .leading, spacing: 4) {
                    Text(line.productName).font(.subheadline.weight(.medium))
                    Text("SKU \(line.naturaSku) · Sugerido \(line.suggestedPesos.map { Money(pesos: $0).formatted } ?? "—")")
                        .font(.caption).foregroundStyle(.secondary)
                    QuantityStepper("Cantidad", value: $line.quantity, in: 1...999)
                    LabeledContent("Precio final") {
                        MoneyField("Precio final", money: Binding(
                            get: { Money(pesos: line.finalPesos ?? line.suggestedPesos ?? 0) },
                            set: { line.finalPesos = $0.pesos })).frame(maxWidth: 140)
                    }
                }
            }
            .onDelete { lines.remove(atOffsets: $0) }
        }
    }

    // MARK: Voz

    private var productCandidates: [VoiceCandidate] {
        products.map { VoiceCandidate(id: $0.id, name: $0.name, code: $0.naturaSku) }
    }

    private var customerCandidates: [VoiceCandidate] {
        customers.map { VoiceCandidate(id: $0.id, name: $0.displayName) }
    }

    private var productLabels: [String: String] {
        Dictionary(products.map { ($0.id, "\($0.name) · \($0.naturaSku)") }, uniquingKeysWith: { first, _ in first })
    }

    private var voiceReferenceYear: Int {
        CycleCode.parse(cycleText).map { $0 / 100 } ?? Calendar.current.component(.year, from: .now)
    }

    private func applyVoice(_ items: [VoiceProposalItem]) {
        let snapshot = VoiceUndoSnapshot(customerName: customerName, selectedCustomerId: selectedCustomerId,
                                         cycleText: cycleText, note: note, lines: lines)
        let state = VoiceOrderState(
            customerId: selectedCustomerId, customerName: customerName, cycle: CycleCode.parse(cycleText), note: note,
            lines: lines.map { VoiceOrderState.Line(productId: $0.sellerProductId, quantity: $0.quantity, finalPesos: $0.finalPesos) })
        let result = VoiceOrderApplier.apply(items, to: state, customers: customerCandidates)
        guard result.applied > 0 else {
            voiceMessage = "No se aplicó nada del dictado."
            return
        }

        let existing = Dictionary(lines.map { ($0.sellerProductId, $0) }, uniquingKeysWith: { first, _ in first })
        let productsById = Dictionary(products.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let newLines: [CustomerOrderLineSnapshot] = result.state.lines.compactMap { line in
            if var current = existing[line.productId] {
                current.quantity = line.quantity
                current.finalPesos = line.finalPesos
                return current
            }
            guard let product = productsById[line.productId] else { return nil }
            return CustomerOrderLineSnapshot(
                sellerProductId: product.id, productName: product.name, naturaSku: product.naturaSku,
                quantity: line.quantity, suggestedPesos: product.lastSuggestedSalePesos, finalPesos: line.finalPesos)
        }

        voiceUndo = snapshot
        customerName = result.state.customerName
        selectedCustomerId = result.state.customerId
        if let cycle = result.state.cycle { cycleText = String(cycle) }
        note = result.state.note
        lines = newLines
        voiceMessage = result.skipped > 0
            ? "Dictado aplicado: \(result.applied) cambio(s); \(result.skipped) sin resolver se omitieron."
            : "Dictado aplicado: \(result.applied) cambio(s)."
        Haptics.success()
    }

    private func undoVoice() {
        guard let snapshot = voiceUndo else { return }
        customerName = snapshot.customerName
        selectedCustomerId = snapshot.selectedCustomerId
        cycleText = snapshot.cycleText
        note = snapshot.note
        lines = snapshot.lines
        voiceUndo = nil
        voiceMessage = "Dictado deshecho."
    }

    // MARK: Acciones

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        if let order = orders.first {
            customerName = order.customerDisplayName
            selectedCustomerId = order.customerId
            cycleText = String(order.cycle)
            status = order.status
            note = order.note ?? ""
            lines = order.lines ?? []
        } else {
            let lastCycle = (try? context.fetch(FetchDescriptor<CustomerOrder>(
                predicate: #Predicate { $0.sellerId == sellerId }, sortBy: [SortDescriptor(\.orderedAt, order: .reverse)])))?.first?.cycle
            cycleText = lastCycle.map(String.init) ?? ""
        }
    }

    private func addLine(_ product: CatalogProduct) {
        if let index = lines.firstIndex(where: { $0.sellerProductId == product.id }) {
            lines[index].quantity += 1
        } else {
            lines.append(CustomerOrderLineSnapshot(
                sellerProductId: product.id, productName: product.name, naturaSku: product.naturaSku, quantity: 1,
                suggestedPesos: product.lastSuggestedSalePesos, finalPesos: nil))
        }
        productQuery = ""
        Haptics.tap()
    }

    private func quickCreate(sku: String) {
        switch sync.quickCreateProduct(sellerId: sellerId, sku: sku, name: quickName) {
        case .success(let id):
            if let product = products.first(where: { $0.id == id }) ?? (try? context.fetch(
                FetchDescriptor<CatalogProduct>(predicate: #Predicate { $0.id == id })))?.first {
                addLine(product)
            }
            quickName = ""
        case .failure(let error):
            errorMessage = error.message
        }
    }

    private func save() {
        errorMessage = nil
        guard let cycle = CycleCode.parse(cycleText) else {
            errorMessage = "El ciclo es obligatorio, formato AAAACC (ej. 202606)."
            return
        }
        switch sync.saveCustomerOrder(sellerId: sellerId, orderId: orders.first?.id, customerId: selectedCustomerId,
                                      newCustomerName: selectedCustomerId == nil ? customerName : nil,
                                      cycle: cycle, status: status, note: note, lines: lines) {
        case .success:
            Haptics.success()
            if orderId == nil { dismiss() } else { savedMessage = "Pedido guardado." }
        case .failure(let error):
            Haptics.error()
            errorMessage = error.message
        }
    }

    private func convertToSale(_ order: CustomerOrder) {
        save()
        guard errorMessage == nil else { return }
        Cart.load(order: order, sellerId: sellerId, context: context)
        router.tab = .sell
    }
}
