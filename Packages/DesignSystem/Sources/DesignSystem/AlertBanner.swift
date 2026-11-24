import SwiftUI

/// Aviso inline y calmo (nunca alertas bloqueantes por estar offline, §10).
public struct AlertBanner: View {
    let message: String
    let tone: StatusTone
    let systemImage: String

    public init(_ message: String, tone: StatusTone = .warning, systemImage: String = "exclamationmark.triangle.fill") {
        self.message = message
        self.tone = tone
        self.systemImage = systemImage
    }

    public var body: some View {
        Label {
            Text(message).font(.subheadline)
        } icon: {
            Image(systemName: systemImage).foregroundStyle(tone.color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(tone.color.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
    }
}
