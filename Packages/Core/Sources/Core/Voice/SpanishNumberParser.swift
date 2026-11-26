import Foundation

/// Número leído desde una transcripción.
public struct ParsedNumber: Equatable, Sendable {
    public let value: Int
    /// Dígitos tal como se dictaron; conserva ceros a la izquierda en códigos ("cero siete…" → "07…").
    public let digits: String
    /// Cuántos tokens ocupa ("treinta y cinco" → 3).
    public let tokenCount: Int
    /// Dictado dígito a dígito ("uno dos tres…") o escrito con cifras ("12345").
    public let isDigitSequence: Bool

    public init(value: Int, digits: String, tokenCount: Int, isDigitSequence: Bool) {
        self.value = value
        self.digits = digits
        self.tokenCount = tokenCount
        self.isDigitSequence = isDigitSequence
    }
}

/// Precio leído desde una transcripción.
public struct ParsedPrice: Equatable, Sendable {
    public let amount: Money
    public let tokenCount: Int
    /// Forma abreviada ("nueve noventa" → $9.990): la pantalla debe pedir confirmación.
    public let isShorthand: Bool

    public init(amount: Money, tokenCount: Int, isShorthand: Bool) {
        self.amount = amount
        self.tokenCount = tokenCount
        self.isShorthand = isShorthand
    }
}

/// Números del español de Chile: cardinales ("doce mil novecientos noventa"), cifras ("12.990"),
/// dígitos dictados ("uno dos tres cuatro cinco") y precios ("diez lucas", "nueve noventa").
public enum SpanishNumberParser {
    static let units: [String: Int] = [
        "un": 1, "uno": 1, "una": 1, "dos": 2, "tres": 3, "cuatro": 4,
        "cinco": 5, "seis": 6, "siete": 7, "ocho": 8, "nueve": 9,
    ]
    static let digitWords: [String: Int] = [
        "cero": 0, "uno": 1, "dos": 2, "tres": 3, "cuatro": 4,
        "cinco": 5, "seis": 6, "siete": 7, "ocho": 8, "nueve": 9,
    ]
    static let teens: [String: Int] = [
        "diez": 10, "once": 11, "doce": 12, "trece": 13, "catorce": 14, "quince": 15,
        "dieciseis": 16, "diecisiete": 17, "dieciocho": 18, "diecinueve": 19,
        "veinte": 20, "veintiun": 21, "veintiuno": 21, "veintiuna": 21, "veintidos": 22, "veintitres": 23,
        "veinticuatro": 24, "veinticinco": 25, "veintiseis": 26, "veintisiete": 27, "veintiocho": 28,
        "veintinueve": 29,
    ]
    static let tens: [String: Int] = [
        "treinta": 30, "cuarenta": 40, "cincuenta": 50, "sesenta": 60,
        "setenta": 70, "ochenta": 80, "noventa": 90,
    ]
    static let hundreds: [String: Int] = [
        "cien": 100, "ciento": 100,
        "doscientos": 200, "doscientas": 200, "trescientos": 300, "trescientas": 300,
        "cuatrocientos": 400, "cuatrocientas": 400, "quinientos": 500, "quinientas": 500,
        "seiscientos": 600, "seiscientas": 600, "setecientos": 700, "setecientas": 700,
        "ochocientos": 800, "ochocientas": 800, "novecientos": 900, "novecientas": 900,
    ]

    /// Mínimo de dígitos dictados seguidos para leerlos como código ("uno dos tres").
    static let minimumSpelledDigits = 3

    /// Número que empieza en `start`, o `nil` si ahí no hay uno.
    public static func parse(_ tokens: [VoiceToken], at start: Int) -> ParsedNumber? {
        guard start >= 0, start < tokens.count, !tokens[start].isSeparator else { return nil }
        if let literal = digitLiteral(tokens[start].text) {
            return ParsedNumber(value: Int(literal) ?? 0, digits: literal, tokenCount: 1, isDigitSequence: true)
        }
        if let spelled = spelledDigits(tokens, at: start) {
            return spelled
        }
        return cardinal(tokens, at: start)
    }

    /// La frase completa como número ("doce mil novecientos noventa" → 12990).
    public static func value(of phrase: String) -> Int? {
        let tokens = VoiceText.tokenize(phrase)
        guard let number = parse(tokens, at: 0), number.tokenCount == tokens.count else { return nil }
        return number.value
    }

