import Core
import Foundation

/// Error de una llamada a Natura, con mensaje listo para la UI.
public enum NaturaError: Error, Equatable, Sendable {
    /// Akamai bloqueó la llamada: reintentar más tarde.
    case blocked(String)
    /// Natura rechazó las credenciales: **no reintentar** (evita bloquear la cuenta).
    case credentials(String)
    /// Natura pide un paso adicional (p. ej. aceptar términos): entrar una vez a minegocio.
    case challenge(String)
    case network(String)
    case unexpected(String)

    public var message: String {
        switch self {
        case .blocked(let step): "Natura bloqueó la conexión (\(step)). Intenta de nuevo en unos minutos."
        case .credentials(let detail): "Natura rechazó el inicio de sesión: \(detail)"
        case .challenge(let name): "Natura pide un paso adicional (\(name)). Entra una vez a minegocio.natura.cl y vuelve a intentar."
        case .network(let detail): "Sin conexión con Natura: \(detail)"
        case .unexpected(let detail): "Respuesta inesperada de Natura: \(detail)"
        }
    }
}

/// Producto del catálogo del ciclo actual (GSP `cardSection`).
public struct CycleCatalogItem: Equatable, Sendable {
    public let sku: String
    public let name: String
    public let brand: String?
    public let category: String
    public let points: Int?
    public let purchasePesos: Int?
    public let resalePesos: Int?
    public let imageURL: String?
}

public struct NaturaCycleInfo: Equatable, Sendable {
    /// AAAACC.
    public let code: Int
    public let start: Date?
    public let end: Date?
    public let remainingDays: Int?
}

