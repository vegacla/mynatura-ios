import Core
import SwiftUI

/// Pastilla de conectividad/sync en la toolbar (§3).
public struct SyncStatusPill: View {
    let indicator: SyncIndicator

    public init(_ indicator: SyncIndicator) {
        self.indicator = indicator
    }

    private var tone: StatusTone {
        switch indicator {
        case .online: .success
        case .pending: .warning
        case .offline: .neutral
        case .failed: .danger
        case .syncing: .info
        }
    }

    private var systemImage: String {
        switch indicator {
        case .online: "checkmark.icloud"
        case .pending: "arrow.triangle.2.circlepath.icloud"
        case .offline: "icloud.slash"
        case .failed: "exclamationmark.icloud"
        case .syncing: "arrow.triangle.2.circlepath"
        }
    }

    public var body: some View {
        StatusBadge(indicator.label, tone: tone, systemImage: systemImage)
            .accessibilityLabel("Estado de sincronización: \(indicator.label)")
    }
}
