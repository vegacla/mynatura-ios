/// Monto en pesos chilenos enteros.
/// Los campos `*Cents` del backend son en realidad pesos (Natura entrega "$12.990" → 12990).
public struct Money: Hashable, Comparable, Sendable, Codable {
    public let pesos: Int

    public init(pesos: Int) {
        self.pesos = pesos
    }

    public static let zero = Money(pesos: 0)

    public static func < (lhs: Money, rhs: Money) -> Bool { lhs.pesos < rhs.pesos }

    public static func + (lhs: Money, rhs: Money) -> Money { Money(pesos: lhs.pesos + rhs.pesos) }

    public static func * (lhs: Money, rhs: Int) -> Money { Money(pesos: lhs.pesos * rhs) }

    /// Formato es-CL determinista ("$12.990", "-$500"), independiente del locale del sistema.
    public var formatted: String {
        let digits = String(abs(pesos))
        var grouped = ""
        for (index, character) in digits.enumerated() {
            if index > 0, (digits.count - index) % 3 == 0 {
                grouped.append(".")
            }
            grouped.append(character)
        }
        return (pesos < 0 ? "-$" : "$") + grouped
    }

    /// Parsea textos como "$12.990", "12990" o "12.990". Devuelve nil si no hay dígitos.
    public static func parse(_ text: String) -> Money? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let isNegative = trimmed.hasPrefix("-")
        let digits = trimmed.filter(\.isASCIIDigit)
        guard !digits.isEmpty, let value = Int(digits) else { return nil }
        return Money(pesos: isNegative ? -value : value)
    }
}

extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
}
