import Core
import SwiftUI

/// Ajustes › Voz (docs/voice-interaction-proposal.md §6): reúne los interruptores que estaban repartidos en las hojas.
struct VoiceSettingsScreen: View {
    @AppStorage("voice.allowServerRecognition") private var allowServer = false
    @AppStorage("voice.spokenAnswers") private var spokenAnswers = true
    @AppStorage("voice.receivingContinuous") private var receivingContinuous = false
    @AppStorage("voice.logUnrecognized") private var logUnrecognized = false
    @State private var phrases: [UnrecognizedPhrases.Entry] = []

    var body: some View {
        List {
            Section {
                Toggle("Permitir servidores de Apple", isOn: $allowServer)
            } footer: {
                Text("Si el iPhone no tiene reconocimiento de voz local en español, el audio se envía a Apple para transcribirlo. Apagado, la voz solo funciona cuando hay modelo local.")
            }
            Section {
                Toggle("Leer respuestas en voz alta", isOn: $spokenAnswers)
                Toggle("Recepción sin manos al abrir el dictado", isOn: $receivingContinuous)
            } footer: {
                Text("Sin manos: en Recepción, el dictado escucha seguido; di cada producto y haz una pausa.")
            }
            Section {
                Toggle("Guardar frases no entendidas", isOn: $logUnrecognized)
                ForEach(Array(phrases.enumerated()), id: \.offset) { _, entry in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("“\(entry.text)”")
                        Text(entry.date.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                    }
                }
                if !phrases.isEmpty {
                    ShareLink("Compartir lista", item: phrases.map(\.text).joined(separator: "\n"))
                    Button("Borrar lista", role: .destructive) {
                        VoicePhraseLog.clear()
                        phrases = []
                    }
                }
            } footer: {
                Text("Solo se guardan en este iPhone (las últimas \(UnrecognizedPhrases.capacity)). Sirven para mejorar lo que la app entiende.")
            }
            Section("Puedes decir") {
                ForEach(Self.examples, id: \.self) { Text($0).font(.callout) }
            }
        }
        .navigationTitle("Voz")
        .onAppear { phrases = VoicePhraseLog.entries }
    }

    static let examples = [
        "¿Cuánto me queda de Kaiak?",
        "¿Qué me encargó Juan?",
        "¿Cuánto vendí esta semana?",
        "¿Cuándo cierra el ciclo?",
        "¿Cuánto crédito tengo? · ¿Cuándo vence mi pago?",
        "Ir a recepción · Abre la revista · Muéstrame las ofertas",
        "Abre el pedido de María · Abre el pedido del ciclo",
    ]
}
