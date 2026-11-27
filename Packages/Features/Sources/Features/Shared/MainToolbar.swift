import SwiftUI
import UIKit

/// Toolbar común: botón de consulta por voz (la pastilla de sync se quitó en M7).
extension View {
    func mainToolbar(sellerId: String) -> some View {
        toolbar {
            ToolbarItem(placement: .topBarLeading) {
                VoiceQueryToolbarButton(sellerId: sellerId)
            }
        }
    }
}

enum Haptics {
    @MainActor static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    @MainActor static func error() { UINotificationFeedbackGenerator().notificationOccurred(.error) }
    @MainActor static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
}

/// Texto "solo online" cuando falta conexión (§4.6).
struct OnlineOnlyNote: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "wifi.slash")
            .font(.footnote)
            .foregroundStyle(.secondary)
    }
}
