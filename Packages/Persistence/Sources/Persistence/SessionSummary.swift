import Foundation
import SwiftData

/// Perfil local (M7): `sellerId` con que se identifican los datos del iPhone y código de consultora Natura.
/// En instalaciones anteriores conserva el `sellerId` del backend, para no perder datos.
@Model
public final class SessionSummary {
    @Attribute(.unique) public var sellerId: String
    public var customerCode: String
    public var displayName: String
    /// Última actualización del perfil.
    public var lastValidatedAt: Date

    public init(sellerId: String, customerCode: String, displayName: String, lastValidatedAt: Date = .now) {
        self.sellerId = sellerId
        self.customerCode = customerCode
        self.displayName = displayName
        self.lastValidatedAt = lastValidatedAt
    }
}
