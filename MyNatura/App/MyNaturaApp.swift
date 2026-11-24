import APIClient
import Persistence
import SwiftData
import SwiftUI

@main
struct MyNaturaApp: App {
    private let container: ModelContainer
    @State private var session: SessionStore

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
        _session = State(initialValue: SessionStore(
            api: api,
            repository: SessionRepository(context: container.mainContext)
        ))
    }

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environment(session)
        }
        .modelContainer(container)
    }
}
