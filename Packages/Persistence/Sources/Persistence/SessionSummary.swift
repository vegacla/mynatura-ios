import Foundation
import SwiftData

/// Última sesión validada contra el backend; permite entrar offline (§4.1, §6).
@Model
public final class SessionSummary {
    @Attribute(.unique) public var sellerId: String
    public var customerCode: String
    public var displayName: String
    /// Última vez que `/api/auth/me` o login confirmaron la sesión.
    public var lastValidatedAt: Date

    public init(sellerId: String, customerCode: String, displayName: String, lastValidatedAt: Date = .now) {
        self.sellerId = sellerId
        self.customerCode = customerCode
        self.displayName = displayName
        self.lastValidatedAt = lastValidatedAt
    }
}
