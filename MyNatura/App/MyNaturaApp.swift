import Features
import Persistence
import Store
import SwiftData
import SwiftUI

/// Punto de entrada: arma dependencias y las inyecta en el entorno. Sin backend ni login (M7).
@main
struct MyNaturaApp: App {
    private let container: ModelContainer
    @State private var profile: AppProfile
    @State private var store: LocalStore
    @State private var router = AppRouter.shared

    init() {
        let container: ModelContainer
        do {
            container = try PersistenceController.makeContainer()
        } catch {
            fatalError("No se pudo abrir la base de datos local: \(error)")
        }
        self.container = container
        _profile = State(initialValue: AppProfile(repository: SessionRepository(context: container.mainContext)))
        _store = State(initialValue: LocalStore(context: container.mainContext, connectivity: ConnectivityMonitor()))
    }

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environment(profile)
                .environment(store)
                .environment(router)
        }
        .modelContainer(container)
    }
}
