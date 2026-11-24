import Foundation
import Testing
@testable import APIClient

@Suite("CookieJar")
struct CookieJarTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func storesAndReplaces() {
        var jar = CookieJar.apply(setCookie: "a=1; Path=/", to: [:], now: now)
        jar = CookieJar.apply(setCookie: "a=2; HttpOnly", to: jar, now: now)
        #expect(jar == ["a": "2"])
    }

    @Test func splitsCombinedHeadersWithoutBreakingDates() {
        let header = "a=1; Expires=Thu, 01 Jan 2099 00:00:00 GMT; Path=/, b=2; Path=/"
        #expect(CookieJar.split(header) == ["a=1; Expires=Thu, 01 Jan 2099 00:00:00 GMT; Path=/", "b=2; Path=/"])
        #expect(CookieJar.apply(setCookie: header, to: [:], now: now) == ["a": "1", "b": "2"])
    }

    @Test func expiredOrEmptyRemoves() {
        let jar = ["a": "1", "b": "2", "c": "3"]
        let result = CookieJar.apply(
            setCookie: "a=; Path=/, b=x; Max-Age=0, c=y; Expires=Thu, 01 Jan 1970 00:00:00 GMT",
            to: jar, now: now)
        #expect(result.isEmpty)
    }

    @Test func keepsSignedValueWithDotsAndEquals() {
        let jar = CookieJar.apply(setCookie: "s=abc.def%3D=; Path=/", to: [:], now: now)
        #expect(jar == ["s": "abc.def%3D="])
    }

    @Test func header() {
        #expect(CookieJar.header(for: [:]) == nil)
        #expect(CookieJar.header(for: ["b": "2", "a": "1"]) == "a=1; b=2")
    }
}

@Suite("BackendURL & Endpoint")
struct BackendURLTests {
    @Test(arguments: [
        ("192.168.1.10:3000", "http://192.168.1.10:3000"),
        (" http://pc.local:3000/ ", "http://pc.local:3000"),
        ("https://abc.trycloudflare.com", "https://abc.trycloudflare.com"),
    ])
    func parses(input: String, expected: String) {
        #expect(BackendURL.parse(input)?.absoluteString == expected)
    }

    @Test(arguments: ["", "   ", "http://", "a b"])
    func rejects(input: String) {
        #expect(BackendURL.parse(input) == nil)
    }

    @Test func endpointURL() {
        let base = URL(string: "http://h:3000/")!
        #expect(Endpoint<HealthDTO>.health.url(relativeTo: base)?.absoluteString == "http://h:3000/health")
        let search = Endpoint<EmptyResponse>(path: "/api/customers", query: [QueryItem("q", "maría josé")])
        #expect(search.url(relativeTo: base)?.absoluteString == "http://h:3000/api/customers?q=mar%C3%ADa%20jos%C3%A9")
    }

    @Test func decodesDatesWithAndWithoutMilliseconds() {
        #expect(JSONCoding.parseDate("2026-11-23T10:00:00.123Z") != nil)
        #expect(JSONCoding.parseDate("2026-11-23T10:00:00Z") != nil)
        #expect(JSONCoding.parseDate("23/11/2026") == nil)
    }
}
