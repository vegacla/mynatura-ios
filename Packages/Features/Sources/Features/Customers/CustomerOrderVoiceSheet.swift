import Core
import DesignSystem
import SwiftUI

/// Dictado del pedido de cliente (V2 de docs/voice-interaction-proposal.md).
/// La voz propone chips; nada cambia en el pedido hasta tocar "Aplicar".
struct CustomerOrderVoiceSheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("voice.allowServerRecognition") private var allowServer = false
    @State private var speech = SpeechCaptureService()
    @State private var items: [VoiceProposalItem] = []
    @State private var nextId = 0
    @State private var message: String?

    let products: [VoiceCandidate]
    let customers: [VoiceCandidate]
    /// id de producto → "Nombre · SKU".
    let productLabels: [String: String]
    let referenceYear: Int
    let vocabulary: [String]
    let canUndoLastApply: Bool
    let onApply: ([VoiceProposalItem]) -> Void
    let onUndoLastApply: () -> Void

    private var customerNames: [String: String] {
        Dictionary(customers.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
    }

    private var applicableCount: Int { items.filter(\.action.isApplicable).count }

    var body: some View {
        NavigationStack {
            List {
                transcriptSection
                if !items.isEmpty { chipsSection }
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
                examplesSection
            }
            .safeAreaInset(edge: .bottom) {
                HoldToTalkButton(isListening: speech.isListening, onPress: { startListening() }, onRelease: { speech.stop() })
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                    .background(.bar)
            }
            .navigationTitle("Dictar pedido")
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
        }
    }

    // MARK: Secciones

    private var transcriptSection: some View {
        Section {
            if speech.transcript.isEmpty {
                Text(speech.isListening ? "Te escucho…" : "Mantén presionado el botón y dicta el pedido.")
                    .foregroundStyle(.secondary)
            } else {
                Text(speech.transcript)
                    .font(.body)
            }
        } header: {
            HStack {
                Text("Lo que escuché")
                Spacer()
                if speech.usesServer {
                    Label("Servidor de Apple", systemImage: "icloud")
                        .labelStyle(.iconOnly)
                        .accessibilityLabel("Reconocimiento en servidores de Apple")
                }
            }
        }
    }

    private var chipsSection: some View {
        Section {
            ForEach(items) { item in
                chipRow(item)
                    .swipeActions {
                        Button("Quitar", role: .destructive) { remove(item.id) }
                    }
            }
        } header: {
            Text("Lo que entendí")
        } footer: {
            let pending = items.count - applicableCount
            if pending > 0 {
                Text("\(pending) sin resolver: elige una opción o quítalo. Al aplicar se omiten.")
            }
        }
    }

    private var examplesSection: some View {
        Section("Puedes decir") {
            VStack(alignment: .leading, spacing: 6) {
                Text("“Para Ana Rojas, dos del 12345 y un Kaiak clásico”")
                Text("“Otro más” · “Sube a tres el Ekos” · “Quita el Humor”")
                Text("“Nota: entregar el viernes” · “Deshacer”")
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func chipRow(_ item: VoiceProposalItem) -> some View {
        let tone: StatusTone = item.action.isApplicable ? .success : (item.action.choices.isEmpty ? .danger : .warning)
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: item.action.isApplicable ? "checkmark.circle.fill" : "questionmark.circle.fill")
                .foregroundStyle(tone.color)
            VStack(alignment: .leading, spacing: 4) {
                Text(title(for: item.action))
                if let detail = detail(for: item.action) {
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
                if !item.action.choices.isEmpty {
                    Menu("Elegir…") {
                        ForEach(item.action.choices, id: \.self) { id in
                            Button(label(forChoice: id, in: item.action)) { choose(id, for: item.id) }
                        }
                    }
                    .font(.caption.weight(.semibold))
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Textos de los chips

    private func productLabel(_ reference: ProductRef, _ match: VoiceMatch) -> String {
        if case .found(let id) = match, let label = productLabels[id] { return label }
        switch reference {
        case .sku(let code): return "código \(code)"
        case .text(let text): return "“\(text)”"
        }
    }

    private func title(for action: VoiceAction) -> String {
        switch action {
        case .customer(let spoken, let match):
            switch match {
            case .found(let id): return "Cliente: \(customerNames[id] ?? spoken)"
            case .notFound: return "Cliente nuevo: \(spoken)"
            case .ambiguous: return "¿Qué cliente? “\(spoken)”"
            }
        case .cycle(let code):
            return CycleCode.label(code)
        case .keepCycle:
            return "Ciclo actual (sin cambios)"
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
        }
    }

    private func detail(for action: VoiceAction) -> String? {
        switch action {
        case .addLine(_, _, let price, let match):
            if let price, price.isShorthand, case .found = match {
                return "Precio dicho abreviado: revisa que sea \(price.amount.formatted)."
            }
            return detail(for: match)
        case .setQuantity(_, _, let match), .removeLine(_, let match):
            return detail(for: match)
        case .unrecognized:
            return "No lo entendí. Quítalo o dilo de nuevo."
        default:
            return nil
        }
    }

    private func detail(for match: VoiceMatch) -> String? {
        switch match {
        case .found: return nil
        case .ambiguous: return "Hay varios parecidos."
        case .notFound: return "No está en tu catálogo. Agrégalo desde la búsqueda del pedido."
        }
    }

    private func label(forChoice id: String, in action: VoiceAction) -> String {
        if case .customer = action { return customerNames[id] ?? id }
        return productLabels[id] ?? id
    }

    // MARK: Acciones

    private func startListening() {
        message = nil
        Task {
            await speech.start(contextualStrings: vocabulary, allowServer: allowServer)
        }
    }

    private func commit(_ text: String) {
        let commands = CommandGrammar.interpret(text, context: .customerOrder)
        let proposal = VoiceProposalBuilder.build(commands, products: products, customers: customers,
                                                  referenceYear: referenceYear, firstId: nextId)
        nextId += proposal.items.count + 1
        if proposal.undoRequested {
            if !items.isEmpty {
                items.removeLast()
                message = "Quité lo último que dictaste."
            } else if canUndoLastApply {
                onUndoLastApply()
                message = "Deshice el último dictado aplicado."
            } else {
                message = "No hay nada que deshacer."
            }
        }
        items.append(contentsOf: proposal.items)
        if proposal.items.isEmpty, !proposal.undoRequested, !proposal.finishRequested {
            message = "No entendí. Intenta con “dos del 12345” o “un Kaiak clásico”."
        }
        if proposal.items.contains(where: { $0.action.isApplicable }) {
            Haptics.tap()
        } else if !proposal.items.isEmpty {
            Haptics.error()
        }
        if proposal.finishRequested, applicableCount > 0 {
            message = "Listo. Revisa y toca Aplicar."
        }
    }

    private func choose(_ id: String, for itemId: Int) {
        guard let index = items.firstIndex(where: { $0.id == itemId }) else { return }
        items[index].action = items[index].action.resolving(with: id)
        Haptics.tap()
    }

    private func remove(_ itemId: Int) {
        items.removeAll { $0.id == itemId }
    }

    private func apply() {
        speech.cancel()
        onApply(items)
        dismiss()
    }
}
