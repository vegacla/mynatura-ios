import Foundation
import Testing
@testable import APIClient

@Suite("LiveAPIClient")
struct LiveAPIClientTests {
    func makeClient(_ transport: FakeTransport, _ store: InMemoryCredentialStore = .init(), base: URL? = baseURL) -> LiveAPIClient {
        LiveAPIClient(baseURL: { base }, transport: transport, credentials: store)
    }

    @Test func loginStoresSessionCookieAndSendsItBack() async throws {
        let transport = FakeTransport([
            json(200, sessionJSON, headers: ["Set-Cookie": "mynatura_session=abc.sig; Path=/; HttpOnly; SameSite=Lax"]),
            json(200, sessionJSON),
        ])
        let store = InMemoryCredentialStore()
        let client = makeClient(transport, store)

        let session = try await client.send(.login(customerCode: "100000001", password: "changeme123"))
        #expect(session.seller.displayName == "Dev Seller")
        #expect(store.load() == ["mynatura_session": "abc.sig"])
        #expect(client.hasSessionCredential)

        _ = try await client.send(.me)
        let login = transport.requests[0]
        #expect(login.method == .post)
        #expect(login.url.absoluteString == "http://192.168.1.10:3000/api/auth/login")
        #expect(login.headers["Content-Type"] == "application/json")
        #expect(login.headers["Cookie"] == nil)
        let body = try JSONDecoder().decode(LoginRequestDTO.self, from: login.body ?? Data())
        #expect(body == LoginRequestDTO(customerCode: "100000001", password: "changeme123"))

        let me = transport.requests[1]
        #expect(me.method == .get)
        #expect(me.body == nil)
        #expect(me.headers["Content-Type"] == nil)
        #expect(me.headers["Cookie"] == "mynatura_session=abc.sig")
    }

    @Test func unauthorizedClearsCookieAndCarriesMessage() async {
        let transport = FakeTransport([json(401, #"{"message":"Unauthorized."}"#)])
        let store = InMemoryCredentialStore(["mynatura_session": "old"])
        let client = makeClient(transport, store)

        await #expect(throws: APIError.unauthorized(message: "Unauthorized.")) {
            _ = try await client.send(.me)
        }
        #expect(store.load().isEmpty)
    }

    @Test func logoutClearCookieRemovesIt() async throws {
        let transport = FakeTransport([
            json(200, #"{"success":true}"#,
                 headers: ["set-cookie": "mynatura_session=; Max-Age=0; Path=/; Expires=Thu, 01 Jan 1970 00:00:00 GMT"]),
        ])
        let store = InMemoryCredentialStore(["mynatura_session": "abc"])
        let response = try await makeClient(transport, store).send(.logout)
        #expect(response.success)
        #expect(store.load().isEmpty)
        #expect(transport.requests[0].headers["Content-Type"] == nil)
    }

    @Test(arguments: [
        (400, #"{"statusCode":400,"error":"Bad Request","message":"body/password must NOT have fewer than 8 characters"}"#,
         APIError.validation(message: "body/password must NOT have fewer than 8 characters")),
        (409, #"{"message":"Ya existe"}"#, .conflict(message: "Ya existe")),
        (404, "", .notFound),
        (500, "boom", .server(status: 500)),
        (422, "", .validation(message: "Solicitud rechazada (422).")),
    ])
    func mapsHTTPErrors(status: Int, body: String, expected: APIError) async {
        let client = makeClient(FakeTransport([json(status, body)]))
        await #expect(throws: expected) { _ = try await client.send(.me) }
    }

    @Test func transportErrorsPassThrough() async {
        let client = makeClient(FakeTransport([.failure(.offline)]))
        await #expect(throws: APIError.offline) { _ = try await client.send(.me) }
        #expect(APIError.offline.isUnreachable)
        #expect(APIError.server(status: 503).isUnreachable)
        #expect(!APIError.unauthorized(message: nil).isUnreachable)
    }

    @Test func missingBaseURLIsNotConfigured() async {
        let transport = FakeTransport([])
        let client = makeClient(transport, base: nil)
        await #expect(throws: APIError.notConfigured) { _ = try await client.send(.me) }
        #expect(transport.requests.isEmpty)
    }

    @Test func badJSONIsDecodingError() async {
        let client = makeClient(FakeTransport([json(200, #"{"nope":1}"#)]))
        do throws(APIError) {
            _ = try await client.send(.me)
            Issue.record("Debió fallar")
        } catch {
            guard case .decoding = error else {
                Issue.record("Error inesperado: \(error)")
                return
            }
        }
    }
}
