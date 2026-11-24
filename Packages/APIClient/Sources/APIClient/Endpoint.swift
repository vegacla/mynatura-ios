import Foundation

public struct QueryItem: Sendable, Equatable {
    public var name: String
    public var value: String

    public init(_ name: String, _ value: String) {
        self.name = name
        self.value = value
    }
}

/// Descripción tipada de una llamada al backend. `path` es absoluto ("/api/auth/me").
public struct Endpoint<Response: Decodable & Sendable>: Sendable {
    public var method: HTTPMethod
    public var path: String
    public var query: [QueryItem]
    public var body: Data?
    /// Content-Type del cuerpo; por defecto JSON.
    public var contentType: String?

    public init(method: HTTPMethod = .get, path: String, query: [QueryItem] = [], body: Data? = nil, contentType: String? = nil) {
        self.method = method
        self.path = path
        self.query = query
        self.body = body
        self.contentType = contentType
    }

    public init(method: HTTPMethod, path: String, json: some Encodable) {
        self.init(method: method, path: path, body: try? JSONCoding.encoder.encode(json))
    }

    public func url(relativeTo baseURL: URL) -> URL? {
        var base = baseURL.absoluteString
        while base.hasSuffix("/") { base.removeLast() }
        guard var components = URLComponents(string: base + path) else { return nil }
        if !query.isEmpty {
            components.queryItems = query.map { URLQueryItem(name: $0.name, value: $0.value) }
        }
        return components.url
    }
}

public struct EmptyResponse: Decodable, Sendable, Equatable {
    public init() {}
}

public enum JSONCoding {
    public static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    /// Fechas ISO 8601 con o sin milisegundos (Postgres/JS emiten "…T10:00:00.000Z").
    public static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            if let date = parseDate(text) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Fecha inválida: \(text)")
        }
        return decoder
    }

    static func parseDate(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }
}
