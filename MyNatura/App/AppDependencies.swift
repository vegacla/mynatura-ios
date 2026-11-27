import Features
import Persistence
import Store
import SwiftData

/// Base de datos, perfil y store compartidos por la app y los Atajos de Siri (que pueden correr sin abrir la app).
@MainActor
enum AppDependencies {
    static let container: ModelContainer = {
        do {
            return try PersistenceController.makeContainer()
        } catch {
            fatalError("No se pudo abrir la base de datos local: \(error)")
        }
    }()

    static let profile = AppProfile(repository: SessionRepository(context: container.mainContext))
    static let store = LocalStore(context: container.mainContext, connectivity: ConnectivityMonitor())
}
