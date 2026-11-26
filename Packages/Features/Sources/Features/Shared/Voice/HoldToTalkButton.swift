import SwiftUI

/// Mantener presionado para hablar (§4 de docs/voice-interaction-proposal.md): evita activaciones
/// accidentales y deja claro cuándo la app escucha. Con VoiceOver, un toque empieza y otro termina.
struct HoldToTalkButton: View {
    let isListening: Bool
    let onPress: () -> Void
    let onRelease: () -> Void

    @State private var pressed = false

    var body: some View {
        Label(isListening ? "Escuchando… suelta para terminar" : "Mantén presionado para hablar",
              systemImage: isListening ? "waveform" : "mic.fill")
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(isListening ? Color.red : Color.accentColor, in: Capsule())
            .contentShape(Capsule())
            .scaleEffect(pressed ? 1.03 : 1)
            .animation(.easeOut(duration: 0.15), value: pressed)
            // Distancia 0: empieza al tocar y termina al soltar, aunque el dedo se mueva.
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !pressed else { return }
                        pressed = true
                        onPress()
                    }
                    .onEnded { _ in
                        pressed = false
                        onRelease()
                    }
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(isListening ? "Terminar dictado" : "Dictar")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction {
                if isListening {
                    onRelease()
                } else {
                    onPress()
                }
            }
    }
}
