import BackgroundTasks
import Features
import SwiftUI
import Sync

/// Decide entre restaurando / login / app según la sesión, y dispara la sincronización (§7.4).
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
        .task {
            sync.connectivity.onReconnect = { onReconnect() }
            await session.restore()
        }
        // Al iniciar sesión online (login, restauración o al recuperar la red): push + pull.
        .task(id: session.current.map { "\($0.sellerId)|\($0.isOffline)" }) {
            guard let current = session.current, !current.isOffline else { return }
            await sync.syncNow(sellerId: current.sellerId)
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                Task {
                    await session.revalidateIfOffline()
                    if let current = session.current, !current.isOffline {
                        await sync.syncNow(sellerId: current.sellerId)
                    }
                }
            case .background:
                BackgroundRefresh.schedule()
            default:
                break
            }
        }
    }

    private func onReconnect() {
        Task {
            await session.revalidateIfOffline()
            if let current = session.current, !current.isOffline {
                await sync.syncNow(sellerId: current.sellerId)
            }
        }
    }
}

/// BGAppRefreshTask (§7.4). Si iOS no lo ejecuta, la sync en foreground cubre el caso.
enum BackgroundRefresh {
    static let identifier = "cl.mynatura.app.refresh"

    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }
}
