import Core
import DesignSystem
import Persistence
import SwiftData
import SwiftUI
import Sync

/// Detalle de producto (§4.5): EAN asociados, conciliación física y kardex.
struct ProductDetailScreen: View {
    @Environment(SyncEngine.self) private var sync
    @Query private var products: [CatalogProduct]
    @Query private var stock: [StockItem]
    @Query private var events: [InventoryEventRecord]
    let productId: String
    let sellerId: String

    init(productId: String, sellerId: String) {
        self.productId = productId
        self.sellerId = sellerId
        _products = Query(filter: #Predicate<CatalogProduct> { $0.id == productId })
        _stock = Query(filter: #Predicate<StockItem> { $0.sellerProductId == productId })
        _events = Query(filter: #Predicate<InventoryEventRecord> { $0.sellerProductId == productId })
    }

    var body: some View {
        if let product = products.first {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(product.name).font(.headline)
                        HStack(spacing: 6) {
                            Text("SKU \(product.naturaSku)").font(.subheadline).foregroundStyle(.secondary)
                            SellableBadge(isSellable: product.isSellable)
                            StatusBadge(product.source.label)
                            if product.syncState == .pending { StatusBadge("Pendiente", tone: .warning) }
                        }
                    }
                    LabeledContent("Precio compra") { MoneyText(product.lastPurchase) }
                    LabeledContent("Precio sugerido") { MoneyText(product.lastSuggestedSale) }
                }
                BarcodesSection(product: product, sellerId: sellerId)
                ReconciliationSection(productId: productId, sellerId: sellerId, stock: stock.first)
                Section("Kardex") {
                    let rows = Kardex.rows(events.map(\.kardexEntry))
                    if rows.isEmpty {
                        Text("Sin movimientos").foregroundStyle(.secondary)
                    } else {
                        KardexHeader()
                        ForEach(rows.reversed()) { row in KardexRowView(row: row) }
                    }
                }
            }
            .navigationTitle("Producto")
            .navigationBarTitleDisplayMode(.inline)
            .syncStatusToolbar(sellerId: sellerId)
        } else {
            ContentUnavailableView("Producto no encontrado", systemImage: "shippingbox")
        }
    }
}

private struct BarcodesSection: View {
    @Environment(SyncEngine.self) private var sync
    let product: CatalogProduct
    let sellerId: String
    @State private var newEAN = ""
    @State private var errorMessage: String?
    @State private var scanning = false

    var body: some View {
        Section("EAN asociados") {
            if product.barcodes.isEmpty {
                Text("Sin EAN").foregroundStyle(.secondary)
            }
            ForEach(product.barcodes, id: \.self) { ean in
                Text(ean).monospacedDigit()
            }
            HStack {
                TextField("Agregar EAN", text: $newEAN)
                    .keyboardType(.numberPad)
                    .onSubmit(add)
                ScannerButton { scanning = true }
                Button("Agregar", action: add).disabled(newEAN.isEmpty)
            }
            if let errorMessage {
                AlertBanner(errorMessage, tone: .danger)
            }
        }
        .sheet(isPresented: $scanning) {
            ScannerSheet(title: "Escanear EAN", continuous: false) { code in
                newEAN = Normalize.ean(code)
                add()
            }
        }
    }

    private func add() {
        if let error = sync.addBarcode(sellerId: sellerId, productId: product.id, ean: newEAN) {
            errorMessage = error.message
            Haptics.error()
        } else {
            errorMessage = nil
            newEAN = ""
            Haptics.success()
        }
    }
}

private struct ReconciliationSection: View {
    @Environment(SyncEngine.self) private var sync
    let productId: String
    let sellerId: String
    let stock: StockItem?
    @State private var counted = 0
    @State private var note = ""
    @State private var savedMessage: String?

