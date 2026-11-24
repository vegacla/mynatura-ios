import Foundation

public struct SyncEventInputDTO: Codable, Sendable, Equatable {
    public let entityType: String
    public let localReference: String?
    /// "succeeded" | "failed"
    public let status: String
    public let errorSummary: String?

    public init(entityType: String, localReference: String?, status: String, errorSummary: String?) {
        self.entityType = entityType
        self.localReference = localReference
        self.status = status
        self.errorSummary = errorSummary
    }
}

public struct RecordSyncEventsResponseDTO: Codable, Sendable, Equatable {
    public let recorded: Int
}

public extension Endpoint where Response == RecordSyncEventsResponseDTO {
    /// Auditoría best-effort tras cada lote de push (§7.3).
    static func recordSyncEvents(_ events: [SyncEventInputDTO]) -> Self {
        Endpoint(method: .post, path: "/api/sync/events", json: events)
    }
}
