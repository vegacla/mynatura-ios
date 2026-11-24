import Features
import SwiftUI
import Sync

/// Decide entre restaurando / login / app según la sesión, y dispara el pull (§7.4).
struct AppRootView: View {
    @Environment(SessionStore.self) private var session
    @Environment(SyncEngine.self) private var sync
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            switch session.phase {
            case .restoring:
                ProgressView("Restaurando sesión…")
            case .signedOut:
                LoginScreen()
            case .signedIn(let current):
                RootTabView(sellerId: current.sellerId)
            }
        }
        .animation(.default, value: session.phase)
        .task { await session.restore() }
        // Pull al iniciar sesión online (login, restauración o al recuperar la red).
        .task(id: session.current.map { "\($0.sellerId)|\($0.isOffline)" }) {
            guard let current = session.current, !current.isOffline else { return }
            await sync.pullAll(sellerId: current.sellerId)
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            Task {
                await session.revalidateIfOffline()
                if let current = session.current, !current.isOffline {
                    await sync.pullAll(sellerId: current.sellerId)
                }
            }
        }
    }
}
