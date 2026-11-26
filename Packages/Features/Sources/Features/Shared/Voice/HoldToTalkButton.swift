import SwiftUI

/// Botón de voz (§4 de docs/voice-interaction-proposal.md).
/// - Mantener presionado: habla mientras se mantiene; al soltar termina la frase.
/// - Toque corto (si hay `onTap`): pasa a modo continuo, sin manos; otro toque lo termina.
/// Con VoiceOver, la acción del botón alterna empezar y terminar.
struct HoldToTalkButton: View {
    let isListening: Bool
    var isContinuous = false
    let onPress: () -> Void
    let onRelease: () -> Void
    /// Toque corto: entrar o salir del modo continuo. Sin esto, el botón es solo "mantener presionado".
    var onTap: (() -> Void)?

    /// Bajo esta duración, soltar cuenta como toque.
    static let tapThreshold: TimeInterval = 0.35

    @State private var pressedAt: Date?
    @State private var pressStartedContinuous = false

    private var title: String {
        if isContinuous { return "Escuchando sin manos · toca para terminar" }
        if isListening { return "Escuchando… suelta para terminar" }
        return onTap == nil ? "Mantén presionado para hablar" : "Mantén para hablar · toca para manos libres"
    }

    var body: some View {
        Label(title, systemImage: isContinuous ? "waveform.circle.fill" : (isListening ? "waveform" : "mic.fill"))
            .font(.headline)
            .multilineTextAlignment(.center)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .padding(.horizontal, 8)
            .background(isListening || isContinuous ? Color.red : Color.accentColor, in: Capsule())
            .contentShape(Capsule())
            .scaleEffect(pressedAt != nil ? 1.03 : 1)
            .animation(.easeOut(duration: 0.15), value: pressedAt != nil)
            // Distancia 0: empieza al tocar y termina al soltar, aunque el dedo se mueva.
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard pressedAt == nil else { return }
                        pressedAt = Date()
                        pressStartedContinuous = isContinuous
                        if !isContinuous { onPress() }
                    }
                    .onEnded { _ in
                        let duration = pressedAt.map { Date().timeIntervalSince($0) } ?? 0
                        pressedAt = nil
                        if pressStartedContinuous {
                            if let onTap { onTap() } else { onRelease() }
                        } else if duration < Self.tapThreshold, let onTap {
                            onTap()
                        } else {
                            onRelease()
                        }
                    }
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(isListening || isContinuous ? "Terminar dictado" : "Dictar")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction {
                if isContinuous {
                    if let onTap { onTap() } else { onRelease() }
                } else if isListening {
                    onRelease()
                } else {
                    onPress()
                    onTap?()
                }
            }
    }
}