/// Sesión con Natura por HTTP, sin navegador (docs/natura-integration.md). Una instancia por importación:
/// las cookies y tokens viven solo en memoria y se descartan al terminar.
public actor NaturaClient {
    static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/145.0.0.0 Safari/537.36"

    private let http = NaturaHTTP()
    private var cookies: [String: String] = [:]
    private var username = ""
    private var ssoToken: String?
    private var gspConfig: GspPublicConfig?
    private var accessToken: String?
    private var xAppToken = ""
    private var personCode = ""

    public init() {}

    // MARK: Login

    /// signin (natura-auth) → sesión de minegocio (`wcmn_session`). El código de consultora es el usuario.
    public func login(customerCode: String, password: String) async throws {
        username = NaturaUsername.normalize(customerCode)

        // 1. URL de login de minegocio (con su client_id) desde la redirección de /ingreso/cl.
        let entry = try await send(URLRequest(url: URL(string: "https://minegocio.natura.cl/ingreso/cl?return_url=")!), step: "ingreso")
        guard let loginLocation = entry.1.value(forHTTPHeaderField: "Location"), let loginURL = URL(string: loginLocation),
              let components = URLComponents(url: loginURL, resolvingAgainstBaseURL: false),
              let clientId = components.queryItems?.first(where: { $0.name == "client_id" })?.value,
              let redirectURI = components.queryItems?.first(where: { $0.name == "redirect_uri" })?.value else {
            throw NaturaError.unexpected("no se encontró la página de login de minegocio")
        }
        let company = components.queryItems?.first(where: { $0.name == "company" })?.value ?? "natura"
        let country = components.queryItems?.first(where: { $0.name == "country" })?.value ?? "cl"

        // 2. API y x-api-key desde el bundle de la página de login.
        let page = try await text(URLRequest(url: loginURL), step: "página de login")
        guard let assetPath = NaturaBundle.firstMatchPublic(#"src="(/assets/index-[^"]+\.js)""#, in: page),
              let assetURL = URL(string: assetPath, relativeTo: loginURL) else {
            throw NaturaError.unexpected("cambió la página de login")
        }
        let bundle = try await text(URLRequest(url: assetURL), step: "configuración de login")
        guard let apiDomain = NaturaBundle.firstMatchPublic(#"VITE_APP_API_DOMAIN:"([^"]+)""#, in: bundle),
              let apiKey = NaturaBundle.firstMatchPublic(#"VITE_APP_API_TOKEN:"([^"]+)""#, in: bundle),
              let signinURL = URL(string: apiDomain + "/signin") else {
            throw NaturaError.unexpected("cambió la configuración de login")
        }
        let redirectUrl = redirectURI.contains("return_url") ? redirectURI : redirectURI + "?return_url="

        // 3. signin con la contraseña cifrada como CryptoJS.
        guard let encrypted = CryptoJSAES.encrypt(password, passphrase: username) else {
            throw NaturaError.unexpected("no se pudo cifrar la contraseña")
        }
        var request = URLRequest(url: signinURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("https://\(loginURL.host ?? "")", forHTTPHeaderField: "Origin")
        request.setValue(loginURL.absoluteString, forHTTPHeaderField: "Referer")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "clientId": clientId, "country": country, "company": company, "username": username,
            "password": encrypted, "recaptchaToken": "disabled", "redirectUrl": redirectUrl, "document": "personCode",
        ])
        let (data, response) = try await send(request, step: "signin")
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        if (400..<500).contains(response.statusCode) {
            let message = json["message"] as? String ?? "HTTP \(response.statusCode)"
            if NaturaUsername.isCredentialError(status: response.statusCode, message: message) {
                throw NaturaError.credentials(message)
            }
            throw NaturaError.unexpected("signin \(response.statusCode): \(message)")
        }
        if json["challengeRequired"] as? Bool == true {
            let challenge = (json["challenge"] as? [String: Any])?["challengeName"] as? String ?? "desconocido"
            throw NaturaError.challenge(challenge)
        }
        guard let token = json["sso_token"] as? String, !token.isEmpty else {
            throw NaturaError.unexpected("signin no devolvió sso_token")
        }
        ssoToken = token

        // 4. natura-callback de minegocio → wcmn_session (redirecciones a mano).
        var callback = URLComponents(string: redirectUrl)
        callback?.queryItems = (callback?.queryItems ?? []) + [URLQueryItem(name: "sso_token", value: token)]
        guard var next = callback?.url else { throw NaturaError.unexpected("callback inválido") }
        for _ in 0..<8 {
            let (_, hop) = try await send(URLRequest(url: next), step: "natura-callback")
            guard (300..<400).contains(hop.statusCode), let location = hop.value(forHTTPHeaderField: "Location"),
                  let url = URL(string: location, relativeTo: next) else { break }
            next = url.absoluteURL
        }
        guard cookies["wcmn_session"] != nil else {
            throw NaturaError.unexpected("minegocio no entregó la sesión")
        }
    }

    // MARK: minegocio

    /// Todos los pedidos (todas las páginas), del más antiguo al más reciente.
    public func orders() async throws -> [NaturaOrderSummary] {
        var all: [NaturaOrderSummary] = []
        var page = 1
        while page < 200 {
            var components = URLComponents(string: "https://minegocio.natura.cl/pedidos/ajax/orders/\(username)/0")!
            components.queryItems = [URLQueryItem(name: "page", value: String(page)),
                                     URLQueryItem(name: "pageSize", value: String(NaturaOrders.pageSize)),
                                     URLQueryItem(name: "orderId", value: "")]
            let data = try await xhr(components.url!, step: "pedidos")
            let batch: [NaturaOrderSummary]
            do { batch = try NaturaOrders.decodePage(data) } catch { throw NaturaError.unexpected(error.message) }
            all += batch
            if NaturaOrders.isLastPage(batch) { break }
            page += 1
        }
        return all.sorted { ($0.orderedAt ?? .distantPast) < ($1.orderedAt ?? .distantPast) }
    }

    /// Excel del pedido (fuente principal). Prueba con el número de pedido y con el id; nil si no llega un XLSX.
    public func orderReport(for order: NaturaOrderSummary) async throws -> OrderReport? {
        for key in [order.orderNumber, order.id] {
            guard let encoded = key.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
                  let url = URL(string: "https://minegocio.natura.cl/pedidos/order-report/\(encoded)") else { continue }
            var request = URLRequest(url: url)
            request.setValue("https://minegocio.natura.cl/pedidos", forHTTPHeaderField: "Referer")
            let (data, response) = try await send(request, step: "Excel del pedido")
            guard response.statusCode == 200, data.starts(with: [0x50, 0x4B]) else { continue }
            guard let sheet = try? ZipReader.entry(named: "xl/worksheets/sheet1.xml", in: data),
                  let report = try? OrderReportParser.parse(sheetXML: sheet), !report.lines.isEmpty else { continue }
            return report
        }
        return nil
    }

    /// Líneas desde el HTML (respaldo del Excel).
    public func orderItems(for order: NaturaOrderSummary) async throws -> [NaturaOrderItem] {
        guard let url = URL(string: "https://minegocio.natura.cl/pedidos/items/\(order.id)/\(order.orderNumber)?from=pedidos") else {
            return []
        }
        var request = URLRequest(url: url)
        request.setValue("https://minegocio.natura.cl/pedidos", forHTTPHeaderField: "Referer")
        let html = try await text(request, step: "líneas del pedido")
        do { return try NaturaItemsHTML.parse(html) } catch { throw NaturaError.unexpected(error.message) }
    }

    /// Ciclo vigente (AAAACC) desde el home de minegocio.
    public func homeCycle() async throws -> Int? {
        MinegocioHome.currentCycle(fromHTML: try await text(URLRequest(url: URL(string: "https://minegocio.natura.cl/home")!), step: "home"))
    }

    // MARK: GSP

    /// Configuración del bundle de GSP → recover-session con el sso_token → cadena del xAppToken.
    public func openGsp() async throws {
        guard let ssoToken else { throw NaturaError.unexpected("primero hay que iniciar sesión") }
        let home = try await text(URLRequest(url: URL(string: "https://gsp.natura.com/")!), step: "GSP")
        guard let path = NaturaBundle.gspBundlePath(fromHTML: home), let bundleURL = URL(string: path, relativeTo: URL(string: "https://gsp.natura.com/")) else {
            throw NaturaError.unexpected("cambió la página de GSP")
        }
        let config: GspPublicConfig
        do { config = try NaturaBundle.gspConfig(fromBundle: try await text(URLRequest(url: bundleURL), step: "configuración GSP")) }
        catch let error as NaturaParseError { throw NaturaError.unexpected(error.message) }
        gspConfig = config

        var request = URLRequest(url: URL(string: config.serviceApiUrl.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/authentication-api/recover-session")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(config.apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("https://gsp.natura.com", forHTTPHeaderField: "Origin")
        request.setValue("https://gsp.natura.com/", forHTTPHeaderField: "Referer")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["token": ssoToken, "redirectUrl": config.redirectUri, "clientId": config.clientId])
        let (data, response) = try await send(request, step: "recover-session")
        guard response.statusCode == 200, let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let access = json["accessToken"] as? String else {
            throw NaturaError.unexpected("GSP no abrió la sesión (HTTP \(response.statusCode))")
        }
        accessToken = access
        xAppToken = ""

        let person = try await graphql(GspQueries.authPersonData, variables: ["personID": NSNull(), "channelId": 1, "fullTokens": false],
                                       operation: "authPersonData")
        personCode = dig(person, ["profileGetPersonData", "payload", "personCode"]) as? String ?? username
        updateToken(person, ["profileGetPersonData", "xAppToken"])
        let cycles = try await graphql(GspQueries.profileOtherCycles, variables: ["roleId": 1, "functionId": 1, "businessModelId": 1],
                                       operation: "profileOtherCycles")
        updateToken(cycles, ["profileGetOtherCycles", "xAppToken"])
        let commercial = try await graphql(GspQueries.authCommercialInfo,
                                           variables: ["channelId": 1, "showcaseAccess": true, "businessModelId": 1, "systemId": 1],
                                           operation: "authCommercialInfo")
        updateToken(commercial, ["profileGetCommercialInfo", "xAppToken"])
    }

    /// Ciclo actual con fechas (GSP `consultantSection`).
    public func currentCycle() async throws -> NaturaCycleInfo? {
        let data = try await graphql(GspQueries.consultantSection, variables: [:])
        guard let cycle = dig(data, ["consultantSection", "actualCycle"]) as? [String: Any],
              let number = cycle["number"] as? Int, let year = cycle["year"] as? Int ?? (cycle["year"] as? String).flatMap(Int.init) else {
            return nil
        }
        return NaturaCycleInfo(code: year * 100 + number,
                               start: (cycle["startDate"] as? String).flatMap(NaturaDates.parse),
                               end: (cycle["endDate"] as? String).flatMap(NaturaDates.parse),
                               remainingDays: cycle["remainingDays"] as? Int)
    }

    /// Catálogo del ciclo: todas las categorías (pestañas) de GSP y sus páginas, sin repetir códigos.
    public func cycleCatalog(cycle: Int) async throws -> [CycleCatalogItem] {
        let categoriesData = try await graphql(GspQueries.categories, variables: ["context": "NATURA", "cycle": cycle])
        let categories = (dig(categoriesData, ["categorySection", "categories"]) as? [[String: Any]] ?? [])
            .compactMap { category -> (id: String, label: String)? in
                guard let id = category["id"] as? String, let label = category["label"] as? String,
                      (category["target"] as? String ?? "TAB_CARDS") == "TAB_CARDS" else { return nil }
                return (id, label)
            }
        var items: [String: CycleCatalogItem] = [:]
        for category in categories {
            var page = 1
            while page <= 40 {
                let data = try await graphql(GspQueries.cardSection, variables: [
                    "context": "NATURA", "category": category.id, "cycle": cycle, "page": page, "size": 60,
                    "filterOptions": ["productCategories": [String](), "productLines": [String]()], "lastPromotionCodes": [Int](),
                ])
                let cards = dig(data, ["cardSection", "cards"]) as? [[String: Any]] ?? []
                for card in cards {
                    let products = (card["products"] as? [[String: Any]]).flatMap { $0.isEmpty ? nil : $0 } ?? [card]
                    for product in products {
                        guard let rawCode = product["code"], let sku = Self.code(rawCode), items[sku] == nil else { continue }
                        items[sku] = CycleCatalogItem(
                            sku: sku, name: product["name"] as? String ?? card["name"] as? String ?? sku,
                            brand: product["brand"] as? String ?? card["brand"] as? String, category: category.label,
                            points: Self.number(product["points"]), purchasePesos: Self.price(product["purchasePrice"]),
                            resalePesos: Self.price(product["resalePrice"]), imageURL: product["image"] as? String)
                    }
                }
                let totalPages = Self.number(dig(data, ["cardSection", "totalPages"])) ?? 1
                if page >= totalPages || cards.isEmpty { break }
                page += 1
            }
        }
        return Array(items.values)
    }

    // MARK: HTTP

    private func graphql(_ query: String, variables: [String: Any], operation: String? = nil) async throws -> Any {
        guard let config = gspConfig, let accessToken, let url = URL(string: config.graphqlUrl) else {
            throw NaturaError.unexpected("GSP sin sesión")
        }
        let operationName = NaturaBundle.firstMatchPublic(#"query (\w+)"#, in: query) ?? "query"
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(xAppToken, forHTTPHeaderField: "x-app-token")
        request.setValue("https://gsp.natura.com", forHTTPHeaderField: "Origin")
        request.setValue("https://gsp.natura.com/", forHTTPHeaderField: "Referer")
        if let operation {
            request.setValue(operation, forHTTPHeaderField: "operation")
            request.setValue("", forHTTPHeaderField: "sessionidentifier")
        } else {
            request.setValue("WEB", forHTTPHeaderField: "application")
            request.setValue("CL", forHTTPHeaderField: "country")
            request.setValue(personCode, forHTTPHeaderField: "http_username")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: ["operationName": operationName, "query": query, "variables": variables])
        let (data, response) = try await send(request, step: operationName)
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw NaturaError.unexpected("\(operationName): HTTP \(response.statusCode)")
        }
        if let errors = json["errors"] as? [[String: Any]], !errors.isEmpty, json["data"] == nil || json["data"] is NSNull {
            let message = errors.compactMap { $0["message"] as? String }.joined(separator: "; ")
            throw NaturaError.unexpected("\(operationName): \(message)")
        }
        return json["data"] ?? [:]
    }

    private func updateToken(_ data: Any, _ path: [String]) {
        if let token = dig(data, path) as? String, !token.isEmpty { xAppToken = token }
    }

    private func dig(_ value: Any, _ path: [String]) -> Any? {
        var current: Any? = value
        for key in path { current = (current as? [String: Any])?[key] }
        return current
    }

    static func code(_ value: Any) -> String? {
        if let int = value as? Int { return String(int) }
        if let string = value as? String, !string.isEmpty { return Normalize.naturaSku(string) }
        return nil
    }

    static func number(_ value: Any?) -> Int? {
        if let int = value as? Int { return int }
        if let double = value as? Double { return Int(double.rounded()) }
        return nil
    }

    /// `{ from, to }`: `to` es el precio vigente (con descuento); si no viene, `from`.
    static func price(_ value: Any?) -> Int? {
        guard let range = value as? [String: Any] else { return number(value) }
        return number(range["to"]) ?? number(range["from"])
    }

    private func xhr(_ url: URL, step: String) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.setValue("https://minegocio.natura.cl/pedidos", forHTTPHeaderField: "Referer")
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        let (data, response) = try await send(request, step: step)
        guard response.statusCode == 200 else { throw NaturaError.unexpected("\(step): HTTP \(response.statusCode)") }
        return data
    }

    private func text(_ request: URLRequest, step: String) async throws -> String {
        let (data, response) = try await send(request, step: step)
        guard response.statusCode == 200 else { throw NaturaError.unexpected("\(step): HTTP \(response.statusCode)") }
        return String(decoding: data, as: UTF8.self)
    }

    /// Envía con cookies propias (de natura y minegocio), sin seguir redirecciones, y detecta bloqueos de Akamai.
    private func send(_ original: URLRequest, step: String) async throws -> (Data, HTTPURLResponse) {
        var request = original
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        if request.value(forHTTPHeaderField: "Accept") == nil {
            request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        }
        if let host = request.url?.host, host.hasSuffix("natura.cl"), !cookies.isEmpty {
            request.setValue(cookies.map { "\($0.key)=\($0.value)" }.joined(separator: "; "), forHTTPHeaderField: "Cookie")
        }
        let (data, response): (Data, HTTPURLResponse)
        do {
            (data, response) = try await http.send(request)
        } catch {
            throw NaturaError.network(error.localizedDescription)
        }
        if let host = request.url?.host, host.hasSuffix("natura.cl") { storeCookies(from: response) }
        if response.statusCode == 403 || response.statusCode == 429 {
            let server = response.value(forHTTPHeaderField: "Server") ?? ""
            let body = String(decoding: data.prefix(2000), as: UTF8.self)
            if server.localizedCaseInsensitiveContains("akamai") || body.contains("Access Denied") || body.contains("edgesuite") {
                throw NaturaError.blocked(step)
            }
        }
        return (data, response)
    }

    private func storeCookies(from response: HTTPURLResponse) {
        let headers = response.allHeaderFields.reduce(into: [String: String]()) { result, entry in
            if let key = entry.key as? String, let value = entry.value as? String { result[key] = value }
        }
        guard let url = response.url else { return }
        for cookie in HTTPCookie.cookies(withResponseHeaderFields: headers, for: url) {
            if cookie.value.isEmpty || (cookie.expiresDate.map { $0 < Date() } ?? false) {
                cookies.removeValue(forKey: cookie.name)
            } else {
                cookies[cookie.name] = cookie.value
            }
        }
    }
}

/// Consultas GraphQL mínimas de GSP (docs/natura-integration.md §3.3).
enum GspQueries {
    static let authPersonData = """
    query authPersonData($personID: String, $fullTokens: Boolean, $channelId: ID) {
      profileGetPersonData(personID: $personID fullTokens: $fullTokens channelId: $channelId) {
        xAppToken payload { personCode countryCode isBlocked } } }
    """
    static let profileOtherCycles = """
    query profileOtherCycles($businessModelId: Int, $roleId: Int, $functionId: Int) {
      profileGetOtherCycles(businessModelId: $businessModelId roleId: $roleId functionId: $functionId) {
        xAppToken payload { personData { currentCycle { cycleCode dateStart dateEnd orderDate } } } } }
    """
    static let authCommercialInfo = """
    query authCommercialInfo($businessModelId: Int, $systemId: Int, $showcaseAccess: Boolean, $channelId: Int) {
      profileGetCommercialInfo(businessModelId: $businessModelId systemId: $systemId showcaseAccess: $showcaseAccess channelId: $channelId) {
        xAppToken payload { isBlocked credit { available limit additional } } } }
    """
    static let consultantSection = """
    query consultantSection { consultantSection {
      actualCycle { number label startDate endDate year status remainingDays orderDate } } }
    """
    static let categories = """
    query categories($context: String!, $cycle: Int!) {
      categorySection(context: $context, cycle: $cycle) { categories { id label target } } }
    """
    static let cardSection = """
    query cardSection($context: String!, $category: String!, $cycle: Int!, $filterOptions: FilterOptions, $page: Int = 1,
                      $size: Int = 12, $lastPromotionCodes: [Int] = []) {
      cardSection(context: $context category: $category cycle: $cycle filterOptions: $filterOptions page: $page size: $size
                  lastPromotionCodes: $lastPromotionCodes) {
        cards { name brand code points image type
          products { code name image brand points purchasePrice { from to } resalePrice { from to } }
          purchasePrice { from to } resalePrice { from to } }
        totalItens totalPages } }
    """
}

/// URLSession efímera que **no sigue redirecciones** (las sigue `NaturaClient` para juntar cookies).
final class NaturaHTTP: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.timeoutIntervalForRequest = 30
        return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }()

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (data, http)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest) async -> URLRequest? {
        nil
    }
}
