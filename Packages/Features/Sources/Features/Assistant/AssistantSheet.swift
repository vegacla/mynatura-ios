import Core
import DesignSystem
import Persistence
import Store
import SwiftData
import SwiftUI

/// Asistente unificado (docs/unified-assistant-proposal.md, U2–U4): escanear, voz o texto → tarjeta de lo reconocido
/// → acciones que aplican. Convive con las hojas de dictado de cada pantalla y con "Preguntar".
/// La voz elige o prepara; lo que cambia datos se hace con un toque y el resultado queda a la vista.
struct AssistantSheet: View {
    enum Mode: String, CaseIterable { case scan, voice, text }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL
    @Environment(LocalStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(AppProfile.self) private var profile
    @AppStorage("assistant.mode") private var modeRaw = Mode.scan.rawValue
    @AppStorage("voice.allowServerRecognition") private var allowServer = false
    @AppStorage("voice.spokenAnswers") private var spokenAnswers = true
    @AppStorage("voice.logUnrecognized") private var logUnrecognized = false
    @State private var speech = SpeechCaptureService()
    @State private var speaker = VoiceSpeaker()
    @State private var typed = ""
    @State private var active: AssistantEntity?
    @State private var candidates: [AssistantEntity] = []
    @State private var answers: [VoiceAnswer] = []
    @State private var path: [AssistantRoute] = []
    @State private var sharing: SharedText?
    @State private var lastScan: (code: String, at: Date)?
    let sellerId: String

    private var mode: Mode { Mode(rawValue: modeRaw) ?? .scan }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                inputSection
                if !candidates.isEmpty { candidatesSection }
                if let active { entitySection(active) }
                if !answers.isEmpty {
                    Section("Respuestas") {
                        ForEach(Array(answers.suffix(4).reversed().enumerated()), id: \.offset) { _, answer in
                            Label(answer.text, systemImage: "text.bubble")
                        }
                    }
                }
                if active == nil && candidates.isEmpty { helpSection }
            }
            .safeAreaInset(edge: .bottom) {
                if mode == .voice {
                    HoldToTalkButton(isListening: speech.isListening,
                                     onPress: { startListening() }, onRelease: { speech.stop() })
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                        .background(.bar)
                }
            }
            .navigationTitle("Asistente")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Listo") { dismiss() } }
            }
            .navigationDestination(for: AssistantRoute.self) { route in route.destination(sellerId: sellerId) }
            .sheet(item: $sharing) { shared in
                ActivityView(items: [shared.text]) { _ in sharing = nil }.ignoresSafeArea()
            }
            .onChange(of: speech.lastUtterance) { _, utterance in
                if let utterance { handle(utterance.text, scanned: false) }
            }
            .onDisappear {
                speech.cancel()
                speaker.stop()
            }
            .task { await VoiceModelWarmup.prepare(speech, sellerId: sellerId, context: context) }
        }
    }

    // MARK: Secciones

    @ViewBuilder private var inputSection: some View {
        Section {
            Picker("Entrada", selection: $modeRaw) {
                Text("Escanear").tag(Mode.scan.rawValue)
                Text("Voz").tag(Mode.voice.rawValue)
                Text("Texto").tag(Mode.text.rawValue)
            }
            .pickerStyle(.segmented)
            switch mode {
            case .scan:
                if BarcodeScannerView.isAvailable {
                    BarcodeScannerView { code in handleScan(code) }
                        .frame(height: 170)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
                } else {
                    Text("Escáner no disponible: revisa el permiso de cámara, o usa Voz o Texto.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            case .voice:
                Text(speech.transcript.isEmpty ? (speech.isListening ? "Te escucho…" : "Mantén presionado y habla.") : speech.transcript)
                    .foregroundStyle(speech.transcript.isEmpty ? .secondary : .primary)
                if case .failed(let error) = speech.state { AlertBanner(error, tone: .warning) }
            case .text:
                TextField("Producto, cliente, código o pregunta", text: $typed)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.go)
                    .onSubmit {
                        handle(typed, scanned: false)
                        typed = ""
                    }
            }
        }
    }

    private var candidatesSection: some View {
        Section("¿Cuál?") {
            ForEach(candidates, id: \.self) { entity in
                Button(title(of: entity)) {
                    active = entity
                    candidates = []
                }
            }
        }
    }

    @ViewBuilder private func entitySection(_ entity: AssistantEntity) -> some View {
        let actions = AssistantActions.available(for: entity, context: assistantContext(entity))
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text(title(of: entity)).font(.headline)
                if let detail = subtitle(of: entity) {
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(actions.prefix(4)) { action in
                    Button { run(action, on: entity) } label: {
                        Label(action.title, systemImage: action.systemImage)
                            .font(.subheadline)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    .disabled(action.requiresNetwork && !store.connectivity.isOnline)
                }
            }
            if actions.count > 4 {
                Menu {
                    ForEach(actions.dropFirst(4)) { action in
                        Button { run(action, on: entity) } label: { Label(action.title, systemImage: action.systemImage) }
                            .disabled(action.requiresNetwork && !store.connectivity.isOnline)
                    }
                } label: {
                    Label("Más…", systemImage: "ellipsis.circle")
                }
            }
        } header: {
            HStack {
                Text("Reconocido")
                Spacer()
                Button("Limpiar") { self.active = nil }.font(.caption)
            }
        } footer: {
            Text("Di o escribe una acción (“a la venta”, “¿quién lo encargó?”) o escanea otro producto.")
        }
    }

    private var helpSection: some View {
        Section("Puedes") {
            VStack(alignment: .leading, spacing: 6) {
                Text("Escanear un producto o escribir su código")
                Text("Nombrar un producto o un cliente: “Kaiak”, “Ana”")
                Text("Preguntar: “¿cuándo cierra el ciclo?”, “¿cuánto crédito tengo?”, “¿qué tengo que pedir?”")
                Text("Ir a una pantalla: “abre la revista”, “ir a recepción”")
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
    }

    // MARK: Entrada

    private func handleScan(_ code: String) {
        if let lastScan, lastScan.code == code, Date().timeIntervalSince(lastScan.at) < 2 { return }
        lastScan = (code, .now)
        handle(code, scanned: true)
    }

    private func handle(_ input: String, scanned: Bool) {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        // 1. Una acción sobre lo reconocido ("¿y cuánto queda?", "a la venta").
        if !scanned, let active,
           let action = AssistantActions.match(text, in: AssistantActions.available(for: active, context: assistantContext(active))) {
            run(action, on: active)
            return
        }
        // 2. Navegación por voz ("abre la revista").
        let commands = scanned ? [] : CommandGrammar.interpret(text, context: .global)
        if commands.contains(where: { if case .navigate = $0 { true } else { false } }) {
            reply(commands.map { resolver.resolve($0) })
            return
        }
        if !scanned, VoiceText.fold(text).contains("que tengo que pedir") {
            active = .cycle
            run(AssistantActions.action(.cycleWhatToOrder), on: .cycle)
            return
        }
        // 3. Qué es (producto, cliente, ciclo, cuenta, revista).
        switch AssistantResolver.resolve(text, products: productCandidates(), customers: customerCandidates(), barcodes: barcodeIndex()) {
        case .entity(let entity):
            active = entity
            candidates = []
            Haptics.tap()
        case .candidates(let list):
            candidates = list
        case .none:
            if scanned {
                reply([VoiceAnswer(text: "El código \(text) no está en tu catálogo.")])
                Haptics.error()
                return
            }
        }
        // 4. Además, si es una pregunta, se responde.
        let queries = commands.filter { if case .query = $0 { true } else { false } }
        if !queries.isEmpty {
            reply(queries.map { resolver.resolve($0) })
        } else if active == nil && candidates.isEmpty && !scanned {
            if logUnrecognized { VoicePhraseLog.append(text) }
            reply([VoiceAnswers.notUnderstood(text)])
        }
    }

    private func startListening() {
        speaker.stop()
        Task { await speech.start(contextualStrings: vocabulary(), allowServer: allowServer) }
    }

    private func reply(_ new: [VoiceAnswer]) {
        answers.append(contentsOf: new)
        if spokenAnswers, mode == .voice { speaker.speak(new.map(\.speech).joined(separator: " ")) }
    }

    // MARK: Datos

    private var resolver: VoiceQueryResolver {
        VoiceQueryResolver(context: context, sellerId: sellerId, router: router, logUnrecognized: logUnrecognized,
                           close: { dismiss() })
    }

    private func fetch<T: PersistentModel>(_ descriptor: FetchDescriptor<T>) -> [T] {
        (try? context.fetch(descriptor)) ?? []
    }

    private func products() -> [CatalogProduct] {
        let id = sellerId
        return fetch(FetchDescriptor<CatalogProduct>(predicate: #Predicate { $0.sellerId == id }))
    }

    private func customers() -> [Customer] {
        let id = sellerId
        return fetch(FetchDescriptor<Customer>(predicate: #Predicate { $0.sellerId == id }))
    }

    private func productCandidates() -> [VoiceCandidate] {
        products().map { VoiceCandidate(id: $0.id, name: $0.name, code: $0.naturaSku) }
    }

    private func customerCandidates() -> [VoiceCandidate] {
        customers().map { VoiceCandidate(id: $0.id, name: $0.displayName) }
    }

    private func barcodeIndex() -> [String: String] {
        var index: [String: String] = [:]
        for product in products() { for code in product.barcodes { index[Normalize.ean(code)] = product.id } }
        return index
    }

    private func vocabulary() -> [String] {
        VoiceVocabulary.contextualStrings(productNames: products().map(\.name), customerNames: customers().map(\.displayName))
    }

    private func product(_ id: String) -> CatalogProduct? {
        fetch(FetchDescriptor<CatalogProduct>(predicate: #Predicate { $0.id == id })).first
    }

    private func customer(_ id: String) -> Customer? {
        fetch(FetchDescriptor<Customer>(predicate: #Predicate { $0.id == id })).first
    }

    private func stock(_ productId: String) -> Int {
        fetch(FetchDescriptor<StockItem>(predicate: #Predicate { $0.sellerProductId == productId })).first?.operationalQuantity ?? 0
    }

    /// Pedido Natura abierto con una línea de este SKU por recibir.
    private func openReceivingOrder(sku: String) -> NaturaOrder? {
        let id = sellerId
        let normalized = Normalize.naturaSku(sku).lowercased()
        let lines = fetch(FetchDescriptor<NaturaOrderLine>(predicate: #Predicate { $0.sellerId == id }))
            .filter { Normalize.naturaSku($0.naturaSku).lowercased() == normalized && $0.receivedQuantity < $0.quantity }
        let orders = fetch(FetchDescriptor<NaturaOrder>(predicate: #Predicate { $0.sellerId == id }))
            .filter { !$0.isClosed }
        let openIds = Set(orders.map(\.id))
        guard let line = lines.first(where: { openIds.contains($0.orderId) }) else { return nil }
        return orders.first { $0.id == line.orderId }
    }

    private func customerOrders(_ customerId: String) -> [CustomerOrder] {
        fetch(FetchDescriptor<CustomerOrder>(predicate: #Predicate { $0.customerId == customerId },
                                             sortBy: [SortDescriptor(\.orderedAt, order: .reverse)]))
    }

    private func assistantContext(_ entity: AssistantEntity) -> AssistantContext {
        let cycle = store.draftCycle(sellerId: sellerId)
        var result = AssistantContext(isOnline: store.connectivity.isOnline, hasCycle: cycle != nil)
        switch entity {
        case .product(let id):
            guard let product = product(id) else { return result }
            result.stock = stock(id)
            result.isSellable = product.isSellable
            result.hasOpenReceivingLine = openReceivingOrder(sku: product.naturaSku) != nil
            result.hasOffer = product.hasOffer(inCycle: cycle)
        case .customer(let id):
            result.hasPhone = (customer(id)?.phone ?? "").filter(\.isNumber).count >= 8
            result.hasCustomerOrders = !customerOrders(id).isEmpty
        case .cycle, .account, .magazine:
            break
        }
        return result
    }

    private func title(of entity: AssistantEntity) -> String {
        switch entity {
        case .product(let id): product(id)?.name ?? "Producto"
        case .customer(let id): customer(id)?.displayName ?? "Cliente"
        case .cycle: store.draftCycle(sellerId: sellerId).map { CycleCode.label($0) } ?? "Ciclo"
        case .account: "Cuenta Natura"
        case .magazine: "Revista del ciclo"
        }
    }

    private func subtitle(of entity: AssistantEntity) -> String? {
        switch entity {
        case .product(let id):
            guard let product = product(id) else { return nil }
            var parts = ["SKU \(product.naturaSku)", "Stock \(stock(id))"]
            if let price = product.lastSuggestedSalePesos { parts.append(Money(pesos: price).formatted) }
            if product.cycleCode == store.draftCycle(sellerId: sellerId), let points = product.cyclePoints { parts.append("\(points) pts") }
            return parts.joined(separator: " · ")
        case .customer(let id):
            guard let customer = customer(id) else { return nil }
            return [customer.phone, "\(customerOrders(id).count) pedido(s)"].compactMap { $0 }.joined(separator: " · ")
        case .cycle, .account, .magazine:
            return nil
        }
    }

    // MARK: Acciones

    private func run(_ action: AssistantAction, on entity: AssistantEntity) {
        switch (action.id, entity) {
        case (.productStock, .product(let id)):
            let name = product(id)?.name ?? ""
            reply([VoiceAnswers.stock(spoken: name, facts: [VoiceStockFact(name: name, quantity: stock(id))])])
        case (.productAddToSale, .product(let id)):
            guard let product = product(id) else { return }
            if Cart.add(product, available: stock(id), sellerId: sellerId, context: context) {
                reply([VoiceAnswer(text: "Agregué 1 \(product.name) al carro. Cóbralo en Vender.")])
                Haptics.success()
            } else {
                reply([VoiceAnswer(text: "No hay más stock de \(product.name) para agregar.")])
                Haptics.error()
            }
        case (.productReceive, .product(let id)):
            guard let product = product(id), let order = openReceivingOrder(sku: product.naturaSku) else { return }
            switch store.scanReceiving(sellerId: sellerId, orderId: order.id, code: product.naturaSku) {
            case .matched(let name, let received, let ordered):
                reply([VoiceAnswer(text: "Recibido en el pedido \(order.orderNumber): \(name) \(received) de \(ordered).")])
                Haptics.success()
            case .failed(let message):
                reply([VoiceAnswer(text: message)])
                Haptics.error()
            }
        case (.productDetail, .product(let id)):
            path.append(.product(id))
        case (.productWhoOrdered, .product(let id)):
            reply([whoOrdered(id)])
        case (.productPricing, .product(let id)):
            reply([pricing(id)])
        case (.productSalesMonth, .product(let id)):
            reply([salesThisMonth(id)])
        case (.productOffer, .product(let id)):
            reply([offer(id)])
        case (.productAddToDraft, .product(let id)):
            guard let cycle = store.draftCycle(sellerId: sellerId) else { return }
            store.addDraftProduct(sellerId: sellerId, cycle: cycle, productId: id, source: .restock)
            reply([VoiceAnswer(text: "Agregado al pedido del \(CycleCode.label(cycle)), en Reposición.")])
            Haptics.success()
        case (.productShare, .product(let id)):
            guard let product = product(id) else { return }
            var text = "\(product.name) (código \(product.naturaSku))"
            if let price = product.lastSuggestedSalePesos { text += ": \(Money(pesos: price).formatted)" }
            sharing = SharedText(text: text)

        case (.customerPending, .customer(let id)):
            reply([resolver.resolve(.query(.customerOrders(name: customer(id)?.displayName ?? "")))])
        case (.customerLastOrder, .customer(let id)):
            if let order = customerOrders(id).first { path.append(.customerOrder(order.id)) }
        case (.customerNewOrder, .customer):
            path.append(.newCustomerOrder)
        case (.customerPurchases, .customer(let id)):
            reply([purchases(id)])
        case (.customerDetail, .customer(let id)):
            path.append(.customer(id))
        case (.customerSendMagazine, .customer(let id)):
            guard let customer = customer(id), let cycle = store.draftCycle(sellerId: sellerId),
                  let url = NaturaMagazine.viewerURL(cycleCode: cycle, customerCode: profile.customerCode),
                  let link = NaturaMagazine.whatsAppURL(
                      phone: customer.phone ?? "",
                      text: NaturaMagazine.shareMessage(cycleCode: cycle, url: url,
                                                        customerName: customer.displayName.split(separator: " ").first.map(String.init)))
            else { return }
            openURL(link)
        case (.customerWhatsApp, .customer(let id)):
            guard let customer = customer(id),
                  let link = NaturaMagazine.whatsAppURL(phone: customer.phone ?? "", text: "Hola!") else { return }
            openURL(link)
        case (.customerCall, .customer(let id)):
            let digits = (customer(id)?.phone ?? "").filter { $0.isNumber || $0 == "+" }
            if let url = URL(string: "tel:\(digits)") { openURL(url) }

        case (.cycleInfo, _):
            reply([resolver.resolve(.query(.cycle))])
        case (.cycleWhatToOrder, _):
            reply([whatToOrder()])
        case (.cycleOrderDraft, _):
            path.append(.orderDraft)
        case (.cycleOffers, _):
            path.append(.offers)
        case (.cycleMagazine, _), (.magazineOpen, _):
            if let cycle = store.draftCycle(sellerId: sellerId),
               let url = NaturaMagazine.viewerURL(cycleCode: cycle, customerCode: profile.customerCode) {
                openURL(url)
            }
        case (.magazineShare, _):
            if let cycle = store.draftCycle(sellerId: sellerId),
               let url = NaturaMagazine.viewerURL(cycleCode: cycle, customerCode: profile.customerCode) {
                sharing = SharedText(text: NaturaMagazine.shareMessage(cycleCode: cycle, url: url))
            }
        case (.accountCredit, _):
            reply([resolver.resolve(.query(.credit))])
        case (.accountPayments, _):
            reply([resolver.resolve(.query(.payments))])
        case (.accountOpen, _):
            path.append(.account)
        default:
            break
        }
    }

    // MARK: Respuestas locales nuevas (U3)

    private func whoOrdered(_ productId: String) -> VoiceAnswer {
        let id = sellerId
        let open = fetch(FetchDescriptor<CustomerOrder>(predicate: #Predicate { $0.sellerId == id }))
            .filter { $0.status == .draft || $0.status == .confirmed }
        var who: [String: Int] = [:]
        for order in open {
            for line in order.lines ?? [] where line.sellerProductId == productId {
                who[order.customerDisplayName, default: 0] += line.quantity
            }
        }
        let name = product(productId)?.name ?? "este producto"
        guard !who.isEmpty else { return VoiceAnswer(text: "Nadie tiene encargado \(name) en pedidos abiertos.") }
        let list = who.sorted { $0.value > $1.value }.map { "\($0.key) (\($0.value))" }.joined(separator: ", ")
        return VoiceAnswer(text: "\(name) lo encargó: \(list).")
    }

    private func pricing(_ productId: String) -> VoiceAnswer {
        guard let product = product(productId) else { return VoiceAnswer(text: "No encontré el producto.") }
        let cost = product.lastPurchasePesos
        guard let sale = product.lastSuggestedSalePesos, sale > 0 else {
            return VoiceAnswer(text: cost > 0 ? "Lo compraste a \(Money(pesos: cost).formatted). No tengo precio de venta." : "No tengo costo ni precio de venta de \(product.name).")
        }
        guard cost > 0 else { return VoiceAnswer(text: "Lo vendes a \(Money(pesos: sale).formatted). No tengo su costo de compra.") }
        let margin = sale - cost
        let percent = Int((Double(margin) / Double(sale) * 100).rounded())
        return VoiceAnswer(
            text: "Lo compraste a \(Money(pesos: cost).formatted) y lo vendes a \(Money(pesos: sale).formatted): ganas \(Money(pesos: margin).formatted) (\(percent) %).",
            speech: "Lo compraste a \(VoiceAnswers.spoken(Money(pesos: cost))) y lo vendes a \(VoiceAnswers.spoken(Money(pesos: sale))): ganas \(VoiceAnswers.spoken(Money(pesos: margin))), un \(percent) por ciento.")
    }

    private func salesThisMonth(_ productId: String) -> VoiceAnswer {
        let interval = VoicePeriod.thisMonth.interval(containing: .now, calendar: .current)
        let id = sellerId
        let start = interval.start
        let end = interval.end
        let sales = fetch(FetchDescriptor<LocalSale>(predicate: #Predicate {
            $0.sellerId == id && $0.occurredAt >= start && $0.occurredAt < end
        })).filter { $0.kind == .sale }
        var units = 0
        var total = Money.zero
        for sale in sales {
            for line in sale.lines where line.sellerProductId == productId {
                units += line.quantity
                total = total + line.total
            }
        }
        let name = product(productId)?.name ?? "este producto"
        guard units > 0 else { return VoiceAnswer(text: "Este mes no has vendido \(name).") }
        return VoiceAnswer(text: "Este mes vendiste \(units) de \(name) por \(total.formatted).",
                           speech: "Este mes vendiste \(units) de \(name) por \(VoiceAnswers.spoken(total)).")
    }

    private func offer(_ productId: String) -> VoiceAnswer {
        guard let product = product(productId) else { return VoiceAnswer(text: "No encontré el producto.") }
        var parts: [String] = []
        if let text = product.cycleOfferText { parts.append(text) }
        if let points = product.cyclePoints { parts.append("\(points) puntos") }
        if let purchase = product.cyclePurchasePesos { parts.append("compra \(Money(pesos: purchase).formatted)") }
        return VoiceAnswer(text: parts.isEmpty ? "\(product.name) no tiene oferta este ciclo." : "\(product.name): " + parts.joined(separator: " · ") + ".")
    }

    private func purchases(_ customerId: String) -> VoiceAnswer {
        let sales = fetch(FetchDescriptor<LocalSale>(predicate: #Predicate { $0.customerId == customerId })).filter { $0.kind == .sale }
        let name = customer(customerId)?.displayName ?? "Este cliente"
        guard !sales.isEmpty else { return VoiceAnswer(text: "\(name) todavía no tiene compras registradas.") }
        let total = sales.reduce(Money.zero) { $0 + $1.total }
        let last = sales.map(\.occurredAt).max()
        var text = "\(name) te ha comprado \(total.formatted) en \(sales.count) venta(s)"
        if let last { text += "; la última, el \(last.formatted(date: .abbreviated, time: .omitted))" }
        return VoiceAnswer(text: text + ".", speech: "\(name) te ha comprado \(VoiceAnswers.spoken(total)) en \(sales.count) ventas.")
    }

    private func whatToOrder() -> VoiceAnswer {
        guard let cycle = store.draftCycle(sellerId: sellerId) else {
            return VoiceAnswer(text: "No sé el ciclo vigente: trae tus pedidos desde Ajustes › Natura.")
        }
        let lines = store.cycleSuggestions(sellerId: sellerId, cycle: cycle)
        guard !lines.isEmpty else {
            return VoiceAnswer(text: "Con tu stock cubres los encargos confirmados del \(CycleCode.label(cycle)).")
        }
        let shown = lines.prefix(6).map { "\($0.quantity) \($0.name)" }.joined(separator: ", ")
        let more = lines.count > 6 ? " y \(lines.count - 6) más" : ""
        return VoiceAnswer(text: "Para los encargos del \(CycleCode.label(cycle)) te falta pedir: \(shown)\(more). Ábrelo en “Armar pedido”.")
    }
}

private struct SharedText: Identifiable {
    let id = UUID()
    let text: String
}

/// Pantallas que el Asistente abre dentro de su hoja.
enum AssistantRoute: Hashable {
    case product(String)
    case customer(String)
    case customerOrder(String)
    case newCustomerOrder
    case orderDraft
    case offers
    case account

    @MainActor @ViewBuilder
    func destination(sellerId: String) -> some View {
        switch self {
        case .product(let id): ProductDetailScreen(productId: id, sellerId: sellerId)
        case .customer(let id): CustomerDetailScreen(customerId: id, sellerId: sellerId)
        case .customerOrder(let id): CustomerOrderEditor(sellerId: sellerId, orderId: id)
        case .newCustomerOrder: CustomerOrderEditor(sellerId: sellerId, orderId: nil)
        case .orderDraft: NaturaOrderDraftEntry(sellerId: sellerId)
        case .offers: CycleOffersScreen(sellerId: sellerId)
        case .account: NaturaAccountScreen(sellerId: sellerId)
        }
    }
}

/// Botón del Asistente en la toolbar (junto a "Preguntar").
struct AssistantToolbarButton: View {
    let sellerId: String
    @State private var open = false

    var body: some View {
        Button { open = true } label: { Image(systemName: "sparkles") }
            .accessibilityLabel("Asistente")
            .sheet(isPresented: $open) {
                AssistantSheet(sellerId: sellerId)
                    .presentationDetents([.medium, .large])
            }
    }
}
