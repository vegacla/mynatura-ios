import Core
import DesignSystem
import Persistence
import SwiftData
import SwiftUI
import Store

/// Detalle de producto (§4.5): EAN asociados, conciliación física y kardex.
struct ProductDetailScreen: View {
    @Environment(LocalStore.self) private var store
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
                        }
                    }
                    LabeledContent("Precio compra") { MoneyText(product.lastPurchase) }
                    LabeledContent("Precio sugerido") { MoneyText(product.lastSuggestedSale) }
                }
                BarcodesSection(product: product, sellerId: sellerId)
                ReconciliationSection(productId: productId, sellerId: sellerId, stock: stock.first)
                LotsSection(productId: productId)
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
            .mainToolbar(sellerId: sellerId)
        } else {
            ContentUnavailableView("Producto no encontrado", systemImage: "shippingbox")
        }
    }
}

private struct BarcodesSection: View {
    @Environment(LocalStore.self) private var store
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
        if let error = store.addBarcode(sellerId: sellerId, productId: product.id, ean: newEAN) {
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
    @Environment(LocalStore.self) private var store
    let productId: String
    let sellerId: String
    let stock: StockItem?
    @State private var counted = 0
    @State private var note = ""
    @State private var savedMessage: String?
    @Environment(\.modelContext) private var context
    @State private var speech = SpeechCaptureService()
    @State private var voiceMessage: String?
    @AppStorage("voice.allowServerRecognition") private var allowServer = false

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
            HoldToTalkButton(isListening: speech.isListening,
                             onPress: { startDictation() }, onRelease: { speech.stop() })
                .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
            if let voiceMessage {
                Text(voiceMessage).font(.footnote).foregroundStyle(.secondary)
            }
            if case .failed(let error) = speech.state {
                AlertBanner(error, tone: .warning)
                if !allowServer {
                    Toggle("Permitir reconocimiento en servidores de Apple", isOn: $allowServer)
                }
            }
            Text(StockRules.deltaLabel(counted: counted, theoretical: operational))
                .font(.footnote.monospacedDigit())
                .foregroundStyle(counted == operational ? Color.secondary : StatusTone.warning.color)
            Button("Guardar conciliación") {
                store.createReconciliation(sellerId: sellerId, productId: productId, counted: counted, note: note)
                note = ""
                savedMessage = store.connectivity.isOnline ? "Conciliación guardada." : "Conciliación guardada en el iPhone; se sincroniza al volver la red."
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
        .onChange(of: speech.lastUtterance) { _, utterance in
            if let utterance { applyDictation(utterance.text) }
        }
        .onDisappear { speech.cancel() }
        .task { await VoiceModelWarmup.prepare(speech, sellerId: sellerId, context: context) }
    }

    private func startDictation() {
        voiceMessage = nil
        Task { await speech.start(contextualStrings: [], allowServer: allowServer) }
    }

    /// "conté siete" llena el conteo; "nota: …" la observación. Se guarda con el botón, como siempre.
    private func applyDictation(_ text: String) {
        var understood: [String] = []
        for command in CommandGrammar.interpret(text, context: .reconciliation) {
            switch command {
            case .physicalCount(let value):
                counted = min(max(value, 0), 9999)
                understood.append("conteo \(counted)")
            case .note(let noteText):
                note = note.isEmpty ? noteText : note + "\n" + noteText
                understood.append("observación")
            default:
                break
            }
        }
        if understood.isEmpty {
            voiceMessage = "No entendí “\(text)”. Prueba con “conté siete”."
            Haptics.error()
        } else {
            voiceMessage = "Dictado: " + understood.joined(separator: " y ") + ". Revisa y toca Guardar conciliación."
            Haptics.tap()
        }
    }
}

/// Lotes del producto (docs/local-first-migration.md §4): stock por lote, costo y su origen; completar costos pendientes.
private struct LotsSection: View {
    @Environment(LocalStore.self) private var store
    @Query private var lots: [InventoryLotRecord]
    @State private var editingLotId: String?
    @State private var costInput = Money.zero
    @State private var errorMessage: String?

    init(productId: String) {
        _lots = Query(filter: #Predicate<InventoryLotRecord> { $0.productId == productId }, sort: \.receivedAt, order: .reverse)
    }

    var body: some View {
        if !lots.isEmpty {
            Section {
                ForEach(lots) { lot in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(lot.receivedAt.formatted(date: .abbreviated, time: .omitted))
                            Spacer()
                            Text("\(lot.remaining) / \(lot.quantity)").monospacedDigit()
                        }
                        .font(.subheadline)
                        HStack(spacing: 6) {
                            StatusBadge(sourceLabel(lot.source), tone: lot.source == .unknown ? .warning : .neutral)
                            if let cost = lot.unitCost { Text(cost.formatted) } else { Text("Costo pendiente") }
                            if let note = lot.note { Text("· \(note)").lineLimit(1) }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        if lot.source == .unknown {
                            if editingLotId == lot.id {
                                HStack {
                                    MoneyField("Costo unitario", money: $costInput).frame(maxWidth: 140)
                                    Button("Guardar") { complete(lot) }.buttonStyle(.bordered)
                                }
                            } else {
                                Button("Completar costo") {
                                    costInput = .zero
                                    editingLotId = lot.id
                                }
                                .font(.caption)
                            }
                        }
                    }
                }
                if let errorMessage { AlertBanner(errorMessage, tone: .danger) }
            } header: {
                Text("Lotes")
            } footer: {
                Text("Las unidades gratis de Natura entran a costo 0; al salir se valorizan con el precio de compra conocido según el método de costeo.")
            }
        }
    }

    private func sourceLabel(_ source: CostSource) -> String {
        switch source {
        case .purchased: "Comprado"
        case .free: "Gratis Natura"
        case .manual: "Manual"
        case .unknown: "Sin costo"
        }
    }

    private func complete(_ lot: InventoryLotRecord) {
        if let error = store.completeLotCost(lotId: lot.id, unitCost: costInput) {
            errorMessage = error.message
            Haptics.error()
        } else {
            errorMessage = nil
            editingLotId = nil
            Haptics.success()
        }
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
    @Environment(LocalStore.self) private var store
    let sellerId: String
    let onCreated: (String) -> Void
    @State private var sku = ""
    @State private var name = ""
    @State private var errorMessage: String?
    @State private var lookingUp = false

    /// `initialSku` / `initialName`: lo leído en una foto (docs/product-photo-proposal.md), editable.
    init(sellerId: String, initialSku: String = "", initialName: String = "", onCreated: @escaping (String) -> Void) {
        self.sellerId = sellerId
        self.onCreated = onCreated
        _sku = State(initialValue: initialSku)
        _name = State(initialValue: initialName)
    }

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
            let found = await store.lookupMasterProductName(sku: current)
            if current == sku, name.isEmpty, let found { name = found }
            lookingUp = false
        }
    }

    private func create() {
        switch store.quickCreateProduct(sellerId: sellerId, sku: sku, name: name) {
        case .success(let id):
            onCreated(id)
            dismiss()
        case .failure(let error):
            errorMessage = error.message
        }
    }
}
