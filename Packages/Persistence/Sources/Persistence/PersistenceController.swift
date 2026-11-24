import Foundation
import SwiftData

public enum PersistenceController {
    /// Todos los modelos de la app. Agregar aquí cada @Model nuevo.
    public static var schema: Schema {
        Schema([
            SessionSummary.self,
        ])
    }

    /// Contenedor en Application Support/MyNatura con protección
    /// `completeUntilFirstUserAuthentication` (permite sync en background tras el primer desbloqueo).
    public static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        if inMemory {
            return try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        }
        let directory = URL.applicationSupportDirectory.appending(path: "MyNatura", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
        )
        let configuration = ModelConfiguration(schema: schema, url: directory.appending(path: "MyNatura.store"))
        return try ModelContainer(for: schema, configurations: configuration)
    }
}
