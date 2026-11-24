import Foundation

/// Normalizadores espejo de backend/src/modules/*/domain/normalize-*.ts (repo mynatura).
public enum Normalize {
    /// Quita "#" inicial y espacios: "# 70983" → "70983".
    public static func naturaSku(_ value: String) -> String {
        var text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("#") {
            text.removeFirst()
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Solo dígitos.
    public static func ean(_ value: String) -> String {
        value.filter(\.isASCIIDigit)
    }

    /// Dígitos y K en mayúscula: "12.345.678-k" → "12345678K".
    public static func rut(_ value: String) -> String {
        value.uppercased().filter { $0.isASCIIDigit || $0 == "K" }
    }

    /// Minúsculas, sin tildes, espacios colapsados. Para autocompletar y detectar duplicados.
    public static func customerName(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es_CL"))
            .lowercased()
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    /// Código escaneado en recepción: todo dígitos → EAN; si no → SKU.
    public static func scanCode(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, trimmed.allSatisfy(\.isASCIIDigit) {
            return ean(trimmed)
        }
        return naturaSku(trimmed)
    }

    /// Largo mínimo aceptado por el backend para un código de recepción.
    public static let minimumScanCodeLength = 5
}
