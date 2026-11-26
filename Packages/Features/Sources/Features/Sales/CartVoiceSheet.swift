import Core
import DesignSystem
import Persistence
import SwiftData
import SwiftUI

/// Dictado del carro de venta (V5 de docs/voice-interaction-proposal.md): "dos Kaiak a nueve noventa",
/// "para la señora Ana", "quita el Humor". La voz nunca registra la venta: "Aplicar" solo carga el carro,
/// y "Registrar venta" sigue siendo un toque. Si un precio queda bajo el sugerido, el motivo se elige en el carro.
struct CartVoiceSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @AppStorage("voice.allowServerRecognition") private var allowServer = false
    @Query private var products: [CatalogProduct]
    @Query private var stock: [StockItem]
    @Query private var customers: [Customer]
    @State private var speech = SpeechCaptureService()
    @State private var items: [VoiceProposalItem] = []
    @State private var nextId = 0
    @State private var message: String?

    let sellerId: String
    /// Resumen de lo aplicado, para mostrarlo en la pantalla que abrió el dictado.
    let onApplied: (String) -> Void

    init(sellerId: String, onApplied: @escaping (String) -> Void) {
        self.sellerId = sellerId
        self.onApplied = onApplied
        _products = Query(filter: #Predicate<CatalogProduct> { $0.sellerId == sellerId && $0.isSellable }, sort: \.name)
        _stock = Query(filter: #Predicate<StockItem> { $0.sellerId == sellerId })
        _customers = Query(filter: #Predicate<Customer> { $0.sellerId == sellerId }, sort: \.displayName)
    }

    private var productById: [String: CatalogProduct] {
        Dictionary(products.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private var available: [String: Int] {
        Dictionary(stock.map { ($0.sellerProductId, $0.operationalQuantity) }, uniquingKeysWith: { first, _ in first })
    }

    private var productCandidates: [VoiceCandidate] {
        products.map { VoiceCandidate(id: $0.id, name: $0.name, code: $0.naturaSku) }
    }

    private var customerCandidates: [VoiceCandidate] {
        customers.map { VoiceCandidate(id: $0.id, name: $0.displayName) }
    }

    /// Se puede aplicar en el carro: resuelto, con stock y (si es cliente) existente.
    private func isApplicable(_ action: VoiceAction) -> Bool {
        guard action.isApplicable else { return false }
        switch action {
        case .customer(_, .notFound):
            return false
        case .addLine(_, _, _, .found(let id)):
            return (available[id] ?? 0) > 0
        default:
            return true
        }
    }

    private var applicableCount: Int { items.filter { isApplicable($0.action) }.count }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if speech.transcript.isEmpty {
                        Text(speech.isContinuous ? "Te escucho. Haz una pausa entre productos; di “listo” para terminar."
                             : (speech.isListening ? "Te escucho…" : "Mantén presionado y dicta, o toca para hablar sin manos."))
                            .foregroundStyle(.secondary)
                    } else {
                        Text(speech.transcript)
                    }
                } header: {
                    HStack {
                        Text("Lo que escuché")
                        Spacer()
                        if speech.usesCustomModel {
                            Image(systemName: "text.book.closed").accessibilityLabel("Vocabulario propio activo")
                        }
                        if speech.usesServer {
                            Image(systemName: "icloud").accessibilityLabel("Reconocimiento en servidores de Apple")
                        }
                    }
                }
                if !items.isEmpty {
                    Section {
                        ForEach(items) { item in
                            chipRow(item)
                                .swipeActions {
                                    Button("Quitar", role: .destructive) { items.removeAll { $0.id == item.id } }
                                }
                        }
                    } header: {
                        Text("Lo que entendí")
                    } footer: {
                        let pending = items.count - applicableCount
                        if pending > 0 {
                            Text("\(pending) sin resolver o sin stock: al aplicar se omiten.")
                        }
                    }
                }
                if let message {
                    Section { AlertBanner(message, tone: .info, systemImage: "info.circle.fill") }
                }
                if case .failed(let error) = speech.state {
                    Section {
                        AlertBanner(error, tone: .warning)
                        if !allowServer {
                            Toggle("Permitir reconocimiento en servidores de Apple", isOn: $allowServer)
                        }
                    } footer: {
                        Text("Sin esta opción, la voz se reconoce solo en el iPhone y el audio no sale del equipo.")
                    }
                }
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("“Dos Kaiak a nueve noventa”")
                        Text("“Para la señora Ana” · “Otro más” · “Quita el Humor”")
                        Text("“Nota: paga con transferencia”")
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                } header: {
                    Text("Puedes decir")
                } footer: {
                    Text("La venta se registra siempre con el botón “Registrar venta” del carro.")
                }
            }
            .safeAreaInset(edge: .bottom) {
                HoldToTalkButton(isListening: speech.isListening, isContinuous: speech.isContinuous,
                                 onPress: { startListening() }, onRelease: { speech.stop() },
                                 onTap: { toggleContinuous() })
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                    .background(.bar)
            }
            .navigationTitle("Dictar venta")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") {
                        speech.cancel()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Aplicar") { apply() }
                        .disabled(applicableCount == 0)
                }
            }
            .onChange(of: speech.lastUtterance) { _, utterance in
                if let utterance { commit(utterance.text) }
            }
            .onDisappear { speech.cancel() }
            .task { await VoiceModelWarmup.prepare(speech, sellerId: sellerId, context: context) }
        }
    }

    // MARK: Chips

    @ViewBuilder
    private func chipRow(_ item: VoiceProposalItem) -> some View {
        let applicable = isApplicable(item.action)
        let tone: StatusTone = applicable ? .success : (item.action.choices.isEmpty ? .danger : .warning)
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: applicable ? "checkmark.circle.fill" : "questionmark.circle.fill")
                .foregroundStyle(tone.color)
            VStack(alignment: .leading, spacing: 4) {
                Text(title(for: item.action))
                if let detail = detail(for: item.action) {
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
                if !item.action.choices.isEmpty {
                    Menu("Elegir…") {
                        ForEach(item.action.choices, id: \.self) { id in
                            Button(choiceLabel(id, in: item.action)) { choose(id, for: item.id) }
                        }
                    }
                    .font(.caption.weight(.semibold))
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func productLabel(_ reference: ProductRef, _ match: VoiceMatch) -> String {
        if case .found(let id) = match, let product = productById[id] { return product.name }
        switch reference {
        case .sku(let code): return "código \(code)"
        case .text(let text): return "“\(text)”"
        }
    }

    private func choiceLabel(_ id: String, in action: VoiceAction) -> String {
        if case .customer = action { return customers.first { $0.id == id }?.displayName ?? id }
        guard let product = productById[id] else { return id }
        return "\(product.name) · \(available[id] ?? 0) disp."
    }

    private func title(for action: VoiceAction) -> String {
        switch action {
        case .customer(let spoken, let match):
            if case .found(let id) = match, let customer = customers.first(where: { $0.id == id }) {
                return "Cliente: \(customer.displayName)"
            }
            return "Cliente: “\(spoken)”"
        case .addLine(let quantity, let reference, let price, let match):
            var text = "\(quantity) × \(productLabel(reference, match))"
            if let price { text += " a \(price.amount.formatted)" }
            return text
        case .repeatLast(let quantity):
            return "+\(quantity) a la última línea"
        case .setQuantity(let reference, let quantity, let match):
            return "\(productLabel(reference, match)) → \(quantity)"
        case .removeLine(let reference, let match):
            return "Quitar \(productLabel(reference, match))"
        case .note(let text):
            return "Nota: \(text)"
        case .unrecognized(let text):
            return "“\(text)”"
        case .cycle, .keepCycle, .receive, .count:
            return "No aplica en una venta"
        }
    }

    private func detail(for action: VoiceAction) -> String? {
        switch action {
        case .customer(_, .notFound):
            return "No está entre tus clientes. Créalo en Clientes o elige “Sin cliente”."
        case .customer(_, .ambiguous):
            return "Hay varios clientes parecidos."
        case .addLine(let quantity, _, let price, let match):
            switch match {
            case .found(let id):
                let stock = available[id] ?? 0
                if stock <= 0 { return "Sin stock: no se agrega." }
                var notes: [String] = []
                if quantity > stock { notes.append("Hay \(stock) disponibles: se agregan \(stock).") }
                if let price {
                    if price.isShorthand { notes.append("Precio dicho abreviado: revisa que sea \(price.amount.formatted).") }
                    if let suggested = productById[id]?.lastSuggestedSale, price.amount < suggested {
                        notes.append("Bajo el sugerido (\(suggested.formatted)): elige el motivo en el carro.")
                    }
                }
                return notes.isEmpty ? nil : notes.joined(separator: " ")
            case .ambiguous:
                return "Hay varios parecidos."
            case .notFound:
                return "No está entre tus productos vendibles."
            }
        case .setQuantity(_, _, .notFound), .removeLine(_, .notFound):
            return "No está entre tus productos vendibles."
        case .unrecognized:
            return "No lo entendí. Quítalo o dilo de nuevo."
        default:
            return nil
        }
    }

    // MARK: Acciones

    private func startListening() {
        message = nil
        let vocabulary = VoiceVocabulary.contextualStrings(productNames: products.map(\.name),
                                                           customerNames: customers.map(\.displayName))
        Task { await speech.start(contextualStrings: vocabulary, allowServer: allowServer) }
    }

    private func toggleContinuous() {
        if speech.isContinuous {
            speech.stopContinuous()
        } else {
            message = nil
            speech.startContinuous()
        }
    }

    private func commit(_ text: String) {
        let commands = CommandGrammar.interpret(text, context: .cart)
        let proposal = VoiceProposalBuilder.build(commands, products: productCandidates, customers: customerCandidates,
                                                  referenceYear: 0, firstId: nextId)
        nextId += proposal.items.count + 1
        if proposal.undoRequested {
            if items.isEmpty {
                message = "No hay nada que deshacer en este dictado. Edita el carro para cambiar lo ya aplicado."
            } else {
                items.removeLast()
                message = "Quité lo último que dictaste."
            }
        }
        items.append(contentsOf: proposal.items)
        if proposal.items.contains(where: { isApplicable($0.action) }) {
            Haptics.tap()
        } else if !proposal.items.isEmpty {
            Haptics.error()
        }
        if proposal.finishRequested {
            speech.stopContinuous()
            message = applicableCount > 0
                ? "Toca Aplicar para cargar el carro y luego “Registrar venta”."
                : "La venta se registra con el botón del carro."
        }
    }

    private func choose(_ id: String, for itemId: Int) {
        guard let index = items.firstIndex(where: { $0.id == itemId }) else { return }
        items[index].action = items[index].action.resolving(with: id)
        Haptics.tap()
    }

    /// Carga lo dictado en el carro persistido (`CartDraft` + `CartDraftLine`).
    private func apply() {
        speech.cancel()
        let draft = Cart.draft(sellerId: sellerId, context: context)
        let id = sellerId
        let lines = (try? context.fetch(FetchDescriptor<CartDraftLine>(predicate: #Predicate { $0.sellerId == id },
                                                                       sortBy: [SortDescriptor(\.addedAt)]))) ?? []
        let state = VoiceOrderState(
            customerId: draft.customerId, customerName: draft.customerName ?? "", note: draft.note,
            lines: lines.map { VoiceOrderState.Line(productId: $0.productId, quantity: $0.quantity, finalPesos: $0.finalPricePesos) })
        let result = VoiceOrderApplier.apply(items, to: state, customers: customerCandidates,
                                             limits: available, allowsNewCustomer: false)

        let kept = Set(result.state.lines.map(\.productId))
        for line in lines where !kept.contains(line.productId) {
            context.delete(line)
        }
        let existing = Dictionary(lines.map { ($0.productId, $0) }, uniquingKeysWith: { first, _ in first })
        for line in result.state.lines {
            if let current = existing[line.productId] {
                current.quantity = line.quantity
                if let finalPesos = line.finalPesos { current.finalPricePesos = finalPesos }
            } else if let product = productById[line.productId] {
                let price = line.finalPesos ?? product.lastSuggestedSalePesos ?? product.lastPurchasePesos
                context.insert(CartDraftLine(sellerId: sellerId, productId: product.id, quantity: line.quantity,
                                             finalPricePesos: price))
            }
        }
        if let customerId = result.state.customerId, customerId != draft.customerId {
            draft.customerId = customerId
            draft.customerName = result.state.customerName
        }
        draft.note = result.state.note
        try? context.save()

        var summary = "Dictado aplicado al carro: \(result.applied) cambio(s)."
        if result.capped > 0 { summary += " \(result.capped) ajustado(s) al stock." }
        if result.outOfStock > 0 { summary += " \(result.outOfStock) sin stock." }
        let unresolved = result.skipped - result.outOfStock
        if unresolved > 0 { summary += " \(unresolved) sin resolver." }
        Haptics.success()
        onApplied(summary)
        dismiss()
    }
}
