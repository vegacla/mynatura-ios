import Core
import DesignSystem
import Persistence
import SwiftData
import SwiftUI
import Sync

/// Pastilla de estado en la toolbar de todas las pantallas (§3).
struct SyncStatusToolbarItem: View {
    @Environment(SyncEngine.self) private var sync
    @Query private var mutations: [PendingMutation]

    init(sellerId: String) {
        _mutations = Query(filter: #Predicate<PendingMutation> { $0.sellerId == sellerId })
    }

    var body: some View {
        let failed = mutations.filter { $0.status == .failed }.count
        SyncStatusPill(SyncIndicator.derive(
            isOnline: sync.connectivity.isOnline, isSyncing: sync.isSyncing,
            pending: mutations.count - failed, failed: failed))
    }
}

extension View {
    func syncStatusToolbar(sellerId: String) -> some View {
        toolbar {
            ToolbarItem(placement: .topBarLeading) {
                SyncStatusToolbarItem(sellerId: sellerId)
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
