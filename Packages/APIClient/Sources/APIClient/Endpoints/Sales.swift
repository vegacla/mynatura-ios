import Foundation

// Espejo de backend/src/modules/sales/contracts/sales-contracts.ts

public struct PricingReasonDTO: Codable, Sendable, Equatable {
    public let code: String
    public let label: String
    /// "gift" | "discount"
    public let category: String
}

public struct PricingReasonsResponseDTO: Codable, Sendable, Equatable {
    public let reasons: [PricingReasonDTO]
}

public struct CreateSaleLineInputDTO: Codable, Sendable, Equatable {
    public let sellerProductId: String
    public let quantity: Int
    public let finalUnitPriceCents: Int
    public let pricingReasonCode: String?
    public let pricingReasonNote: String?

    public init(sellerProductId: String, quantity: Int, finalUnitPriceCents: Int, pricingReasonCode: String?, pricingReasonNote: String?) {
        self.sellerProductId = sellerProductId
        self.quantity = quantity
        self.finalUnitPriceCents = finalUnitPriceCents
        self.pricingReasonCode = pricingReasonCode
        self.pricingReasonNote = pricingReasonNote
    }
}

public struct CreateSaleInputDTO: Codable, Sendable, Equatable {
    public let clientMutationId: String
    /// ISO 8601
    public let occurredAt: String
    public let customerId: String?
    public let note: String?
    public let lines: [CreateSaleLineInputDTO]

    public init(clientMutationId: String, occurredAt: String, customerId: String?, note: String?, lines: [CreateSaleLineInputDTO]) {
        self.clientMutationId = clientMutationId
        self.occurredAt = occurredAt
        self.customerId = customerId
        self.note = note
        self.lines = lines
    }
}

public struct CreatedSaleLineDTO: Codable, Sendable, Equatable {
    public let id: String
    public let sellerProductId: String
    public let productName: String
    public let naturaSku: String
    public let quantity: Int
    public let suggestedUnitPriceCents: Int?
    public let costUnitPriceCents: Int?
    public let costTotalCents: Int?
    public let finalUnitPriceCents: Int
    public let pricingReasonCode: String?
    public let pricingReasonCategory: String?
}

public struct CreatedSaleDTO: Codable, Sendable, Equatable {
    public let id: String
    public let sellerId: String
    public let clientMutationId: String
    public let occurredAt: Date
    public let note: String?
    public let lines: [CreatedSaleLineDTO]
}

public struct CreateSaleResponseDTO: Codable, Sendable, Equatable {
    public let sale: CreatedSaleDTO
}

public struct SaleListLineDTO: Codable, Sendable, Equatable {
    public let id: String
    public let sellerProductId: String
    public let productName: String
    public let naturaSku: String
    public let quantity: Int
    public let suggestedUnitPriceCents: Int?
    public let finalUnitPriceCents: Int
    public let pricingReasonCode: String?
    public let costUnitPriceCents: Int?
}

public struct SaleListItemDTO: Codable, Sendable, Equatable {
    public let id: String
    public let clientMutationId: String
    public let occurredAt: Date
    public let note: String?
    public let customerDisplayName: String?
    public let lines: [SaleListLineDTO]
}

public struct SaleListResponseDTO: Codable, Sendable, Equatable {
    public let sales: [SaleListItemDTO]
}

public extension Endpoint where Response == PricingReasonsResponseDTO {
    static var pricingReasons: Self { Endpoint(path: "/api/sales/pricing-reasons") }
}

public extension Endpoint where Response == SaleListResponseDTO {
    static var sales: Self { Endpoint(path: "/api/sales") }
}

public extension Endpoint where Response == CreateSaleResponseDTO {
    static func createSale(_ input: CreateSaleInputDTO) -> Self {
        Endpoint(method: .post, path: "/api/sales", json: input)
    }
}

public extension APIError {
    /// El backend rechaza un `clientMutationId` repetido con este mensaje (§9.1):
    /// la venta ya está guardada, así que el reintento cuenta como éxito.
    var isDuplicateSale: Bool {
        if case .validation(let message) = self {
            return message.localizedCaseInsensitiveContains("ya fue registrada")
        }
        return false
    }
}
