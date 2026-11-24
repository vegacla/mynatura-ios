import SwiftUI

/// Dato compacto: título pequeño + valor destacado.
public struct MiniStat: View {
    let title: String
    let value: String
    let tone: StatusTone

    public init(_ title: String, value: String, tone: StatusTone = .neutral) {
        self.title = title
        self.value = value
        self.tone = tone
    }

    public var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title3.weight(.semibold).monospacedDigit())
                .foregroundStyle(tone == .neutral ? Color.primary : tone.color)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
    }
}
