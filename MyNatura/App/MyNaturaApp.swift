import Features
import Persistence
import Store
import SwiftData
import SwiftUI

/// Punto de entrada: inyecta las dependencias compartidas (`AppDependencies`) en el entorno. Sin backend ni login (M7).
@main
struct MyNaturaApp: App {
    @State private var profile = AppDependencies.profile
    @State private var store = AppDependencies.store
    @State private var router = AppRouter.shared

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environment(profile)
                .environment(store)
                .environment(router)
        }
        .modelContainer(AppDependencies.container)
    }
}
