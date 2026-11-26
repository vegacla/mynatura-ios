import Core
import DesignSystem
import Persistence
import PhotosUI
import SwiftData
import SwiftUI
import Sync

/// Recibir por línea (§4.6): comprobante OCR, asistencia de faltantes y edición por línea.
/// Solo consulta los productos y el stock de los SKU del pedido (no el catálogo completo).
struct ReceiveByLineScreen: View {
    @Query private var orders: [NaturaOrder]
    @Query private var lines: [NaturaOrderLine]
    let orderId: String
    let sellerId: String

    init(orderId: String, sellerId: String) {
        self.orderId = orderId
        self.sellerId = sellerId
        _orders = Query(filter: #Predicate<NaturaOrder> { $0.id == orderId })
        _lines = Query(filter: #Predicate<NaturaOrderLine> { $0.orderId == orderId }, sort: \.position)
    }

    var body: some View {
        ReceiveByLineProducts(order: orders.first, lines: lines, skus: Self.skuVariants(lines), sellerId: sellerId)
            .navigationTitle("Recibir por línea")
            .navigationBarTitleDisplayMode(.inline)
            .syncStatusToolbar(sellerId: sellerId)
    }

    /// SKU de las líneas tal cual y normalizados, para encontrar el producto aunque difiera el formato.
    private static func skuVariants(_ lines: [NaturaOrderLine]) -> [String] {
        var set = Set<String>()
        for line in lines {
            let normalized = Normalize.naturaSku(line.naturaSku)
            set.formUnion([line.naturaSku, normalized, normalized.lowercased(), normalized.uppercased()])
        }
        return set.sorted()
    }
}

/// Productos del catálogo cuyos SKU están en el pedido.
private struct ReceiveByLineProducts: View {
    @Query private var products: [CatalogProduct]
    let order: NaturaOrder?
    let lines: [NaturaOrderLine]
    let sellerId: String

    init(order: NaturaOrder?, lines: [NaturaOrderLine], skus: [String], sellerId: String) {
        self.order = order
        self.lines = lines
        self.sellerId = sellerId
        _products = Query(filter: #Predicate<CatalogProduct> { $0.sellerId == sellerId && skus.contains($0.naturaSku) })
    }

    var body: some View {
        let productIdBySku = Dictionary(products.map { (Normalize.naturaSku($0.naturaSku).lowercased(), $0.id) },
                                        uniquingKeysWith: { first, _ in first })
        ReceiveByLineList(order: order, lines: lines, productIdBySku: productIdBySku,
                          productIds: Array(Set(productIdBySku.values)).sorted(), sellerId: sellerId)
    }
}

/// Lista de recepción con el stock solo de esos productos.
private struct ReceiveByLineList: View {
    @Query private var stock: [StockItem]
    @State private var dictating = false
    let order: NaturaOrder?
    let lines: [NaturaOrderLine]
    let productIdBySku: [String: String]
    let sellerId: String

    init(order: NaturaOrder?, lines: [NaturaOrderLine], productIdBySku: [String: String], productIds: [String], sellerId: String) {
        self.order = order
        self.lines = lines
        self.productIdBySku = productIdBySku
        self.sellerId = sellerId
        _stock = Query(filter: #Predicate<StockItem> { $0.sellerId == sellerId && productIds.contains($0.sellerProductId) })
    }

    var body: some View {
        let stockById = Dictionary(stock.map { ($0.sellerProductId, $0.operationalQuantity) }, uniquingKeysWith: { first, _ in first })
        List {
            if let order {
                if order.isClosed {
                    AlertBanner("Pedido cerrado. Reábrelo para editar.", tone: .info, systemImage: "lock.fill")
                } else {
                    ReceiptCard(order: order, lines: lines, sellerId: sellerId)
                    ShortageCard(order: order, lines: lines, sellerId: sellerId)
                }
                ForEach(lines) { line in
                    let productId = productIdBySku[Normalize.naturaSku(line.naturaSku).lowercased()]
                    ReceivingLineRow(line: line, stock: productId.flatMap { stockById[$0] },
                                     isClosed: order.isClosed, sellerId: sellerId, editable: true)
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .bottomBar) {
                Button { dictating = true } label: { Label("Dictar", systemImage: "mic.fill").labelStyle(.titleAndIcon) }
                    .disabled(order?.isClosed ?? true || lines.isEmpty)
            }
        }
        .sheet(isPresented: $dictating) {
            ReceivingVoiceSheet(lines: lines, sellerId: sellerId)
                .presentationDetents([.medium, .large])
        }
    }
}

/// Fila de línea compartida entre recepción por línea y por código (§10 ReceivingLineRow).
struct ReceivingLineRow: View {
    @Environment(SyncEngine.self) private var sync
    let line: NaturaOrderLine
    let stock: Int?
    let isClosed: Bool
    let sellerId: String
    let editable: Bool
    @State private var quantity = 0
    @State private var salePrice = Money.zero
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(line.productName).font(.subheadline.weight(.medium)).lineLimit(2)
                Spacer()
                Text("\(line.receivedQuantity) / \(line.quantity)")
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(line.receivedQuantity >= line.quantity ? StatusTone.success.color : Color.primary)
            }
            HStack(spacing: 8) {
                Text("SKU \(line.naturaSku)")
                Text("Stock \(stock ?? 0)")
                if let purchase = line.purchasePesos { Text("Compra \(Money(pesos: purchase).formatted)") }
                switch line.syncState {
                case .pending: Image(systemName: "icloud.slash")
                case .failed: Image(systemName: "exclamationmark.icloud.fill").foregroundStyle(StatusTone.danger.color)
                case .synced: EmptyView()
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if editable, !isClosed {
                QuantityStepper("Cantidad a recibir", value: $quantity, in: 0...line.quantity)
                LabeledContent("Precio venta") {
                    MoneyField("Precio venta", money: $salePrice).frame(maxWidth: 140)
                }
                if let proposed = line.proposedSuggestedPesos, proposed != line.suggestedPesos {
                    Text("Propuesta OCR: \(Money(pesos: proposed).formatted)").font(.caption).foregroundStyle(StatusTone.info.color)
                }
                HStack {
                    let shortage = ReceivingRules.shortage(ordered: line.quantity, confirmed: quantity)
                    Text(shortage > 0 ? "Faltante: \(shortage)" : "Completo")
                        .font(.caption)
                        .foregroundStyle(shortage > 0 ? StatusTone.warning.color : StatusTone.success.color)
                    Spacer()
                    Button("Guardar línea", action: save)
                        .buttonStyle(.bordered)
                        .disabled(quantity == line.receivedQuantity && salePrice.pesos == (line.suggestedPesos ?? 0))
                }
                if let errorMessage { AlertBanner(errorMessage, tone: .danger) }
            }
        }
        .padding(.vertical, 4)
        .onAppear(perform: reset)
        .onChange(of: line.receivedQuantity) { _, _ in reset() }
    }

    private func reset() {
        quantity = line.receivedQuantity
        salePrice = Money(pesos: line.suggestedPesos ?? 0)
    }

    private func save() {
        let price = salePrice.pesos > 0 ? salePrice.pesos : nil
        if let error = sync.confirmReceivingLine(sellerId: sellerId, lineId: line.id, quantity: quantity, suggestedPesos: price) {
            errorMessage = error.message
            Haptics.error()
        } else {
            errorMessage = nil
            Haptics.success()
        }
    }
}

/// Tarjeta "Comprobante": foto → OCR → propuestas (solo online).
private struct ReceiptCard: View {
    @Environment(SyncEngine.self) private var sync
    let order: NaturaOrder
    let lines: [NaturaOrderLine]
    let sellerId: String
    @State private var photoItem: PhotosPickerItem?
    @State private var showingCamera = false
    @State private var uploading = false
    @State private var resultMessage: (text: String, isError: Bool)?

    private var proposals: Int {
        lines.filter { $0.proposedReceivedQuantity != nil || $0.proposedSuggestedPesos != nil }.count
    }

    var body: some View {
        Section {
            HStack {
                Text("Comprobante").font(.headline)
                Spacer()
                if let ocr = order.ocrStatus { OcrBadge(status: ocr) }
            }
            if sync.connectivity.isOnline {
                HStack {
                    if DocumentCameraView.isSupported {
                        Button { showingCamera = true } label: { Label("Fotografiar", systemImage: "doc.viewfinder") }
                            .buttonStyle(.bordered)
                    }
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Label("Elegir foto", systemImage: "photo")
                    }
                    .buttonStyle(.bordered)
                    if uploading { ProgressView() }
                }
                .disabled(uploading)
            } else {
                OnlineOnlyNote(text: "El OCR de la boleta requiere conexión.")
            }
            if let resultMessage {
                AlertBanner(resultMessage.text, tone: resultMessage.isError ? .danger : .success)
            }
            if proposals > 0 {
                Button("Aceptar propuestas (\(proposals) línea(s))") {
                    let count = sync.acceptOcrProposals(sellerId: sellerId, orderId: order.id)
                    resultMessage = ("Aplicadas \(count) propuesta(s).", false)
                    Haptics.success()
                }
            }
        } footer: {
            Text("La foto se envía al servidor para leer cantidades y precios. Tú decides qué propuestas aceptar.")
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    await upload(image)
                }
                photoItem = nil
            }
        }
        .fullScreenCover(isPresented: $showingCamera) {
            DocumentCameraView(onImage: { image in
                showingCamera = false
                Task { await upload(image) }
            }, onCancel: { showingCamera = false })
            .ignoresSafeArea()
        }
    }

    private func upload(_ image: UIImage) async {
        guard let jpeg = ImageEncoding.jpeg(from: image) else { return }
        uploading = true
        switch await sync.uploadReceipt(sellerId: sellerId, orderId: order.id, jpeg: jpeg) {
        case .success(let message): resultMessage = (message, false)
        case .failure(let error): resultMessage = (error.message, true)
        }
        uploading = false
    }
}

/// Tarjeta "Asistencia de conciliación": aplica los faltantes al stock.
private struct ShortageCard: View {
    @Environment(SyncEngine.self) private var sync
    let order: NaturaOrder
    let lines: [NaturaOrderLine]
    let sellerId: String
    @State private var confirming = false
    @State private var message: String?

    var body: some View {
        let withShortage = lines.filter { $0.shortage > 0 }
        if !withShortage.isEmpty {
            Section {
                Text("Asistencia de conciliación").font(.headline)
                Text("\(withShortage.count) línea(s) con faltante (\(withShortage.reduce(0) { $0 + $1.shortage }) unidad(es)).")
                    .font(.subheadline)
                Button("Aplicar faltantes al stock") { confirming = true }
                if let message { AlertBanner(message, tone: .success, systemImage: "checkmark.circle.fill") }
            }
            .confirmationDialog("¿Aplicar faltantes al stock?", isPresented: $confirming, titleVisibility: .visible) {
                Button("Aplicar") {
                    if case .success(let count) = sync.applyShortages(sellerId: sellerId, orderId: order.id) {
                        message = "Creadas \(count) conciliación(es)."
                        Haptics.success()
                    }
                }
            } message: {
                Text("Se crea una conciliación por línea con la nota “Faltante confirmado en pedido \(order.orderNumber)”.")
            }
        }
    }
}
