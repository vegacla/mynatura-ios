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
                    actionsSection(product)
                } else if let result {
                    unresolvedSection(result)
                }
            }
            .navigationTitle("Foto de producto")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cerrar") { dismiss() } }
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
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 160)
                    .frame(maxWidth: .infinity)
                    .accessibilityHidden(true)
            }
            HStack {
                if CameraPicker.isAvailable {
                    Button { showingCamera = true } label: {
                        Label(image == nil ? "Tomar foto" : "Otra foto", systemImage: "camera")
                    }
                    .buttonStyle(.borderedProminent)
                }
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Label("Elegir foto", systemImage: "photo")
                }
                .buttonStyle(.bordered)
            }
            .disabled(analyzing)
        } footer: {
            Text("Apunta al código de barras o a la etiqueta. La foto se lee en el iPhone y no se guarda.")
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
        let actionContext = ProductActionContext(
            isSellable: product.isSellable, available: available(product.id),
            unknownBarcodes: (result?.unknownBarcodes ?? []).filter { !product.barcodes.map(Normalize.ean).contains($0) },
            receiving: receivingOpportunities(for: product))
        return Section("¿Qué quieres hacer?") {
            ForEach(ProductActions.available(for: actionContext)) { action in
                actionRow(action, product: product)
            }
        }
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
                Text("No encontré este producto en tu catálogo.")
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
        Task {
            do {
                let read = try await PhotoAnalyzer.analyze(picked)
                let catalog = products.map {
                    RecognizableProduct(id: $0.id, name: $0.name, sku: $0.naturaSku, barcodes: $0.barcodes)
                }
                let recognized = ProductRecognizer.recognize(barcodes: read.barcodes, textLines: read.textLines, catalog: catalog)
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

    // MARK: Acciones (las de siempre)

    private func saveInventory(_ product: CatalogProduct) {
        sync.createReconciliation(sellerId: sellerId, productId: product.id, counted: counted, note: countNote)
        countNote = ""
        showingInventory = false
        message = ("Conciliación guardada: \(product.name) = \(counted).", false)
        Haptics.success()
    }

    private func link(_ ean: String, to product: CatalogProduct) {
        if let error = sync.addBarcode(sellerId: sellerId, productId: product.id, ean: ean) {
            message = (error.message, true)
            Haptics.error()
        } else {
            message = ("EAN \(ean) asociado a \(product.name).", false)
            Haptics.success()
        }
    }

    private func addToSale(_ product: CatalogProduct) {
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
