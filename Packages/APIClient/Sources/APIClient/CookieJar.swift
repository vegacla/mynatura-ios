import Foundation

/// Manejo mínimo de cookies: guarda `nombre → valor` a partir de cabeceras Set-Cookie.
public enum CookieJar {
    /// Aplica una cabecera Set-Cookie (posiblemente varias unidas por ", ") al jar.
    /// Cookies con valor vacío, Max-Age ≤ 0 o Expires en el pasado se eliminan.
    public static func apply(setCookie header: String, to jar: [String: String], now: Date = Date()) -> [String: String] {
        var result = jar
        for cookie in split(header) {
            let parts = cookie.split(separator: ";", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            guard let pair = parts.first, let equals = pair.firstIndex(of: "=") else { continue }
            let name = String(pair[..<equals])
            let value = String(pair[pair.index(after: equals)...])
            guard !name.isEmpty else { continue }

            var expired = value.isEmpty
            for attribute in parts.dropFirst() {
                let pieces = attribute.split(separator: "=", maxSplits: 1).map(String.init)
                guard pieces.count == 2 else { continue }
                switch pieces[0].lowercased() {
                case "max-age":
                    if let seconds = Int(pieces[1]), seconds <= 0 { expired = true }
                case "expires":
                    if let date = parseExpires(pieces[1]), date <= now { expired = true }
                default:
                    break
                }
            }
            result[name] = expired ? nil : value
        }
        return result
    }

    /// Valor para la cabecera Cookie ("a=1; b=2"), o nil si el jar está vacío.
    public static func header(for jar: [String: String]) -> String? {
        guard !jar.isEmpty else { return nil }
        return jar.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: "; ")
    }

    /// Separa cookies unidas por coma sin romper fechas "Expires=Thu, 01 Jan 1970 …".
    static func split(_ header: String) -> [String] {
        var cookies: [String] = []
        var current = ""
        var index = header.startIndex
        while index < header.endIndex {
            let character = header[index]
            if character == ",", startsNewCookie(header[header.index(after: index)...]) {
                cookies.append(current)
                current = ""
            } else {
                current.append(character)
            }
            index = header.index(after: index)
        }
        cookies.append(current)
        return cookies.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// Tras una coma empieza otra cookie si viene "token=" (sin espacios ni ';' antes del '=').
    private static func startsNewCookie(_ rest: Substring) -> Bool {
        let trimmed = rest.drop { $0 == " " }
        guard let equals = trimmed.firstIndex(of: "=") else { return false }
        let token = trimmed[..<equals]
        return !token.isEmpty && !token.contains { $0 == " " || $0 == ";" || $0 == "," }
    }

    private static func parseExpires(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        for format in ["EEE, dd MMM yyyy HH:mm:ss zzz", "EEEE, dd-MMM-yy HH:mm:ss zzz", "EEE, dd-MMM-yyyy HH:mm:ss zzz"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: value) { return date }
        }
        return nil
    }
}
