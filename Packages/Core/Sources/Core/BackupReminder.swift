import Foundation

/// Recordatorio de respaldo (docs/local-first-migration.md §6): "Último respaldo: hace 9 días".
public enum BackupReminder {
    /// Cada cuántos días se recuerda respaldar.
    public static let intervalDays = 7

    /// Días completos desde el último respaldo (nil = nunca).
    public static func daysSince(_ lastBackupAt: Date?, now: Date, calendar: Calendar = .current) -> Int? {
        guard let lastBackupAt else { return nil }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: lastBackupAt),
                                           to: calendar.startOfDay(for: now)).day ?? 0
        return max(days, 0)
    }

    /// Toca respaldar: hay datos y nunca se respaldó, o pasaron `intervalDays` o más.
    public static func isDue(lastBackupAt: Date?, hasData: Bool, now: Date, calendar: Calendar = .current) -> Bool {
        guard hasData else { return false }
        guard let days = daysSince(lastBackupAt, now: now, calendar: calendar) else { return true }
        return days >= intervalDays
    }

    public static func label(lastBackupAt: Date?, now: Date, calendar: Calendar = .current) -> String {
        switch daysSince(lastBackupAt, now: now, calendar: calendar) {
        case nil: "Nunca"
        case 0: "Hoy"
        case 1: "Ayer"
        case let days?: "Hace \(days) días"
        }
    }

    /// Nombre del archivo: "MyNatura-respaldo-2026-11-27.json".
    public static func fileName(now: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: now)
        let date = String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
        return "MyNatura-respaldo-\(date).json"
    }
}
