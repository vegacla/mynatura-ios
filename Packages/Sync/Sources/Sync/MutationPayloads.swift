import APIClient
import Foundation

// Payloads guardados en PendingMutation.payload (JSON). Los IDs locales ("local-…") que contengan
// se reescriben cuando el backend devuelve el ID real (§7.6).

struct BarcodePayload: Codable, Sendable {
    let sellerProductId: String
    let ean: String
}

struct ReceivingLinePayload: Codable, Sendable {
    let orderId: String
    let lineId: String
    var suggestedSaleUnitPriceCents: Int?
    var receivedConfirmationQuantity: Int

    var input: UpdateNaturaOrderLineInputDTO {
        UpdateNaturaOrderLineInputDTO(suggestedSaleUnitPriceCents: suggestedSaleUnitPriceCents,
                                      receivedConfirmationQuantity: receivedConfirmationQuantity)
    }
}

struct CustomerCreatePayload: Codable, Sendable {
    let localId: String
    var input: CustomerInputDTO
}

struct CustomerUpdatePayload: Codable, Sendable {
    let customerId: String
    var input: CustomerInputDTO
}

struct QuickProductPayload: Codable, Sendable {
    let localId: String
    let naturaSku: String
    let name: String
}

struct CustomerOrderPayload: Codable, Sendable {
    let orderId: String
    var input: CustomerOrderInputDTO
}

enum PayloadCoding {
    static func encode(_ value: some Encodable) -> Data {
        (try? JSONCoding.encoder.encode(value)) ?? Data()
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) -> T? {
        try? JSONCoding.decoder.decode(type, from: data)
    }
}