    /// Precio que empieza en `start`: "9.990", "nueve mil novecientos noventa", "diez lucas",
    /// "nueve noventa" (abreviado → 9.990), con "pesos" opcional al final.
    public static func parsePrice(_ tokens: [VoiceToken], at start: Int) -> ParsedPrice? {
        guard let first = parse(tokens, at: start) else { return nil }
        var index = start + first.tokenCount
        var amount = first.value
        var isShorthand = false

        let nextWord = word(tokens, at: index)
        if nextWord == "luca" || nextWord == "lucas" {
            amount = first.value * 1000
            index += 1
        } else if !first.isDigitSequence, (1...99).contains(first.value),
                  let second = parse(tokens, at: index), !second.isDigitSequence {
            if (10...99).contains(second.value) {
                // "nueve noventa" = $9.990
                amount = first.value * 1000 + 900 + second.value
                isShorthand = true
                index += second.tokenCount
            } else if (100...999).contains(second.value) {
                // "doce novecientos noventa" = $12.990
                amount = first.value * 1000 + second.value
                isShorthand = true
                index += second.tokenCount
            }
        }

        let currency = word(tokens, at: index)
        if currency == "peso" || currency == "pesos" {
            index += 1
        }
        return ParsedPrice(amount: Money(pesos: amount), tokenCount: index - start, isShorthand: isShorthand)
    }

    static func word(_ tokens: [VoiceToken], at index: Int) -> String? {
        guard index < tokens.count, !tokens[index].isSeparator else { return nil }
        return tokens[index].text
    }

    /// "12345", "12.990", "$9.990" → solo dígitos.
    static func digitLiteral(_ text: String) -> String? {
        var body = Substring(text)
        if body.hasPrefix("$") { body = body.dropFirst() }
        guard let first = body.first, first.isASCIIDigit else { return nil }
        let digits = String(body.filter { $0 != "." && $0 != "," })
        guard !digits.isEmpty, digits.count <= 15, digits.allSatisfy({ $0.isASCIIDigit }) else { return nil }
        return digits
    }

    static func spelledDigits(_ tokens: [VoiceToken], at start: Int) -> ParsedNumber? {
        var digits = ""
        var index = start
        while index < tokens.count, !tokens[index].isSeparator, let digit = digitWords[tokens[index].text] {
            digits += String(digit)
            index += 1
        }
        guard digits.count >= minimumSpelledDigits else { return nil }
        return ParsedNumber(value: Int(digits) ?? 0, digits: digits, tokenCount: index - start, isDigitSequence: true)
    }

    private enum Part { case start, unit, teen, tens, hundred, thousand }

    static func cardinal(_ tokens: [VoiceToken], at start: Int) -> ParsedNumber? {
        var total = 0
        var current = 0
        var last = Part.start
        var index = start

        while index < tokens.count {
            let token = tokens[index]
            if token.isSeparator { break }
            let word = token.text

            if word == "cero", last == .start {
                return ParsedNumber(value: 0, digits: "0", tokenCount: 1, isDigitSequence: false)
            }
            if word == "y" {
                // Solo une decenas y unidades: "treinta y cinco".
                guard last == .tens, index + 1 < tokens.count, units[tokens[index + 1].text] != nil else { break }
                index += 1
                continue
            }
            if let value = units[word] {
                guard last == .start || last == .tens || last == .hundred || last == .thousand else { break }
                current += value
                last = .unit
            } else if let value = teens[word] {
                guard last == .start || last == .hundred || last == .thousand else { break }
                current += value
                last = .teen
            } else if let value = tens[word] {
                guard last == .start || last == .hundred || last == .thousand else { break }
                current += value
                last = .tens
            } else if let value = hundreds[word] {
                guard last == .start || last == .thousand else { break }
                current += value
                last = .hundred
            } else if word == "mil" {
                guard last != .thousand, total == 0 else { break }
                total = max(current, 1) * 1000
                current = 0
                last = .thousand
            } else {
                break
            }
            index += 1
        }

        guard index > start else { return nil }
        let value = total + current
        return ParsedNumber(value: value, digits: String(value), tokenCount: index - start, isDigitSequence: false)
    }
}
