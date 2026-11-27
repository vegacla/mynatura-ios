import Foundation
import SwiftData

/// Perfil local de la app (M7): no hay login propio. `SessionSummary` guarda el `sellerId` con que se identifican
/// los datos en el iPhone (en instalaciones anteriores, el del backend; si no, uno generado aquí).
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

    /// El perfil existente o uno nuevo (`local-…`).
    public func ensureLocalProfile() -> SessionSummary {
        if let existing = current() { return existing }
        let profile = SessionSummary(sellerId: "local-" + UUID().uuidString.lowercased(), customerCode: "", displayName: "")
        context.insert(profile)
        try? context.save()
        return profile
    }

    /// Guarda el código de consultora Natura en el perfil (se muestra en Ajustes).
    public func updateCustomerCode(_ code: String) {
        guard let profile = current(), profile.customerCode != code else { return }
        profile.customerCode = code
        profile.lastValidatedAt = .now
        try? context.save()
    }

    /// Borra todos los datos del iPhone (incluido el perfil).
    public func deleteAll() throws {
        try PersistenceController.deleteAllData(in: context)
    }
}
