import Foundation

// Espejo de customers y customer-orders contracts.

public struct CustomerDTO: Codable, Sendable, Equatable {
    public let id: String
    public let displayName: String
    public let rut: String?
    public let phone: String?
    public let notes: String?
    public let createdAt: Date
    public let updatedAt: Date
}

public struct CustomersResponseDTO: Codable, Sendable, Equatable {
    public let customers: [CustomerDTO]
}

public struct CustomerResponseDTO: Codable, Sendable, Equatable {
    public let customer: CustomerDTO
}

/// Body de POST/PATCH /api/customers.
public struct CustomerInputDTO: Codable, Sendable, Equatable {
    public let displayName: String
    public let rut: String?
    public let phone: String?
    public let notes: String?

    public init(displayName: String, rut: String?, phone: String?, notes: String?) {
        self.displayName = displayName
        self.rut = rut
        self.phone = phone
        self.notes = notes
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(displayName, forKey: .displayName)
        try container.encode(rut, forKey: .rut)
        try container.encode(phone, forKey: .phone)
        try container.encode(notes, forKey: .notes)
    }
}

public struct CustomerOrderLineDTO: Codable, Sendable, Equatable {
    public let id: String
    public let sellerProductId: String
    public let productName: String
    public let naturaSku: String
    public let quantity: Int
    public let suggestedUnitPriceCents: Int?
    public let finalUnitPriceCents: Int?
    public let note: String?
}

public struct CustomerOrderDTO: Codable, Sendable, Equatable {
    public let id: String
    public let customerId: String
    public let customerDisplayName: String
    public let cycle: Int
    public let status: String
    public let note: String?
    public let orderedAt: Date
    public let createdAt: Date
    public let updatedAt: Date
    public let lineCount: Int
}

public struct CustomerOrdersResponseDTO: Codable, Sendable, Equatable {
    public let orders: [CustomerOrderDTO]
}

public struct CustomerOrderDetailDTO: Codable, Sendable, Equatable {
    public let order: CustomerOrderDTO
    public let lines: [CustomerOrderLineDTO]

    public init(from decoder: any Decoder) throws {
        order = try CustomerOrderDTO(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        lines = try container.decode([CustomerOrderLineDTO].self, forKey: .lines)
    }

    public func encode(to encoder: any Encoder) throws {
        try order.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(lines, forKey: .lines)
    }

    private enum CodingKeys: String, CodingKey { case lines }
}

public struct CustomerOrderDetailResponseDTO: Codable, Sendable, Equatable {
    public let order: CustomerOrderDetailDTO
}

public struct CustomerOrderLineInputDTO: Codable, Sendable, Equatable {
    public let sellerProductId: String
    public let quantity: Int
    public let suggestedUnitPriceCents: Int?
    public let finalUnitPriceCents: Int?
    public let note: String?

    public init(sellerProductId: String, quantity: Int, suggestedUnitPriceCents: Int?, finalUnitPriceCents: Int?, note: String?) {
        self.sellerProductId = sellerProductId
        self.quantity = quantity
        self.suggestedUnitPriceCents = suggestedUnitPriceCents
        self.finalUnitPriceCents = finalUnitPriceCents
        self.note = note
    }
}

/// Body de POST/PATCH /api/customer-orders.
public struct CustomerOrderInputDTO: Codable, Sendable, Equatable {
    public let customerId: String?
    public let newCustomerName: String?
    public let cycle: Int
    public let status: String
    public let note: String?
    public let orderedAt: String?
    public let lines: [CustomerOrderLineInputDTO]

    public init(customerId: String?, newCustomerName: String?, cycle: Int, status: String, note: String?, orderedAt: String?, lines: [CustomerOrderLineInputDTO]) {
        self.customerId = customerId
        self.newCustomerName = newCustomerName
        self.cycle = cycle
        self.status = status
        self.note = note
        self.orderedAt = orderedAt
        self.lines = lines
    }
}

public extension Endpoint where Response == CustomersResponseDTO {
    static var customers: Self { Endpoint(path: "/api/customers") }
}

public extension Endpoint where Response == CustomerResponseDTO {
    static func createCustomer(_ input: CustomerInputDTO) -> Self {
        Endpoint(method: .post, path: "/api/customers", json: input)
    }

    static func updateCustomer(id: String, _ input: CustomerInputDTO) -> Self {
        Endpoint(method: .patch, path: "/api/customers/\(PathEscape.segment(id))", json: input)
    }
}

public extension Endpoint where Response == CustomerOrdersResponseDTO {
    static var customerOrders: Self { Endpoint(path: "/api/customer-orders") }
}

public extension Endpoint where Response == CustomerOrderDetailResponseDTO {
    static func customerOrder(id: String) -> Self {
        Endpoint(path: "/api/customer-orders/\(PathEscape.segment(id))")
    }

    static func createCustomerOrder(_ input: CustomerOrderInputDTO) -> Self {
        Endpoint(method: .post, path: "/api/customer-orders", json: input)
    }

    static func updateCustomerOrder(id: String, _ input: CustomerOrderInputDTO) -> Self {
        Endpoint(method: .patch, path: "/api/customer-orders/\(PathEscape.segment(id))", json: input)
    }
}
