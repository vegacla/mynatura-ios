import Core
import DesignSystem
import Persistence
import SwiftData
import SwiftUI

/// Consultas por voz desde cualquier pantalla (V4 de docs/voice-interaction-proposal.md):
/// stock, encargos de un cliente, ventas de un periodo y ciclo. Responde en pantalla y, si se quiere, en voz alta.
/// Solo lee datos locales: funciona sin conexión.
struct VoiceQuerySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @AppStorage("voice.allowServerRecognition") private var allowServer = false
    @AppStorage("voice.spokenAnswers") private var spokenAnswers = true
    @State private var speech = SpeechCaptureService()
    @State private var speaker = VoiceSpeaker()
    @State private var exchanges: [Exchange] = []

    let sellerId: String

    struct Exchange: Identifiable {
        let id = UUID()
        let question: String
        let answers: [VoiceAnswer]
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if speech.transcript.isEmpty {
                        Text(speech.isListening ? "Te escucho…" : "Mantén presionado y pregunta.")
                            .foregroundStyle(.secondary)
                    } else {
                        Text(speech.transcript)
                    }
                } header: {
                    HStack {
                        Text("Pregunta")
                        Spacer()
                        if speech.usesCustomModel {
                            Image(systemName: "text.book.closed").accessibilityLabel("Vocabulario propio activo")
                        }
                        if speech.usesServer {
                            Image(systemName: "icloud").accessibilityLabel("Reconocimiento en servidores de Apple")
                        }
                    }
                }
                ForEach(exchanges.reversed()) { exchange in
                    Section {
                        ForEach(Array(exchange.answers.enumerated()), id: \.offset) { _, answer in
                            Label(answer.text, systemImage: "text.bubble")
                        }
                    } header: {
                        Text("“\(exchange.question)”").textCase(nil)
                    }
                }
                if case .failed(let error) = speech.state {
                    Section {
                        AlertBanner(error, tone: .warning)
                        if !allowServer {
                            Toggle("Permitir reconocimiento en servidores de Apple", isOn: $allowServer)
                        }
                    }
                }
                Section {
                    Toggle("Leer respuestas en voz alta", isOn: $spokenAnswers)
                } footer: {
                    Text("Las respuestas salen de los datos guardados en este iPhone, también sin conexión.")
                }
                Section("Puedes preguntar") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("“¿Cuánto me queda de Kaiak?”")
                        Text("“¿Qué me encargó Juan?”")
                        Text("“¿Cuánto vendí esta semana?” · “¿Cuándo cierra el ciclo?”")
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
            }
            .safeAreaInset(edge: .bottom) {
                HoldToTalkButton(isListening: speech.isListening,
                                 onPress: { startListening() }, onRelease: { speech.stop() })
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                    .background(.bar)
            }
            .navigationTitle("Preguntar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Listo") { dismiss() }
                }
            }
            .onChange(of: speech.lastUtterance) { _, utterance in
                if let utterance { answer(utterance.text) }
            }
            .onChange(of: spokenAnswers) { _, enabled in
                if !enabled { speaker.stop() }
            }
            .onDisappear {
                speech.cancel()
                speaker.stop()
            }
            .task { await VoiceModelWarmup.prepare(speech, sellerId: sellerId, context: context) }
        }
    }

    private func startListening() {
        speaker.stop()
        Task { await speech.start(contextualStrings: vocabulary(), allowServer: allowServer) }
    }

    private func answer(_ question: String) {
        let answers = CommandGrammar.interpret(question, context: .global).map { resolve($0) }
        let final = answers.isEmpty ? [VoiceAnswers.notUnderstood(question)] : answers
        exchanges.append(Exchange(question: question, answers: final))
        if spokenAnswers {
            speaker.speak(final.map(\.speech).joined(separator: " "))
        }
        Haptics.tap()
    }

    private func resolve(_ command: VoiceCommand) -> VoiceAnswer {
        guard case .query(let query) = command else {
            if case .unrecognized(let text) = command { return VoiceAnswers.notUnderstood(text) }
            return VoiceAnswers.notUnderstood("")
        }
        switch query {
        case .stock(let reference):
            return stockAnswer(reference)
        case .customerOrders(let name):
            return customerOrdersAnswer(name)
        case .sales(let period):
            return salesAnswer(period)
        case .cycle:
            return cycleAnswer()
        }
    }

    // MARK: Datos locales

    private func fetch<T: PersistentModel>(_ descriptor: FetchDescriptor<T>) -> [T] {
        (try? context.fetch(descriptor)) ?? []
    }

    private func vocabulary() -> [String] {
        let id = sellerId
        let products = fetch(FetchDescriptor<CatalogProduct>(predicate: #Predicate { $0.sellerId == id }))
        let customers = fetch(FetchDescriptor<Customer>(predicate: #Predicate { $0.sellerId == id }))
        return VoiceVocabulary.contextualStrings(productNames: products.map(\.name),
                                                 customerNames: customers.map(\.displayName))
    }

    private func stockAnswer(_ reference: ProductRef) -> VoiceAnswer {
        let id = sellerId
        let products = fetch(FetchDescriptor<CatalogProduct>(predicate: #Predicate { $0.sellerId == id }))
        let candidates = products.map { VoiceCandidate(id: $0.id, name: $0.name, code: $0.naturaSku) }
        let chosen: [String]
        switch ProductMatcher.resolve(reference, in: candidates) {
        case .found(let found): chosen = [found]
        case .ambiguous(let options): chosen = options
        case .notFound: chosen = []
        }
        let stock = fetch(FetchDescriptor<StockItem>(predicate: #Predicate { $0.sellerId == id }))
        let quantities = Dictionary(stock.map { ($0.sellerProductId, $0.operationalQuantity) }, uniquingKeysWith: { first, _ in first })
        let names = Dictionary(products.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        let facts = chosen.map { VoiceStockFact(name: names[$0] ?? $0, quantity: quantities[$0] ?? 0) }
        return VoiceAnswers.stock(spoken: spokenText(reference), facts: facts)
    }

    private func customerOrdersAnswer(_ name: String) -> VoiceAnswer {
        let id = sellerId
        let customers = fetch(FetchDescriptor<Customer>(predicate: #Predicate { $0.sellerId == id }))
        let candidates = customers.map { VoiceCandidate(id: $0.id, name: $0.displayName) }
        let match = CustomerMatcher.resolve(name: name, in: candidates)
        let names = Dictionary(customers.map { ($0.id, $0.displayName) }, uniquingKeysWith: { first, _ in first })
        guard case .found(let customerId) = match else {
            let ambiguous: [String]
            if case .ambiguous(let options) = match { ambiguous = options.compactMap { names[$0] } } else { ambiguous = [] }
            return VoiceAnswers.customerOrders(spoken: name, match: match, customerName: nil, orders: [],
                                               ambiguousNames: ambiguous)
        }
        let orders = fetch(FetchDescriptor<CustomerOrder>(predicate: #Predicate { $0.customerId == customerId },
                                                          sortBy: [SortDescriptor(\.orderedAt)]))
        let pending = orders.filter { $0.status == .draft || $0.status == .confirmed }
        let facts = pending.map { order in
            VoiceOrderFact(cycle: order.cycle,
                           lines: (order.lines ?? []).map { VoiceStockFact(name: $0.productName, quantity: $0.quantity) })
        }
        return VoiceAnswers.customerOrders(spoken: name, match: match, customerName: names[customerId], orders: facts)
    }

    private func salesAnswer(_ period: VoicePeriod) -> VoiceAnswer {
        let interval = period.interval(containing: .now, calendar: .current)
        let id = sellerId
        let start = interval.start
        let end = interval.end
        let sales = fetch(FetchDescriptor<LocalSale>(predicate: #Predicate {
            $0.sellerId == id && $0.occurredAt >= start && $0.occurredAt < end
        })).filter { $0.syncState != .failed && $0.kind == .sale }
        let total = sales.reduce(Money.zero) { $0 + $1.total }
        return VoiceAnswers.sales(period: period, count: sales.count, total: total)
    }

    private func cycleAnswer() -> VoiceAnswer {
        let id = sellerId
        let customerCycles = fetch(FetchDescriptor<CustomerOrder>(predicate: #Predicate { $0.sellerId == id })).map(\.cycle)
        let naturaCycles = fetch(FetchDescriptor<NaturaOrder>(predicate: #Predicate { $0.sellerId == id })).map(\.cycle)
        let latest = (customerCycles + naturaCycles).filter { $0 >= 10_000 }.max()
        return VoiceAnswers.cycle(latestKnown: latest)
    }

    private func spokenText(_ reference: ProductRef) -> String {
        switch reference {
        case .sku(let code): "código \(code)"
        case .text(let text): text
        }
    }
}

/// Botón "Preguntar" de la toolbar: abre las consultas por voz.
struct VoiceQueryToolbarButton: View {
    let sellerId: String
    @State private var asking = false

    var body: some View {
        Button {
            asking = true
        } label: {
            Image(systemName: "mic.circle")
        }
        .accessibilityLabel("Preguntar por voz")
        .sheet(isPresented: $asking) {
            VoiceQuerySheet(sellerId: sellerId)
                .presentationDetents([.medium, .large])
        }
    }
}
