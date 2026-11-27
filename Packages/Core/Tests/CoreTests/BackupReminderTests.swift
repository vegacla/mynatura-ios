import Foundation
import Testing
@testable import Core

@Suite("Respaldo · recordatorio (M5)")
struct BackupReminderTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Santiago")!
        return calendar
    }

    private func date(_ day: Int, _ hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour))!
    }

    @Test func labels() {
        #expect(BackupReminder.label(lastBackupAt: nil, now: date(27), calendar: calendar) == "Nunca")
        #expect(BackupReminder.label(lastBackupAt: date(27, 8), now: date(27, 20), calendar: calendar) == "Hoy")
        #expect(BackupReminder.label(lastBackupAt: date(26, 23), now: date(27, 1), calendar: calendar) == "Ayer")
        #expect(BackupReminder.label(lastBackupAt: date(18), now: date(27), calendar: calendar) == "Hace 9 días")
    }

    @Test func dueAfterAWeekOrNeverWithData() {
        #expect(BackupReminder.isDue(lastBackupAt: nil, hasData: true, now: date(27), calendar: calendar))
        #expect(!BackupReminder.isDue(lastBackupAt: nil, hasData: false, now: date(27), calendar: calendar))
        #expect(!BackupReminder.isDue(lastBackupAt: date(21), hasData: true, now: date(27), calendar: calendar))
        #expect(BackupReminder.isDue(lastBackupAt: date(20), hasData: true, now: date(27), calendar: calendar))
    }

    @Test func fileName() {
        #expect(BackupReminder.fileName(now: date(7), calendar: calendar) == "MyNatura-respaldo-2026-11-07.json")
    }
}
