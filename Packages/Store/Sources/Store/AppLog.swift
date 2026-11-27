import Foundation
import OSLog

/// Logs de la app (se leen en Ajustes › Diagnóstico con OSLogStore, §13.1).
public enum AppLog {
    public static let subsystem = "cl.mynatura.app"
    public static let sync = Logger(subsystem: subsystem, category: "sync")
    public static let app = Logger(subsystem: subsystem, category: "app")

    /// Últimas entradas del proceso actual (más recientes al final).
    public static func recentEntries(limit: Int = 300) -> [String] {
        guard let store = try? OSLogStore(scope: .currentProcessIdentifier) else { return [] }
        let start = store.position(date: Date().addingTimeInterval(-6 * 3600))
        guard let entries = try? store.getEntries(at: start, matching: NSPredicate(format: "subsystem == %@", subsystem)) else { return [] }
        let lines = entries.compactMap { $0 as? OSLogEntryLog }.map { entry in
            "\(entry.date.formatted(date: .omitted, time: .standard)) [\(entry.category)] \(entry.composedMessage)"
        }
        return Array(lines.suffix(limit))
    }
}
