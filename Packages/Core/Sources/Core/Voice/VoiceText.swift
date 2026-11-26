import Foundation

/// Palabra (o separador) de una transcripción de voz.
/// `raw` conserva mayúsculas y tildes (para notas y nombres); `text` va normalizado (minúsculas, sin tildes).
public struct VoiceToken: Equatable, Sendable {
    public enum Kind: Equatable, Sendable { case word, separator }

    public let raw: String
    public let text: String
    public let kind: Kind

    public init(raw: String, kind: Kind = .word) {
        self.raw = raw
        self.text = kind == .word ? VoiceText.fold(raw) : raw
        self.kind = kind
    }

    public var isSeparator: Bool { kind == .separator }
}

/// Utilidades de texto para la voz: normalización, tokens, clave fonética y distancia de edición.
public enum VoiceText {
    private static let separatorCharacters: Set<Character> = [",", ";", ":", "!", "?", "\n"]
    private static let ignoredCharacters: Set<Character> = ["¿", "¡", "\"", "“", "”", "(", ")", "«", "»"]

    /// Minúsculas y sin tildes ("Clásico" → "clasico", "señora" → "senora").
    public static func fold(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es_CL"))
            .lowercased()
    }

    /// "Para Juan, dos del 12.345." → para · juan · , · dos · del · 12.345 · .
    /// El punto o la coma entre dígitos son parte del número ("12.990").
    public static func tokenize(_ utterance: String) -> [VoiceToken] {
        let characters = Array(utterance)
        var tokens: [VoiceToken] = []
        var word = ""

        func flushWord() {
            if !word.isEmpty {
                tokens.append(VoiceToken(raw: word))
                word = ""
            }
        }

        for index in characters.indices {
            let character = characters[index]
            if ignoredCharacters.contains(character) { continue }
            if character == "." || character == "," {
                let previousIsDigit = index > 0 && characters[index - 1].isASCIIDigit
                let nextIsDigit = index + 1 < characters.count && characters[index + 1].isASCIIDigit
                if previousIsDigit && nextIsDigit {
                    word.append(character)
                } else {
                    flushWord()
                    tokens.append(VoiceToken(raw: String(character), kind: .separator))
                }
                continue
            }
            if separatorCharacters.contains(character) {
                flushWord()
                tokens.append(VoiceToken(raw: String(character), kind: .separator))
                continue
            }
            if character.isWhitespace {
                flushWord()
                continue
            }
            word.append(character)
        }
        flushWord()
        return tokens
    }

    /// Clave fonética simple del español de Chile, para comparar palabras como suenan y tolerar
    /// errores de transcripción: "umor" ≈ "humor", "ecos" ≈ "ekos", "cronos" ≈ "chronos", "vaya" ≈ "baya".
    public static func phoneticKey(_ value: String) -> String {
        let characters = Array(fold(value))
        var output: [Character] = []
        var index = 0

        func character(at offset: Int) -> Character? {
            let position = index + offset
            return position < characters.count ? characters[position] : nil
        }

        while index < characters.count {
            let current = characters[index]
            let next = character(at: 1)
            var step = 1
            switch current {
            case "h":
                break
            case "c":
                if next == "h" {
                    // "chr" suena "kr" (Chronos); el resto de "ch" queda como sonido propio.
                    output.append(character(at: 2) == "r" ? "k" : "C")
                    step = 2
                } else {
                    output.append(next == "e" || next == "i" ? "s" : "k")
                }
            case "q":
                output.append("k")
                if next == "u" { step = 2 }
            case "g":
                if next == "e" || next == "i" {
                    output.append("j")
                } else {
                    output.append("g")
                    if next == "u", let third = character(at: 2), third == "e" || third == "i" { step = 2 }
                }
            case "z":
                output.append("s")
            case "v":
                output.append("b")
            case "w":
                output.append("u")
            case "x":
                output.append("k")
                output.append("s")
            case "y":
                if let next, isVowel(next) {
                    output.append("y")
                } else {
                    output.append("i")
                }
            case "l":
                if next == "l" {
                    output.append("y")
                    step = 2
                } else {
                    output.append("l")
                }
            default:
                output.append(current)
            }
            index += step
        }

        var collapsed: [Character] = []
        for character in output where collapsed.last != character {
            collapsed.append(character)
        }
        return String(collapsed)
    }

    /// Distancia de Levenshtein entre dos cadenas.
    public static func editDistance(_ lhs: String, _ rhs: String) -> Int {
        let left = Array(lhs)
        let right = Array(rhs)
        if left.isEmpty { return right.count }
        if right.isEmpty { return left.count }
        var previous = Array(0...right.count)
        var current = [Int](repeating: 0, count: right.count + 1)
        for i in 1...left.count {
            current[0] = i
            for j in 1...right.count {
                let cost = left[i - 1] == right[j - 1] ? 0 : 1
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
            }
            swap(&previous, &current)
        }
        return previous[right.count]
    }

    static func isVowel(_ character: Character) -> Bool {
        "aeiou".contains(character)
    }

    /// Une palabras conservando lo dictado ("entregar el viernes, en la tarde"); quita separadores al inicio y al final.
    static func joinRaw<S: Sequence>(_ tokens: S) -> String where S.Element == VoiceToken {
        var output = ""
        for token in tokens {
            if token.isSeparator {
                if !output.isEmpty { output += token.raw }
            } else {
                output += output.isEmpty ? token.raw : " " + token.raw
            }
        }
        while let last = output.last, ",;:.!?".contains(last) {
            output.removeLast()
        }
        return output.trimmingCharacters(in: .whitespaces)
    }
}
