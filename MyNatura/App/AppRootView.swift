import SwiftUI

/// Decide entre restaurando / login / app según la sesión.
struct AppRootView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            switch session.phase {
            case .restoring:
                ProgressView("Restaurando sesión…")
            case .signedOut:
                LoginScreen()
            case .signedIn:
                RootTabView()
            }
        }
        .animation(.default, value: session.phase)
        .task { await session.restore() }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task { await session.revalidateIfOffline() }
            }
        }
    }
}
