import Foundation

/// Normaliza la URL del servidor ingresada a mano ("192.168.1.10:3000" → "http://192.168.1.10:3000").
public enum BackendURL {
    public static func parse(_ text: String) -> URL? {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !value.contains(" ") else { return nil }
        if !value.lowercased().hasPrefix("http://"), !value.lowercased().hasPrefix("https://") {
            value = "http://" + value
        }
        while value.hasSuffix("/") { value.removeLast() }
        guard let components = URLComponents(string: value),
              let host = components.host, !host.isEmpty,
              components.query == nil
        else { return nil }
        return components.url
    }
}
