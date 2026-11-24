import Foundation
@testable import APIClient

/// Transporte falso: registra peticiones y devuelve respuestas encoladas.
final class FakeTransport: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var responses: [Result<HTTPResponse, APIError>]
    private(set) var requests: [HTTPRequest] = []

    init(_ responses: [Result<HTTPResponse, APIError>]) {
        self.responses = responses
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        lock.lock()
        requests.append(request)
        let next = responses.removeFirst()
        lock.unlock()
        return try next.get()
    }
}

func json(_ status: Int, _ body: String, headers: [String: String] = [:]) -> Result<HTTPResponse, APIError> {
    .success(HTTPResponse(status: status, headers: headers, body: Data(body.utf8)))
}

let sessionJSON = #"{"seller":{"id":"s-1","customerCode":"100000001","displayName":"Dev Seller"}}"#
let baseURL = URL(string: "http://192.168.1.10:3000")!
