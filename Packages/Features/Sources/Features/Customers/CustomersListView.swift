import Core
import DesignSystem
import Persistence
import SwiftData
import SwiftUI
import Store

struct CustomersListView: View {
    @Environment(LocalStore.self) private var store
    @Query private var customers: [Customer]
    @State private var searchText = ""
    @State private var creating = false
    let sellerId: String

    init(sellerId: String) {
        self.sellerId = sellerId
        _customers = Query(filter: #Predicate<Customer> { $0.sellerId == sellerId }, sort: \.displayName)
    }

    var body: some View {
        let query = Normalize.customerName(searchText)
        let rutQuery = Normalize.rut(searchText)
        let filtered = customers.filter { customer in
            if query.isEmpty { return true }
            if customer.normalizedName.contains(query) { return true }
            if (customer.phone ?? "").contains(searchText) { return true }
            return !rutQuery.isEmpty && Normalize.rut(customer.rut ?? "").contains(rutQuery)
        }
        List(filtered) { customer in
            NavigationLink {
                CustomerDetailScreen(customerId: customer.id, sellerId: sellerId)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(customer.displayName)
                    }
                    if let phone = customer.phone { Text(phone).font(.caption).foregroundStyle(.secondary) }
                }
            }
        }
        .searchable(text: $searchText, prompt: "Nombre, RUT o teléfono")
        .overlay {
            if customers.isEmpty {
                ContentUnavailableView("Sin clientes", systemImage: "person.2")
            } else if filtered.isEmpty {
                ContentUnavailableView.search(text: searchText)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { creating = true } label: { Label("Nuevo cliente", systemImage: "person.badge.plus") }
            }
        }
        .sheet(isPresented: $creating) {
            NavigationStack {
                CustomerForm(sellerId: sellerId, customer: nil) { _ in creating = false }
                    .navigationTitle("Nuevo cliente")
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { creating = false } } }
            }
        }
    }
}

/// Formulario de cliente compartido entre lista y detalle (§10 CustomerForm).
struct CustomerForm: View {
    @Environment(LocalStore.self) private var store
    let sellerId: String
    let customer: Customer?
    let onSaved: (String) -> Void
    @State private var name = ""
    @State private var rut = ""
    @State private var phone = ""
    @State private var notes = ""
    @State private var errorMessage: String?
    @State private var saved = false

    var body: some View {
        Form {
            Section("Ficha") {
                TextField("Nombre", text: $name).textContentType(.name)
                TextField("RUT", text: $rut).keyboardType(.asciiCapable).textInputAutocapitalization(.characters)
                TextField("Teléfono", text: $phone).keyboardType(.phonePad).textContentType(.telephoneNumber)
                TextField("Notas", text: $notes, axis: .vertical)
            }
            if let errorMessage { Section { AlertBanner(errorMessage, tone: .danger) } }
            if saved { Section { AlertBanner("Cliente guardado.", tone: .success, systemImage: "checkmark.circle.fill") } }
            Section {
                Button("Guardar", action: save).disabled(!CustomerRules.isValidName(name))
            }
        }
        .onAppear {
            guard let customer else { return }
            name = customer.displayName
            rut = customer.rut ?? ""
            phone = customer.phone ?? ""
            notes = customer.notes ?? ""
        }
    }

    private func save() {
        switch store.saveCustomer(sellerId: sellerId, customerId: customer?.id, name: name, rut: rut, phone: phone, notes: notes) {
        case .success(let id):
            errorMessage = nil
            saved = true
            Haptics.success()
            onSaved(id)
        case .failure(let error):
            errorMessage = error.message
        }
    }
}

/// Ficha del cliente + sus pedidos y su historial de compras (etapa 10).
struct CustomerDetailScreen: View {
    @Query private var customers: [Customer]
    @Query private var orders: [CustomerOrder]
    @Query private var sales: [LocalSale]
    let customerId: String
    let sellerId: String

    init(customerId: String, sellerId: String) {
        self.customerId = customerId
        self.sellerId = sellerId
        _customers = Query(filter: #Predicate<Customer> { $0.id == customerId })
        _orders = Query(filter: #Predicate<CustomerOrder> { $0.customerId == customerId }, sort: \.orderedAt, order: .reverse)
        _sales = Query(filter: #Predicate<LocalSale> { $0.sellerId == sellerId }, sort: \.occurredAt, order: .reverse)
    }

    var body: some View {
        if let customer = customers.first {
            let customerSales = sales.filter {
                $0.customerId == customer.id || Normalize.customerName($0.customerName ?? "") == customer.normalizedName
            }
            List {
                Section {
                    NavigationLink("Editar ficha") {
                        CustomerForm(sellerId: sellerId, customer: customer) { _ in }.navigationTitle("Editar cliente")
                    }
                    if let rut = customer.rut { LabeledContent("RUT", value: rut) }
                    if let phone = customer.phone { LabeledContent("Teléfono", value: phone) }
                    if let notes = customer.notes { Text(notes).font(.footnote).foregroundStyle(.secondary) }
                }
                Section("Pedidos (\(orders.count))") {
                    if orders.isEmpty { Text("Sin pedidos").foregroundStyle(.secondary) }
                    ForEach(orders) { order in
                        NavigationLink {
                            CustomerOrderEditor(sellerId: sellerId, orderId: order.id)
                        } label: {
                            CustomerOrderRow(order: order)
                        }
                    }
                }
                Section("Compras (\(customerSales.count)) · \(customerSales.reduce(Money.zero) { $0 + $1.total }.formatted)") {
                    if customerSales.isEmpty { Text("Sin compras registradas").foregroundStyle(.secondary) }
                    ForEach(customerSales) { sale in
                        SaleRow(sale: sale, reasonLabels: [:], sellerId: sellerId)
                    }
                }
            }
            .navigationTitle(customer.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .mainToolbar(sellerId: sellerId)
        } else {
            ContentUnavailableView("Cliente no encontrado", systemImage: "person")
        }
    }
}

/// Selector de cliente para el carro (opcional).
struct CustomerPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var customers: [Customer]
    @State private var searchText = ""
    let onPick: (Customer?) -> Void

    init(sellerId: String, onPick: @escaping (Customer?) -> Void) {
        self.onPick = onPick
        _customers = Query(filter: #Predicate<Customer> { $0.sellerId == sellerId }, sort: \.displayName)
    }

    var body: some View {
        NavigationStack {
            let query = Normalize.customerName(searchText)
            List {
                Button("Sin cliente") { onPick(nil); dismiss() }
                ForEach(customers.filter { query.isEmpty || $0.normalizedName.contains(query) }) { customer in
                    Button(customer.displayName) { onPick(customer); dismiss() }
                }
            }
            .searchable(text: $searchText, prompt: "Buscar cliente")
            .navigationTitle("Cliente")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } } }
        }
    }
}
