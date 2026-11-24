// Solo plataformas Apple: en Linux (CI de tests) se usa el transporte falso.
#if !os(Linux)
import Foundation

/// Transporte real. Las cookies se manejan a mano (`SessionCredentialStore`), no con HTTPCookieStorage:
/// la cookie del backend es "de sesión" (sin Expires) y iOS la descartaría al cerrar la app.
public final class URLSessionTransport: HTTPTransport {
    private let session: URLSession

    public init(timeout: TimeInterval = 30) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpCookieStorage = nil
        configuration.timeoutIntervalForRequest = timeout
        configuration.waitsForConnectivity = false
        session = URLSession(configuration: configuration)
    }

    public func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method.rawValue
        urlRequest.httpBody = request.body
        if let timeout = request.timeout { urlRequest.timeoutInterval = timeout }
        for (name, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: name)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch let error as URLError {
            throw Self.map(error)
        }
        guard let http = response as? HTTPURLResponse else {
            throw APIError.network("Respuesta no HTTP")
        }
        var headers: [String: String] = [:]
        for (key, value) in http.allHeaderFields {
            if let key = key as? String, let value = value as? String {
                headers[key] = value
            }
        }
        return HTTPResponse(status: http.statusCode, headers: headers, body: data)
    }

    static func map(_ error: URLError) -> APIError {
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost, .cannotFindHost,
             .dnsLookupFailed, .timedOut, .internationalRoamingOff, .dataNotAllowed:
            .offline
        default:
            .network(error.localizedDescription)
        }
    }
}
#endif
