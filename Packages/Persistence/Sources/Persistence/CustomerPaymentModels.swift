import Foundation
import SwiftData

/// Abono de un cliente a lo que debe (ventas fiadas). Paga primero la compra más antigua.
@Model
public final class CustomerPayment {
    @Attribute(.unique) public var id: String
    public var sellerId: String
    public var customerId: String
    public var amountPesos: Int
    public var paidAt: Date
    public var note: String?

    public init(id: String = UUID().uuidString.lowercased(), sellerId: String, customerId: String, amountPesos: Int,
                paidAt: Date = .now, note: String? = nil) {
        self.id = id
        self.sellerId = sellerId
        self.customerId = customerId
        self.amountPesos = amountPesos
        self.paidAt = paidAt
        self.note = note
    }
}
