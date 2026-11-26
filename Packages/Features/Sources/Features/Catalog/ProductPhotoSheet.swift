import Core
import DesignSystem
import Persistence
import PhotosUI
import SwiftData
import SwiftUI
import Sync

/// Foto de un producto → reconocerlo → elegir acción → ejecutar (docs/product-photo-proposal.md).
/// Señales leídas en el iPhone: código de barras, código Natura impreso y nombre de la etiqueta.
/// Cada botón usa las acciones de siempre (offline, con sincronización).
struct ProductPhotoSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(SyncEngine.self) private var sync
    @Environment(AppRouter.self) private var router
    @Query private var products: [CatalogProduct]
    @Query private var stock: [StockItem]
    let sellerId: String

    @State private var showingCamera = false
    @State private var scanning = false
    /// EAN leídos con el escáner que aún no se reconocen: se suman a la foto de la etiqueta para poder asociarlos.
    @State private var scannedBarcodes: [String] = []
    @State private var photoItem: PhotosPickerItem?
    @State private var image: UIImage?
    @State private var analyzing = false
    @State private var reading: PhotoReading?
    @State private var result: RecognitionResult?
    @State private var productId: String?
    @State private var message: (text: String, isError: Bool)?
    @State private var addedToSale = false
    @State private var showingInventory = false
    @State private var counted = 0
    @State private var countNote = ""
    @State private var choosingOrder = false
    @State private var newOrder: NewOrderRequest?
    @State private var creating: CreateRequest?
    @State private var shelfMode = false
    @State private var shelfRows: [ShelfRow] = []
    @State private var speech = SpeechCaptureService()
    @State private var highlighted: String?
    @AppStorage("voice.allowServerRecognition") private var allowServer = false

    /// Fila del inventario de repisa (P3): un producto por foto, con su conteo.
    struct ShelfRow: Identifiable, Equatable {
        let productId: String
        var counted: Int
        var id: String { productId }
    }

    struct NewOrderRequest: Identifiable {
        let productId: String
        var id: String { productId }
    }

    struct CreateRequest: Identifiable {
        let sku: String
        let name: String
        var id: String { sku + "|" + name }
    }

    init(sellerId: String) {
        self.sellerId = sellerId
        _products = Query(filter: #Predicate<CatalogProduct> { $0.sellerId == sellerId }, sort: \.name)
        _stock = Query(filter: #Predicate<StockItem> { $0.sellerId == sellerId })
    }

    private var product: CatalogProduct? {
        guard let productId else { return nil }
        return products.first { $0.id == productId }
    }

    private func available(_ id: String) -> Int {
        stock.first { $0.sellerProductId == id }?.operationalQuantity ?? 0
    }

    var body: some View {
        NavigationStack {
            List {
                captureSection
                if analyzing {
                    Section { ProgressView("Leyendo la foto…") }
                }
                if let reading { readingSection(reading) }
                if let message {
                    Section {
                        AlertBanner(message.text, tone: message.isError ? .danger : .success,
                                    systemImage: message.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        if addedToSale, !message.isError {
                            Button("Ir al carro") {
                                router.tab = .sell
                                dismiss()
                            }
                        }
                    }
                }
                if let product {
                    productCard(product)
                    if !shelfMode { actionsSection(product) }
                } else if let result {
                    unresolvedSection(result)
                }
                if shelfMode { shelfSection }
                if product != nil || !shelfRows.isEmpty { voiceSection }
            }
            .navigationTitle("Foto de producto")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cerrar") { dismiss() } }
            }
            .sheet(isPresented: $scanning) {
                ScannerSheet(title: shelfMode ? "Escanear repisa" : "Escanear código", continuous: shelfMode) { code in
                    handleScan(code)
                }
            }
            .fullScreenCover(isPresented: $showingCamera) {
                CameraPicker(onImage: { picked in
                    showingCamera = false
                    analyze(picked)
                }, onCancel: { showingCamera = false })
                .ignoresSafeArea()
            }
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self), let picked = UIImage(data: data) {
                        analyze(picked)
                    }
                    photoItem = nil
                }
            }
            .sheet(isPresented: $choosingOrder) {
                if let product {
                    CustomerOrderPickerSheet(sellerId: sellerId) { order in
                        choosingOrder = false
                        if let order {
                            add(product, to: order)
                        } else {
                            newOrder = NewOrderRequest(productId: product.id)
                        }
                    }
                }
            }
            .sheet(item: $newOrder) { request in
                NavigationStack {
                    CustomerOrderEditor(sellerId: sellerId, orderId: nil, initialProductId: request.productId)
                }
            }
            .onChange(of: productId) { _, id in
                if shelfMode, let id { addShelfRow(id) }
            }
            .onChange(of: shelfMode) { _, _ in
                productId = nil
                result = nil
                reading = nil
                scannedBarcodes = []
            }
            .onChange(of: speech.lastUtterance) { _, utterance in
                if let utterance { handleVoice(utterance.text) }
            }
            .task { await VoiceModelWarmup.prepare(speech, sellerId: sellerId, context: context) }
            .onDisappear { speech.cancel() }
            .sheet(item: $creating) { request in
                QuickProductSheet(sellerId: sellerId, initialSku: request.sku, initialName: request.name) { id in
                    productId = id
                    message = ("Producto creado.", false)
                }
            }
        }
    }

    // MARK: Secciones

    private var captureSection: some View {
        Section {
            Toggle("Inventario de repisa (foto a foto)", isOn: $shelfMode)
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 160)
                    .frame(maxWidth: .infinity)
                    .accessibilityHidden(true)
            }
            if BarcodeScannerView.isAvailable {
                Button { scanning = true } label: {
                    Label(shelfMode ? "Escanear repisa" : "Escanear código de barras", systemImage: "barcode.viewfinder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(analyzing)
            }
            HStack {
                if CameraPicker.isAvailable {
                    Button { showingCamera = true } label: {
                        Label("Foto de la etiqueta", systemImage: "camera")
                    }
                    .buttonStyle(.bordered)
                }
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Label("Elegir foto", systemImage: "photo")
                }
                .buttonStyle(.bordered)
            }
            .disabled(analyzing)
        } footer: {
            Text(shelfMode
                 ? "Escanea cada unidad: cada lectura suma 1 al conteo de su producto. Ajusta con los botones o di “conté siete”, y guarda todo al final."
                 : "El código de barras se lee en vivo, sin foto. Si no tiene código o no lo conozco, toma una foto de la etiqueta. Todo se lee en el iPhone y no se guarda.")
        }
    }

    private var shelfSection: some View {
        Section {
            if shelfRows.isEmpty {
                Text("Toma la foto del primer producto.").foregroundStyle(.secondary)
            }
            ForEach($shelfRows) { $row in
                VStack(alignment: .leading, spacing: 4) {
                    Text(products.first { $0.id == row.productId }?.name ?? row.productId).font(.subheadline.weight(.medium))
                    QuantityStepper("Conteo (sistema \(available(row.productId)))", value: $row.counted, in: 0...9999)
                }
            }
            .onDelete { shelfRows.remove(atOffsets: $0) }
            if !shelfRows.isEmpty {
                Button("Guardar \(shelfRows.count) conciliación(es)") { saveShelf() }
                    .buttonStyle(.borderedProminent)
            }
        } header: {
            Text("Conteo de repisa (\(shelfRows.count))")
        }
    }

    private var voiceSection: some View {
        Section {
            HoldToTalkButton(isListening: speech.isListening, onPress: {
                Task { await speech.start(contextualStrings: [], allowServer: allowServer) }
            }, onRelease: { speech.stop() })
            .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
            if !speech.transcript.isEmpty {
                Text(speech.transcript).font(.footnote)
            }
            if case .failed(let error) = speech.state {
                AlertBanner(error, tone: .warning)
                if !allowServer {
                    Toggle("Permitir reconocimiento en servidores de Apple", isOn: $allowServer)
                }
            }
        } header: {
            Text("Por voz")
        } footer: {
            Text(shelfMode
                 ? "“Conté siete” ajusta el último producto del conteo."
                 : "“Conté siete”, “a la venta”, “al pedido”, “asocia el código”, “recíbelo”, “ver ficha”. Se resalta el botón y tú confirmas.")
        }
    }

    private func readingSection(_ reading: PhotoReading) -> some View {
        Section("Leí") {
            let codes = result?.readCodes ?? []
            if reading.barcodes.isEmpty, codes.isEmpty, result?.labelName == nil {
                Text("No pude leer códigos ni texto. Prueba con más luz o más cerca.")
                    .foregroundStyle(.secondary)
            }
            ForEach(reading.barcodes, id: \.self) { code in
                Label("EAN \(code)", systemImage: "barcode")
            }
            ForEach(codes, id: \.self) { code in
                Label("Código \(code)", systemImage: "number")
            }
            if let name = result?.labelName {
                Label("“\(name)”", systemImage: "text.viewfinder")
            }
        }
        .font(.subheadline)
    }

    private func productCard(_ product: CatalogProduct) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text(product.name).font(.headline)
                HStack(spacing: 6) {
                    Text("SKU \(product.naturaSku)")
                    Text("· Stock \(available(product.id))")
                    if let suggested = product.lastSuggestedSale { Text("· \(suggested.formatted)") }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                if let reasons = result?.candidates.first(where: { $0.id == product.id })?.reasons, !reasons.isEmpty {
                    Text("Reconocido por " + reasons.map(reasonText).joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if (result?.candidates.count ?? 0) > 1 {
                Button("No es este producto") {
                    productId = nil
                    showingInventory = false
                }
                .font(.footnote)
            }
        }
    }

    private func actionsSection(_ product: CatalogProduct) -> some View {
        Section("¿Qué quieres hacer?") {
            ForEach(currentActions(product)) { action in
                actionRow(action, product: product)
                    .listRowBackground(highlighted == action.id ? Color.accentColor.opacity(0.15) : nil)
            }
        }
    }

    private func currentActions(_ product: CatalogProduct) -> [ProductAction] {
        ProductActions.available(for: ProductActionContext(
            isSellable: product.isSellable, available: available(product.id),
            unknownBarcodes: (result?.unknownBarcodes ?? []).filter { !product.barcodes.map(Normalize.ean).contains($0) },
            receiving: receivingOpportunities(for: product)))
    }

    @ViewBuilder
    private func actionRow(_ action: ProductAction, product: CatalogProduct) -> some View {
        switch action {
        case .takeInventory:
            Button {
                counted = available(product.id)
                showingInventory.toggle()
            } label: {
                Label("Tomar inventario", systemImage: "number.square")
            }
            if showingInventory {
                QuantityStepper("Conteo físico", value: $counted, in: 0...9999)
                TextField("Observación", text: $countNote, axis: .vertical)
                Button("Guardar conciliación") { saveInventory(product) }
                    .buttonStyle(.borderedProminent)
            }
        case .linkBarcode(let ean):
            Button { link(ean, to: product) } label: {
                Label("Asociar EAN \(ean)", systemImage: "barcode.viewfinder")
            }
        case .addToSale:
            Button { addToSale(product) } label: {
                Label("Agregar a la venta", systemImage: "cart.badge.plus")
            }
        case .addToCustomerOrder:
            Button { choosingOrder = true } label: {
                Label("Agregar a pedido de cliente", systemImage: "person.badge.plus")
            }
        case .receive(let opportunity):
            Button { receive(opportunity) } label: {
                Label("Recibir +1 en pedido \(opportunity.orderNumber) (faltan \(opportunity.pending))",
                      systemImage: "tray.and.arrow.down")
            }
        case .openDetail:
            NavigationLink {
                ProductDetailScreen(productId: product.id, sellerId: sellerId)
            } label: {
                Label("Ver ficha y kardex", systemImage: "list.bullet.rectangle")
            }
        case .createProduct:
            EmptyView()
        }
    }

    @ViewBuilder
    private func unresolvedSection(_ result: RecognitionResult) -> some View {
        switch result.match {
        case .found:
            EmptyView()
        case .ambiguous(let ids):
            Section {
                ForEach(ids, id: \.self) { id in
                    if let candidate = products.first(where: { $0.id == id }) {
                        Button {
                            productId = id
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(candidate.name).foregroundStyle(.primary)
                                Text("SKU \(candidate.naturaSku) · Stock \(available(id))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } header: {
                Text(ids.count == 1 ? "¿Es este producto?" : "¿Cuál de estos es?")
            }
        case .notFound:
            Section {
                Text(result.labelName == nil && result.readCodes.isEmpty && !result.unknownBarcodes.isEmpty
                     ? "No conozco este código. Toma una foto de la etiqueta para identificarlo, o créalo."
                     : "No encontré este producto en tu catálogo.")
                Button {
                    creating = CreateRequest(sku: result.readCodes.first ?? "", name: result.labelName ?? "")
                } label: {
                    Label("Crear producto", systemImage: "plus.circle")
                }
            } footer: {
                Text("Se prellena con el código y el nombre leídos; puedes corregirlos.")
            }
        }
    }

    private func reasonText(_ reason: RecognitionReason) -> String {
        switch reason {
        case .barcode(let code): "EAN \(code)"
        case .naturaCode(let code): "código \(code)"
        case .name: "nombre en la etiqueta"
        }
    }

    // MARK: Reconocer

    private func analyze(_ picked: UIImage) {
        image = picked
        analyzing = true
        reading = nil
        result = nil
        productId = nil
        message = nil
        addedToSale = false
        showingInventory = false
        highlighted = nil
        let pendingBarcodes = scannedBarcodes
        scannedBarcodes = []
        Task {
            do {
                let photo = try await PhotoAnalyzer.analyze(picked)
                // Un EAN escaneado antes (y no reconocido) se suma para poder asociarlo al producto de la etiqueta.
                var barcodes = photo.barcodes
                for code in pendingBarcodes where !barcodes.contains(code) { barcodes.append(code) }
                let read = PhotoReading(barcodes: barcodes, textLines: photo.textLines)
                let recognized = ProductRecognizer.recognize(barcodes: read.barcodes, textLines: read.textLines,
                                                             catalog: recognizableCatalog)
                reading = read
                result = recognized
                if case .found(let id) = recognized.match {
                    productId = id
                    Haptics.success()
                } else {
                    Haptics.tap()
                }
            } catch {
                message = ("No pude leer la foto. Intenta de nuevo.", true)
                Haptics.error()
            }
            analyzing = false
        }
    }

    private func receivingOpportunities(for product: CatalogProduct) -> [ReceivingOpportunity] {
        let id = sellerId
        let sku = Normalize.naturaSku(product.naturaSku).lowercased()
        let lines = (try? context.fetch(FetchDescriptor<NaturaOrderLine>(predicate: #Predicate {
            $0.sellerId == id && $0.receivedQuantity < $0.quantity
        }))) ?? []
        let matching = lines.filter { Normalize.naturaSku($0.naturaSku).lowercased() == sku }
        guard !matching.isEmpty else { return [] }
        let orders = (try? context.fetch(FetchDescriptor<NaturaOrder>(predicate: #Predicate { $0.sellerId == id }))) ?? []
        let open = Dictionary(orders.filter { !$0.isClosed }.map { ($0.id, $0.orderNumber) }, uniquingKeysWith: { first, _ in first })
        return matching.compactMap { line in
            guard let number = open[line.orderId] else { return nil }
            return ReceivingOpportunity(orderId: line.orderId, orderNumber: number, lineId: line.id,
                                        pending: line.quantity - line.receivedQuantity)
        }
    }

    private var recognizableCatalog: [RecognizableProduct] {
        products.map { RecognizableProduct(id: $0.id, name: $0.name, sku: $0.naturaSku, barcodes: $0.barcodes) }
    }

    /// Lectura en vivo del escáner: sin foto. Un código de 5–7 dígitos también se prueba como código Natura.
    private func handleScan(_ code: String) {
        let recognized = ProductRecognizer.recognize(barcodes: [code], textLines: [code], catalog: recognizableCatalog)
        if shelfMode {
            if case .found(let id) = recognized.match {
                addShelfRow(id)
                Haptics.success()
            } else {
                message = ("No conozco el código \(code). Sal del modo repisa para identificarlo con una foto.", true)
                Haptics.error()
            }
            return
        }
        image = nil
        highlighted = nil
        showingInventory = false
        addedToSale = false
        reading = PhotoReading(barcodes: [code], textLines: [])
        result = recognized
        switch recognized.match {
        case .found(let id):
            productId = id
            message = nil
            scannedBarcodes = []
            Haptics.success()
        case .ambiguous:
            productId = nil
            message = nil
            Haptics.tap()
        case .notFound:
            productId = nil
            scannedBarcodes = [code]
            message = ("No conozco el código \(code). Toma una foto de la etiqueta para identificar el producto y asociarlo.", true)
            Haptics.error()
        }
    }

    // MARK: Inventario de repisa y voz (P3)

    /// Cada lectura del producto suma 1 a su conteo (la primera crea la fila).
    private func addShelfRow(_ id: String) {
        let name = products.first { $0.id == id }?.name ?? id
        if let index = shelfRows.firstIndex(where: { $0.productId == id }) {
            shelfRows[index].counted = min(shelfRows[index].counted + 1, 9999)
            message = ("\(name): \(shelfRows[index].counted).", false)
            return
        }
        shelfRows.append(ShelfRow(productId: id, counted: 1))
        message = ("Agregado al conteo: \(name) = 1. Sigue escaneando o ajusta.", false)
    }

    private func saveShelf() {
        for row in shelfRows {
            sync.createReconciliation(sellerId: sellerId, productId: row.productId, counted: row.counted,
                                      note: "Inventario por foto")
        }
        message = ("Guardadas \(shelfRows.count) conciliación(es).", false)
        shelfRows = []
        Haptics.success()
    }

    /// La voz elige o prepara el botón; ejecutar sigue siendo un toque.
    private func handleVoice(_ text: String) {
        guard let intent = ProductActionVoice.intent(for: text) else {
            message = ("No entendí “\(text)”.", true)
            Haptics.error()
            return
        }
        if shelfMode {
            if case .inventory(let count?) = intent, let index = shelfRows.indices.last {
                shelfRows[index].counted = min(max(count, 0), 9999)
                message = ("Conteo: \(count). Guarda al terminar la repisa.", false)
                Haptics.tap()
            } else {
                message = ("En el conteo de repisa di, por ejemplo, “conté siete”.", true)
            }
            return
        }
        guard let product else {
            message = ("Primero toma la foto del producto.", true)
            return
        }
        guard let action = ProductActionVoice.action(for: intent, in: currentActions(product)) else {
            message = ("Eso no aplica a \(product.name).", true)
            Haptics.error()
            return
        }
        highlighted = action.id
        if case .inventory(let count) = intent {
            counted = min(max(count ?? available(product.id), 0), 9999)
            showingInventory = true
            message = ("Conteo listo: revisa y toca “Guardar conciliación”.", false)
        } else {
            message = ("Toca el botón resaltado para confirmar.", false)
        }
        Haptics.tap()
    }

    // MARK: Acciones (las de siempre)

    private func saveInventory(_ product: CatalogProduct) {
        highlighted = nil
        sync.createReconciliation(sellerId: sellerId, productId: product.id, counted: counted, note: countNote)
        countNote = ""
        showingInventory = false
        message = ("Conciliación guardada: \(product.name) = \(counted).", false)
        Haptics.success()
    }

    private func link(_ ean: String, to product: CatalogProduct) {
        highlighted = nil
        if let error = sync.addBarcode(sellerId: sellerId, productId: product.id, ean: ean) {
            message = (error.message, true)
            Haptics.error()
        } else {
            message = ("EAN \(ean) asociado a \(product.name).", false)
            Haptics.success()
        }
    }

    private func addToSale(_ product: CatalogProduct) {
        highlighted = nil
        if Cart.add(product, available: available(product.id), sellerId: sellerId, context: context) {
            addedToSale = true
            message = ("Agregado a la venta: \(product.name).", false)
            Haptics.success()
        } else {
            message = ("No hay más stock de \(product.name).", true)
            Haptics.error()
        }
    }

    private func add(_ product: CatalogProduct, to order: CustomerOrder) {
        highlighted = nil
        var lines = order.lines ?? []
        if let index = lines.firstIndex(where: { $0.sellerProductId == product.id }) {
            lines[index].quantity += 1
        } else {
            lines.append(CustomerOrderLineSnapshot(
                sellerProductId: product.id, productName: product.name, naturaSku: product.naturaSku, quantity: 1,
                suggestedPesos: product.lastSuggestedSalePesos, finalPesos: nil))
        }
        switch sync.saveCustomerOrder(sellerId: sellerId, orderId: order.id, customerId: order.customerId, newCustomerName: nil,
                                      cycle: order.cycle, status: order.status, note: order.note, lines: lines) {
        case .success:
            message = ("Agregado al pedido de \(order.customerDisplayName).", false)
            Haptics.success()
        case .failure(let error):
            message = (error.message, true)
            Haptics.error()
        }
    }

    private func receive(_ opportunity: ReceivingOpportunity) {
        highlighted = nil
        let lineId = opportunity.lineId
        guard let line = try? context.fetch(FetchDescriptor<NaturaOrderLine>(predicate: #Predicate { $0.id == lineId })).first else {
            return
        }
        let quantity = min(line.receivedQuantity + 1, line.quantity)
        if let error = sync.confirmReceivingLine(sellerId: sellerId, lineId: line.id, quantity: quantity,
                                                 suggestedPesos: line.suggestedPesos) {
            message = (error.message, true)
            Haptics.error()
        } else {
            message = ("Recibido: \(line.productName) \(quantity) / \(line.quantity) (pedido \(opportunity.orderNumber)).", false)
            Haptics.success()
        }
    }
}

/// Elegir un pedido de cliente abierto (borrador o confirmado), o crear uno nuevo.
struct CustomerOrderPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var orders: [CustomerOrder]
    let onPick: (CustomerOrder?) -> Void

    init(sellerId: String, onPick: @escaping (CustomerOrder?) -> Void) {
        self.onPick = onPick
        _orders = Query(filter: #Predicate<CustomerOrder> { $0.sellerId == sellerId }, sort: \.orderedAt, order: .reverse)
    }

    var body: some View {
        NavigationStack {
            List {
                Button {
                    onPick(nil)
                    dismiss()
                } label: {
                    Label("Pedido nuevo…", systemImage: "plus")
                }
                Section("Pedidos abiertos") {
                    let open = orders.filter { $0.status == .draft || $0.status == .confirmed }
                    if open.isEmpty {
                        Text("No hay pedidos en borrador ni confirmados.").foregroundStyle(.secondary)
                    }
                    ForEach(open) { order in
                        Button {
                            onPick(order)
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(order.customerDisplayName).foregroundStyle(.primary)
                                Text("\(CycleCode.label(order.cycle)) · \(order.status.label) · \(order.lineCount) línea(s)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Agregar a pedido")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } } }
        }
    }
}

/// Botón de cámara para abrir la foto de producto.
struct ProductPhotoButton: View {
    let sellerId: String
    @State private var showing = false

    var body: some View {
        Button { showing = true } label: { Image(systemName: "camera.viewfinder") }
            .accessibilityLabel("Foto de producto")
            .sheet(isPresented: $showing) {
                ProductPhotoSheet(sellerId: sellerId)
            }
    }
}
