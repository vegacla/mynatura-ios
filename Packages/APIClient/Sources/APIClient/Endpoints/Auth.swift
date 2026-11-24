import Foundation

// Espejo de backend/src/modules/auth/contracts/auth-contracts.ts

public struct SellerDTO: Codable, Sendable, Equatable {
    public let id: String
    public let customerCode: String
    public let displayName: String

    public init(id: String, customerCode: String, displayName: String) {
        self.id = id
        self.customerCode = customerCode
        self.displayName = displayName
    }
}

public struct AuthSessionDTO: Codable, Sendable, Equatable {
    public let seller: SellerDTO

    public init(seller: SellerDTO) {
        self.seller = seller
    }
}

public struct LoginRequestDTO: Codable, Sendable, Equatable {
    public let customerCode: String
    public let password: String
}

public struct LogoutResponseDTO: Codable, Sendable, Equatable {
    public let success: Bool
}

public struct HealthDTO: Codable, Sendable, Equatable {
    public let status: String
}

public extension Endpoint where Response == AuthSessionDTO {
    static func login(customerCode: String, password: String) -> Self {
        Endpoint(method: .post, path: "/api/auth/login",
                 json: LoginRequestDTO(customerCode: customerCode, password: password))
    }

    static var me: Self { Endpoint(path: "/api/auth/me") }
}

public extension Endpoint where Response == LogoutResponseDTO {
    static var logout: Self { Endpoint(method: .post, path: "/api/auth/logout") }
}

public extension Endpoint where Response == HealthDTO {
    static var health: Self { Endpoint(path: "/health") }
}
