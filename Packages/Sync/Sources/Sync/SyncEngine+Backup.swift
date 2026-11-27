import Core
import Foundation
import Persistence
import SwiftData

/// Respaldo local (M5 de docs/local-first-migration.md §6): exportar e importar un JSON con todo.
extension SyncEngine {
    /// Escribe el respaldo en un archivo temporal listo para compartir (Archivos, Drive, correo…).
    public func exportBackup(sellerId: String, appVersion: String?) -> Result<URL, ActionError> {
        do {
            let backup = try BackupService.makeBackup(context: context, sellerId: sellerId, appVersion: appVersion)
            let data = try BackupService.encode(backup)
            let directory = FileManager.default.temporaryDirectory.appending(path: "Respaldo", directoryHint: .isDirectory)
            try? FileManager.default.removeItem(at: directory)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appending(path: BackupReminder.fileName(now: backup.exportedAt))
            try data.write(to: url, options: [.atomic, .completeFileProtection])
            return .success(url)
        } catch {
            return .failure(ActionError("No se pudo preparar el respaldo: \(error.localizedDescription)"))
        }
    }

    /// Se compartió o guardó el respaldo: reinicia el recordatorio.
    public func markBackupDone(sellerId: String) {
        settings(sellerId: sellerId).lastBackupAt = .now
        save()
    }

    /// Lee un respaldo para la vista previa (no cambia nada).
    public func readBackup(at url: URL) -> Result<BackupFile, ActionError> {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            do throws(BackupError) {
                return .success(try BackupService.decode(data))
            } catch {
                return .failure(ActionError(error.message))
            }
        } catch {
            return .failure(ActionError("No se pudo abrir el archivo: \(error.localizedDescription)"))
        }
    }

    /// Reemplaza los datos locales por los del respaldo (conserva la sesión). Si falla, deja lo que había.
    public func restoreBackup(_ backup: BackupFile, sellerId: String) -> ActionError? {
        do {
            try BackupService.restore(backup, context: context, sellerId: sellerId)
            return nil
        } catch {
            return ActionError("No se pudo restaurar el respaldo; tus datos quedaron como estaban. \(error.localizedDescription)")
        }
    }

    /// Hay datos propios que valga la pena respaldar.
    public func hasBackupableData(sellerId: String) -> Bool {
        var products = FetchDescriptor<CatalogProduct>(predicate: #Predicate { $0.sellerId == sellerId })
        products.fetchLimit = 1
        var customers = FetchDescriptor<Customer>(predicate: #Predicate { $0.sellerId == sellerId })
        customers.fetchLimit = 1
        return !fetchAll(products).isEmpty || !fetchAll(customers).isEmpty
    }
}
