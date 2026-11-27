import Core
import DesignSystem
import Persistence
import SwiftData
import SwiftUI
import Store

/// Consultas por voz desde cualquier pantalla (V4 de docs/voice-interaction-proposal.md):
/// stock, encargos de un cliente, ventas de un periodo y ciclo. Responde en pantalla y, si se quiere, en voz alta.
/// Solo lee datos locales: funciona sin conexión.
struct VoiceQuerySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router
    @Environment(LocalStore.self) private var store
    @AppStorage("voice.logUnrecognized") private var logUnrecognized = false
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
                        Text("“¿Cuánto vendí esta semana?” · “¿Cuándo cierra el ciclo?” · “¿Cuánto crédito tengo?” · “¿Cuándo vence mi pago?”")
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
        let answers = CommandGrammar.interpret(question, context: .global).map { resolver.resolve($0) }
        let final = answers.isEmpty ? [VoiceAnswers.notUnderstood(question)] : answers
        exchanges.append(Exchange(question: question, answers: final))
        if spokenAnswers {
            speaker.speak(final.map(\.speech).joined(separator: " "))
        }
        Haptics.tap()
    }

    private var resolver: VoiceQueryResolver {
        VoiceQueryResolver(context: context, sellerId: sellerId, router: router, store: store, logUnrecognized: logUnrecognized,
                           close: { dismiss() })
    }

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
