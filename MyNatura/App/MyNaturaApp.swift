import APIClient
import Features
import Persistence
import SwiftData
import SwiftUI
import Sync

/// Punto de entrada: arma dependencias (§2) y las inyecta en el entorno.
@main
struct MyNaturaApp: App {
    private let container: ModelContainer
    @State private var session: SessionStore
    @State private var sync: SyncEngine

    init() {
        let container: ModelContainer
        do {
            container = try PersistenceController.makeContainer()
        } catch {
            fatalError("No se pudo abrir la base de datos local: \(error)")
        }
        self.container = container

        let api = LiveAPIClient(
            baseURL: { BackendSettings.url },
            transport: URLSessionTransport(),
            credentials: KeychainCredentialStore()
        )
        let session = SessionStore(api: api, repository: SessionRepository(context: container.mainContext))
        let sync = SyncEngine(api: api, context: container.mainContext)
        sync.onUnauthorized = { [weak session] in session?.handleUnauthorized() }
        _session = State(initialValue: session)
        _sync = State(initialValue: sync)
    }

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environment(session)
                .environment(sync)
        }
        .modelContainer(container)
    }
}
