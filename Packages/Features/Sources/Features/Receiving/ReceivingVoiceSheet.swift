import Core
import DesignSystem
import Persistence
import SwiftUI
import Store

/// Recepción dictada (V3 de docs/voice-interaction-proposal.md): "llegaron cuatro del 87654",
/// "del Kaiak llegaron dos, falta uno", "llegó completo el Ekos". Con un toque escucha sin manos
/// mientras se abren las cajas. Nada se guarda hasta tocar "Aplicar".
struct ReceivingVoiceSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(LocalStore.self) private var store
    @Environment(\.modelContext) private var context
    @AppStorage("voice.allowServerRecognition") private var allowServer = false
    @State private var speech = SpeechCaptureService()
    @State private var items: [VoiceProposalItem] = []
    @State private var nextId = 0
    @State private var message: String?
    @State private var errors: [String] = []

    let lines: [NaturaOrderLine]
    let sellerId: String

    private var candidates: [VoiceCandidate] {
        lines.map { VoiceCandidate(id: $0.id, name: $0.productName, code: $0.naturaSku) }
    }

    private var linesById: [String: NaturaOrderLine] {
        Dictionary(lines.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private var current: [VoiceReceivingLine] {
        lines.map { VoiceReceivingLine(id: $0.id, ordered: $0.quantity, received: $0.receivedQuantity) }
    }

    private var preview: VoiceReceivingResult {
        VoiceReceivingApplier.apply(items, to: current)
    }

    /// Último producto mencionado, para que "falta uno" u "otro más" sigan con la misma línea.
    private var lastLineId: String? {
        for item in items.reversed() {
            if case .receive(_, _, .found(let id)) = item.action { return id }
        }
        return nil
    }

    var body: some View {
        NavigationStack {
            List {
                transcriptSection
                if !items.isEmpty { chipsSection }
                let changes = changedLines
                if !changes.isEmpty {
                    Section("Quedará así") {
                        ForEach(changes, id: \.id) { change in
                            HStack {
                                Text(linesById[change.id]?.productName ?? change.id).lineLimit(2)
                                Spacer()
                                Text("\(linesById[change.id]?.receivedQuantity ?? 0) → \(change.received) / \(change.ordered)")
                                    .font(.subheadline.monospacedDigit().weight(.semibold))
                            }
                        }
                    }
                }
                if let message {
                    Section { AlertBanner(message, tone: .info, systemImage: "info.circle.fill") }
                }
                ForEach(errors, id: \.self) { error in
                    Section { AlertBanner(error, tone: .danger) }
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
                Section("Puedes decir") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("“Llegaron cuatro del 87654”")
                        Text("“Del Kaiak llegaron dos, falta uno”")
                        Text("“Llegó completo el Ekos” · “Otro más” · “No llegó el 12345”")
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
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
            .navigationTitle("Dictar recepción")
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
                        .disabled(changedLines.isEmpty)
                }
            }
            .onChange(of: speech.lastUtterance) { _, utterance in
                if let utterance { commit(utterance.text) }
            }
            .onDisappear { speech.cancel() }
            .task { await VoiceModelWarmup.prepare(speech, sellerId: sellerId, context: context) }
        }
    }

    private var changedLines: [VoiceReceivingLine] {
        let before = Dictionary(current.map { ($0.id, $0.received) }, uniquingKeysWith: { first, _ in first })
        return preview.lines.filter { before[$0.id] != $0.received }
    }

    // MARK: Secciones

    private var transcriptSection: some View {
        Section {
            if speech.transcript.isEmpty {
                Text(speech.isContinuous ? "Te escucho. Di cada producto y haz una pausa."
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
    }

    private var chipsSection: some View {
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
            let pending = items.filter { !$0.action.isApplicable }.count
            if pending > 0 {
                Text("\(pending) sin resolver: elige la línea o quítalo. Al aplicar se omiten.")
            }
        }
    }

    @ViewBuilder
    private func chipRow(_ item: VoiceProposalItem) -> some View {
        let applicable = item.action.isApplicable
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
                    Menu("Elegir línea…") {
                        ForEach(item.action.choices, id: \.self) { id in
                            Button(linesById[id]?.productName ?? id) { choose(id, for: item.id) }
                        }
                    }
                    .font(.caption.weight(.semibold))
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func lineName(_ reference: ProductRef?, _ match: VoiceMatch) -> String {
        if case .found(let id) = match, let line = linesById[id] { return line.productName }
        switch reference {
        case .sku(let code)?: return "código \(code)"
        case .text(let text)?: return "“\(text)”"
        case nil: return "la última línea"
        }
    }

    private func title(for action: VoiceAction) -> String {
        switch action {
        case .receive(let reference, let amount, let match):
            let name = lineName(reference, match)
            switch amount {
            case .received(let quantity): return "\(name): llegaron \(quantity)"
            case .missing(let missing): return "\(name): faltan \(missing)"
            case .complete: return "\(name): completo"
            case .increment(let extra): return "\(name): +\(extra)"
            }
        case .unrecognized(let text):
            return "“\(text)”"
        default:
            return "No aplica en recepción"
        }
    }

    private func detail(for action: VoiceAction) -> String? {
        switch action {
        case .receive(let reference, let amount, let match):
            switch match {
            case .found(let id):
                guard let line = linesById[id] else { return nil }
                let outcome = VoiceReceivingApplier.target(amount, ordered: line.quantity, received: line.receivedQuantity)
                return outcome.capped ? "Pediste \(line.quantity): se recibe el máximo." : nil
            case .ambiguous:
                return "Hay varias líneas parecidas."
            case .notFound:
                return reference == nil ? "Primero di qué producto." : "No está en este pedido."
            }
        case .unrecognized:
            return "No lo entendí. Quítalo o dilo de nuevo."
        default:
            return nil
        }
    }

    // MARK: Acciones

    private func startListening() {
        message = nil
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

    private var vocabulary: [String] {
        VoiceVocabulary.contextualStrings(productNames: lines.map(\.productName), customerNames: [])
    }

    private func commit(_ text: String) {
        let commands = CommandGrammar.interpret(text, context: .receiving)
        let proposal = VoiceProposalBuilder.build(commands, products: candidates, customers: [], referenceYear: 0,
                                                  firstId: nextId, previousProductId: lastLineId)
        nextId += proposal.items.count + 1
        if proposal.undoRequested {
            if items.isEmpty {
                message = "No hay nada que deshacer."
            } else {
                items.removeLast()
                message = "Quité lo último que dictaste."
            }
        }
        // Solo acciones de recepción; lo demás se muestra como no entendido.
        items.append(contentsOf: proposal.items.map { (item: VoiceProposalItem) -> VoiceProposalItem in
            switch item.action {
            case .receive, .unrecognized: return item
            default: return VoiceProposalItem(id: item.id, action: .unrecognized(text))
            }
        })
        if proposal.items.contains(where: { $0.action.isApplicable }) {
            Haptics.tap()
        } else if !proposal.items.isEmpty {
            Haptics.error()
        }
        if proposal.finishRequested {
            speech.stopContinuous()
            message = "Listo. Revisa y toca Aplicar."
        }
    }

    private func choose(_ id: String, for itemId: Int) {
        guard let index = items.firstIndex(where: { $0.id == itemId }) else { return }
        items[index].action = items[index].action.resolving(with: id)
        Haptics.tap()
    }

    private func apply() {
        speech.cancel()
        errors = []
        var saved = 0
        for change in changedLines {
            guard let line = linesById[change.id] else { continue }
            if let error = store.confirmReceivingLine(sellerId: sellerId, lineId: line.id, quantity: change.received,
                                                     suggestedPesos: line.suggestedPesos) {
                errors.append("\(line.productName): \(error.message)")
            } else {
                saved += 1
            }
        }
        if errors.isEmpty {
            Haptics.success()
            dismiss()
        } else {
            Haptics.error()
            message = "Guardadas \(saved) línea(s); revisa los errores."
            items = []
        }
    }
}
