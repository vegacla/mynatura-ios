import Foundation
import SwiftData

/// Acceso a `SessionSummary`. Solo hay una sesión "actual" por dispositivo.
@MainActor
public struct SessionRepository {
    private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    public func current() -> SessionSummary? {
        var descriptor = FetchDescriptor<SessionSummary>(sortBy: [SortDescriptor(\.lastValidatedAt, order: .reverse)])
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    /// Guarda la sesión validada. Si entra otra cuenta, borra los datos locales de la anterior.
    @discardableResult
    public func upsert(sellerId: String, customerCode: String, displayName: String) throws -> SessionSummary {
        var all = try context.fetch(FetchDescriptor<SessionSummary>())
        if all.contains(where: { $0.sellerId != sellerId }) {
            try PersistenceController.deleteAllData(in: context)
            all = []
        }
        let summary: SessionSummary
        if let existing = all.first(where: { $0.sellerId == sellerId }) {
            existing.customerCode = customerCode
            existing.displayName = displayName
            existing.lastValidatedAt = .now
            summary = existing
        } else {
            summary = SessionSummary(sellerId: sellerId, customerCode: customerCode, displayName: displayName)
            context.insert(summary)
        }
        try context.save()
        return summary
    }

    /// Logout: borra los datos locales de la cuenta.
    public func deleteAll() throws {
        try PersistenceController.deleteAllData(in: context)
    }
}