    var body: some View {
        let theoretical = stock?.theoreticalQuantity ?? 0
        let operational = stock?.operationalQuantity ?? 0
        Section {
            HStack(spacing: 8) {
                MiniStat("Teórico", value: "\(theoretical)")
                MiniStat("Operativo", value: "\(operational)")
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
            if let date = stock?.lastReconciledAt {
                LabeledContent("Última conciliación", value: date.formatted(date: .abbreviated, time: .shortened))
            }
            QuantityStepper("Conteo físico", value: $counted, in: 0...9999)
            TextField("Observación", text: $note, axis: .vertical)
            Text(StockRules.deltaLabel(counted: counted, theoretical: operational))
                .font(.footnote.monospacedDigit())
                .foregroundStyle(counted == operational ? Color.secondary : StatusTone.warning.color)
            Button("Guardar conciliación") {
                sync.createReconciliation(sellerId: sellerId, productId: productId, counted: counted, note: note)
                note = ""
                savedMessage = sync.connectivity.isOnline ? "Conciliación guardada." : "Conciliación guardada en el iPhone; se sincroniza al volver la red."
                Haptics.success()
            }
            if let savedMessage {
                AlertBanner(savedMessage, tone: .success, systemImage: "checkmark.circle.fill")
            }
        } header: {
            Text("Conciliación física")
        } footer: {
            Text("El conteo físico pasa a ser el stock operativo. El historial no se pisa: queda como evento propio.")
        }
        .onAppear { counted = operational }
    }
}

private struct KardexHeader: View {
    var body: some View {
        HStack {
            Text("Fecha · Tipo").frame(maxWidth: .infinity, alignment: .leading)
            Text("Ent.").frame(width: 40, alignment: .trailing)
            Text("Sal.").frame(width: 40, alignment: .trailing)
            Text("Saldo").frame(width: 50, alignment: .trailing)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
    }
}

private struct KardexRowView: View {
    let row: KardexRow

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(row.entry.occurredAt.formatted(date: .numeric, time: .omitted))
                    Text(row.entry.kind.label).fontWeight(.medium)
                    if row.entry.isPending { Image(systemName: "icloud.slash").foregroundStyle(.secondary) }
                }
                if let note = row.entry.note {
                    Text(note).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(row.input > 0 ? "\(row.input)" : "").frame(width: 40, alignment: .trailing)
            Text(row.output > 0 ? "\(row.output)" : "").frame(width: 40, alignment: .trailing)
            Text("\(row.balance)").fontWeight(.semibold).frame(width: 50, alignment: .trailing)
        }
        .font(.caption.monospacedDigit())
        .accessibilityElement(children: .combine)
    }
}

/// Creación rápida por SKU (§4.5 toolbar "+"), con autocompletado desde el maestro Natura.
struct QuickProductSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SyncEngine.self) private var sync
    let sellerId: String
    let onCreated: (String) -> Void
    @State private var sku = ""
    @State private var name = ""
    @State private var errorMessage: String?
    @State private var lookingUp = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("SKU Natura", text: $sku)
                        .keyboardType(.asciiCapable)
                        .textInputAutocapitalization(.never)
                        .onSubmit(lookup)
                    HStack {
                        TextField("Nombre", text: $name)
                        if lookingUp { ProgressView() }
                    }
                } footer: {
                    Text("Si el SKU ya existe en tu catálogo, se reutiliza.")
                }
                if let errorMessage {
                    Section { AlertBanner(errorMessage, tone: .danger) }
                }
            }
            .navigationTitle("Producto nuevo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Crear", action: create).disabled(sku.isEmpty) }
            }
            .onChange(of: sku) { _, _ in
                Task {
                    try? await Task.sleep(for: .milliseconds(600))
                    lookup()
                }
            }
        }
    }

    private func lookup() {
        guard name.isEmpty, !sku.isEmpty else { return }
        lookingUp = true
        let current = sku
        Task {
            let found = await sync.lookupMasterProductName(sku: current)
            if current == sku, name.isEmpty, let found { name = found }
            lookingUp = false
        }
    }

    private func create() {
        switch sync.quickCreateProduct(sellerId: sellerId, sku: sku, name: name) {
        case .success(let id):
            onCreated(id)
            dismiss()
        case .failure(let error):
            errorMessage = error.message
        }
    }
}
