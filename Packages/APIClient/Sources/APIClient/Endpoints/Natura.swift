import Foundation

// Espejo de natura-integration/contracts/natura-import-contracts.ts

public struct NaturaOrderDTO: Codable, Sendable, Equatable {
    public let id: String
    public let externalOrderId: String
    public let orderNumber: String
    public let cycle: Int
    public let subCycle: String?
    public let orderedAt: Date
    public let deliveredAt: Date?
    public let statusName: String
    public let itemsQuantity: Int
    public let totalValueCents: Int
    public let receiptOcrStatus: String?
    public let receiptOcrProcessedAt: Date?
    public let receivingClosedAt: Date?
    public let receivingReviewStatus: String
    public let receivedUnitsQuantity: Int
    public let pendingUnitsQuantity: Int
    public let receivingStatus: String
}

public struct NaturaOrdersResponseDTO: Codable, Sendable, Equatable {
    public let orders: [NaturaOrderDTO]
}

public struct NaturaOrderLineDTO: Codable, Sendable, Equatable {
    public let id: String
    public let naturaSku: String
    public let productName: String
    public let quantity: Int
    public let purchaseUnitPriceCents: Int?
    public let suggestedSaleUnitPriceCents: Int?
    public let proposedSuggestedSaleUnitPriceCents: Int?
    public let receivedConfirmationQuantity: Int
    public let proposedReceivedConfirmationQuantity: Int?
    public let receivedConfirmedAt: Date?
    public let barcodes: [String]
}

/// Detalle = campos del pedido + líneas.
public struct NaturaOrderDetailDTO: Codable, Sendable, Equatable {
    public let order: NaturaOrderDTO
    public let lines: [NaturaOrderLineDTO]

    public init(from decoder: any Decoder) throws {
        order = try NaturaOrderDTO(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        lines = try container.decode([NaturaOrderLineDTO].self, forKey: .lines)
    }

    public func encode(to encoder: any Encoder) throws {
        try order.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(lines, forKey: .lines)
    }

    private enum CodingKeys: String, CodingKey { case lines }
}

public struct NaturaOrderDetailResponseDTO: Codable, Sendable, Equatable {
    public let order: NaturaOrderDetailDTO
}

public struct NaturaImportRunDTO: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let type: String
    public let status: String
    public let startedAt: Date
    public let finishedAt: Date?
    public let importedOrderCount: Int
    public let importedLineCount: Int
}

public struct NaturaImportRunsResponseDTO: Codable, Sendable, Equatable {
    public let runs: [NaturaImportRunDTO]
}

public struct StartImportInputDTO: Codable, Sendable, Equatable {
    public let customerCode: String
    public let password: String
}

public struct StartImportResponseDTO: Codable, Sendable, Equatable {
    public let run: NaturaImportRunDTO
}

/// Body de PATCH …/lines/:lineId. Ambos campos son obligatorios (el precio puede ser null).
public struct UpdateNaturaOrderLineInputDTO: Codable, Sendable, Equatable {
    public let suggestedSaleUnitPriceCents: Int?
    public let receivedConfirmationQuantity: Int

    public init(suggestedSaleUnitPriceCents: Int?, receivedConfirmationQuantity: Int) {
        self.suggestedSaleUnitPriceCents = suggestedSaleUnitPriceCents
        self.receivedConfirmationQuantity = receivedConfirmationQuantity
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(suggestedSaleUnitPriceCents, forKey: .suggestedSaleUnitPriceCents)
        try container.encode(receivedConfirmationQuantity, forKey: .receivedConfirmationQuantity)
    }
}

public struct ReceivingReviewInputDTO: Codable, Sendable, Equatable {
    /// "close" | "reopen"
    public let action: String
}

public struct ReceiptOcrRowDTO: Codable, Sendable, Equatable {
    public let naturaSku: String
    public let description: String
    public let quantity: Int?
    public let priceVentaCents: Int?
    public let confidence: Double
}

public struct ReceiptOcrResultDTO: Codable, Sendable, Equatable {
    public let status: String
    public let matchedLineCount: Int
    public let unmatchedSkus: [String]
    public let extractedRows: [ReceiptOcrRowDTO]
}

public struct ReceiptOcrResponseDTO: Codable, Sendable, Equatable {
    public let order: NaturaOrderDTO
    public let ocr: ReceiptOcrResultDTO
}

public extension Endpoint where Response == NaturaOrdersResponseDTO {
    static var naturaOrders: Self { Endpoint(path: "/api/natura/orders") }
}

public extension Endpoint where Response == NaturaOrderDetailResponseDTO {
    static func naturaOrder(id: String) -> Self {
        Endpoint(path: "/api/natura/orders/\(PathEscape.segment(id))")
    }

    static func updateNaturaOrderLine(orderId: String, lineId: String, input: UpdateNaturaOrderLineInputDTO) -> Self {
        Endpoint(method: .patch,
                 path: "/api/natura/orders/\(PathEscape.segment(orderId))/lines/\(PathEscape.segment(lineId))",
                 json: input)
    }

    static func receivingReview(orderId: String, close: Bool) -> Self {
        Endpoint(method: .patch, path: "/api/natura/orders/\(PathEscape.segment(orderId))/receiving-review",
                 json: ReceivingReviewInputDTO(action: close ? "close" : "reopen"))
    }
}

public extension Endpoint where Response == NaturaImportRunsResponseDTO {
    static var naturaImportRuns: Self { Endpoint(path: "/api/natura/import-runs") }
}

public extension Endpoint where Response == StartImportResponseDTO {
    /// Credenciales Natura: viajan una vez al backend y nunca se guardan en el dispositivo.
    static func importDeliveredOrders(customerCode: String, password: String) -> Self {
        Endpoint(method: .post, path: "/api/natura/import-runs/delivered-orders",
                 json: StartImportInputDTO(customerCode: customerCode, password: password))
    }
}

public extension Endpoint where Response == ReceiptOcrResponseDTO {
    static func receiptOcr(orderId: String, jpeg: Data) -> Self {
        let file = MultipartFile(fieldName: "file", fileName: "boleta.jpg", mimeType: "image/jpeg", data: jpeg)
        return Endpoint(method: .post, path: "/api/natura/orders/\(PathEscape.segment(orderId))/receipt-ocr",
                        body: file.body, contentType: file.contentType)
    }
}
