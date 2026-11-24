import Foundation

public protocol APIClient: Sendable {
    func send<R: Decodable & Sendable>(_ endpoint: Endpoint<R>) async throws(APIError) -> R
    /// Hay cookie de sesión guardada.
    var hasSessionCredential: Bool { get }
    func clearSessionCredential()
}

/// Cliente real: arma la URL desde `baseURL`, agrega la cookie, guarda Set-Cookie y mapea errores.
public final class LiveAPIClient: APIClient {
    private let baseURL: @Sendable () -> URL?
    private let transport: any HTTPTransport
    private let credentials: any SessionCredentialStore

    public init(
        baseURL: @escaping @Sendable () -> URL?,
        transport: any HTTPTransport,
        credentials: any SessionCredentialStore
    ) {
        self.baseURL = baseURL
        self.transport = transport
        self.credentials = credentials
    }

    public var hasSessionCredential: Bool { !credentials.load().isEmpty }

    public func clearSessionCredential() { credentials.clear() }

    public func send<R: Decodable & Sendable>(_ endpoint: Endpoint<R>) async throws(APIError) -> R {
        guard let base = baseURL(), let url = endpoint.url(relativeTo: base) else { throw .notConfigured }

        var headers = ["Accept": "application/json"]
        if endpoint.body != nil { headers["Content-Type"] = endpoint.contentType ?? "application/json" }
        if let cookie = CookieJar.header(for: credentials.load()) { headers["Cookie"] = cookie }
        let request = HTTPRequest(method: endpoint.method, url: url, headers: headers, body: endpoint.body)

        let response: HTTPResponse
        do {
            response = try await transport.send(request)
        } catch let error as APIError {
            throw error
        } catch {
            throw .network(String(describing: error))
        }

        if let setCookie = response.header("set-cookie") {
            credentials.save(CookieJar.apply(setCookie: setCookie, to: credentials.load()))
        }

        guard (200..<300).contains(response.status) else {
            if response.status == 401 { credentials.clear() }
            let message = (try? JSONCoding.decoder.decode(ErrorBody.self, from: response.body))?.message
            throw APIError.from(status: response.status, message: message)
        }

        if R.self == EmptyResponse.self, let empty = EmptyResponse() as? R { return empty }
        do {
            return try JSONCoding.decoder.decode(R.self, from: response.body)
        } catch {
            throw .decoding(String(describing: error))
        }
    }
}

private struct ErrorBody: Decodable {
    let message: String?
}
