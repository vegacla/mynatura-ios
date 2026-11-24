import SwiftUI

/// Tono semántico único para estados (§10): acento para acciones, semánticos solo para estado.
public enum StatusTone: Sendable {
    case neutral, info, success, warning, danger

    public var color: Color {
        switch self {
        case .neutral: .secondary
        case .info: .blue
        case .success: .green
        case .warning: .orange
        case .danger: .red
        }
    }
}

/// Pastilla de estado. Única fuente de colores por estado.
public struct StatusBadge: View {
    let text: String
    let tone: StatusTone
    let systemImage: String?

    public init(_ text: String, tone: StatusTone = .neutral, systemImage: String? = nil) {
        self.text = text
        self.tone = tone
        self.systemImage = systemImage
    }

    public var body: some View {
        HStack(spacing: 3) {
            if let systemImage { Image(systemName: systemImage) }
            Text(text)
        }
        .font(.caption2.weight(.semibold))
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .foregroundStyle(tone.color)
        .background(tone.color.opacity(0.12), in: Capsule())
        .accessibilityElement(children: .combine)
    }
}
