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

    init(sellerId: String, orderId: String?) {
        self.sellerId = sellerId
        self.orderId = orderId
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
        }
        .task {
            loadIfNeeded()
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
