import Foundation

/// Revista digital pública del ciclo (docs/natura-order-placement.md §2.3, docs/natura-integration.md §4).
public enum NaturaMagazine {
    static let base = "https://cl.natura.digital-catalogue.com/consultoria/cl"

    /// Visor oficial del ciclo AAAACC con el código de la consultora (lo que Natura espera que se comparta).
    public static func viewerURL(cycleCode: Int, customerCode: String) -> URL? {
        guard let (year, cycle) = parts(cycleCode) else { return nil }
        var components = URLComponents(string: "\(base)/\(year)/\(cycle)/revista/ciclo-\(cycle)/view/index.html")
        var items = [URLQueryItem(name: "utm_term", value: "web")]
        let code = customerCode.trimmingCharacters(in: .whitespaces)
        if !code.isEmpty { items.insert(URLQueryItem(name: "id_consultora", value: code), at: 0) }
        components?.queryItems = items
        return components?.url
    }

    /// Revista completa en PDF (~46 MB).
    public static func pdfURL(cycleCode: Int) -> URL? {
        guard let (year, cycle) = parts(cycleCode) else { return nil }
        return URL(string: "\(base)/\(year)/\(cycle)/revista/ciclo-\(cycle)/view/common/data/catalogue.pdf")
    }

    /// Texto para WhatsApp u otra app.
    public static func shareMessage(cycleCode: Int, url: URL, customerName: String? = nil) -> String {
        let greeting = customerName.map { "Hola \($0)! " } ?? "Hola! "
        return greeting + "Te comparto la revista Natura del ciclo \(cycleCode % 100): \(url.absoluteString)\nResponde con los códigos que quieres y te los encargo."
    }

    /// Enlace de WhatsApp a un número chileno con el mensaje ya escrito (`wa.me`). nil si el número no sirve.
    public static func whatsAppURL(phone: String, text: String) -> URL? {
        var digits = phone.filter(\.isASCIIDigit)
        if digits.count == 9, digits.hasPrefix("9") { digits = "56" + digits }
        if digits.count == 8 { digits = "569" + digits }
        guard digits.count >= 11 else { return nil }
        var components = URLComponents(string: "https://wa.me/\(digits)")
        components?.queryItems = [URLQueryItem(name: "text", value: text)]
        return components?.url
    }

    /// 202619 → ("2026", "19"); 202701 → ("2027", "01").
    static func parts(_ cycleCode: Int) -> (String, String)? {
        let year = cycleCode / 100
        let cycle = cycleCode % 100
        guard (2000...2099).contains(year), (1...99).contains(cycle) else { return nil }
        return (String(year), String(format: "%02d", cycle))
    }
}
