import SwiftUI

/// Progreso de recepción "Recepción X / Y".
public struct ReceivingProgressBar: View {
    let received: Int
    let total: Int

    public init(received: Int, total: Int) {
        self.received = received
        self.total = total
    }

    private var fraction: Double { total == 0 ? 0 : min(Double(received) / Double(total), 1) }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ProgressView(value: fraction)
                .tint(fraction >= 1 ? StatusTone.success.color : StatusTone.info.color)
            Text("Recepción \(received) / \(total)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}
