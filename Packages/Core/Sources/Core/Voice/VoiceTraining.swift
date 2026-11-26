import Foundation

/// Frase de entrenamiento para el modelo de lenguaje personalizado, con su peso relativo.
public struct VoicePhrase: Equatable, Sendable {
    public let phrase: String
    public let count: Int

    public init(phrase: String, count: Int) {
        self.phrase = phrase
        self.count = count
    }
}

/// Frases para el modelo de lenguaje propio (V6 de docs/voice-interaction-proposal.md): nombres de productos,
/// códigos, clientes y las formas en que se dicen los comandos. Solo Foundation: el modelo se arma en iOS.
public enum VoiceTraining {
    public static let maximumProducts = 400
    public static let maximumCustomers = 200
    public static let maximumPhrases = 6000

    static let quantities = ["un", "dos", "tres", "cuatro", "cinco"]

    /// Palabras genéricas que se omiten para el nombre corto ("Desodorante Colonia Kaiak Clásico" → "Kaiak Clásico").
    static let genericWords: Set<String> = [
        "desodorante", "colonia", "perfume", "crema", "jabon", "en", "barra", "de", "del", "para", "gel", "locion",
        "aceite", "body", "splash", "shampoo", "acondicionador", "repuesto", "refill", "liquido", "corporal",
        "hidratante", "spray", "roll", "on", "la", "el", "y", "con",
    ]

    /// Comandos y consultas fijos, tal como se dicen.
    static let fixedPhrases = [
        "otro más", "listo", "eso es todo", "deshacer", "borra eso", "nota", "ciclo actual", "conté siete",
        "son doce unidades", "no hay ninguno", "falta uno", "llegó completo", "¿cuánto vendí hoy?",
        "¿cuánto vendí esta semana?", "¿cuánto vendí este mes?", "¿cuánto vendí la semana pasada?",
        "¿cuándo cierra el ciclo?", "nueve noventa", "doce mil novecientos noventa", "diez lucas",
    ]

    /// Nombre corto: sin palabras genéricas, máx. 3 palabras; nil si no cambia o queda vacío.
    public static func shortName(_ name: String) -> String? {
        let words = name.split(whereSeparator: \.isWhitespace).map(String.init)
        let kept = words.filter { !genericWords.contains(VoiceText.fold($0)) }.prefix(3)
        let short = kept.joined(separator: " ")
        guard !short.isEmpty, Normalize.customerName(short) != Normalize.customerName(name) else { return nil }
        return short
    }

    /// Frases ordenadas y sin repetidos (el orden de las entradas no cambia el resultado ni la versión).
    public static func phrases(productNames: [String], productCodes: [String], customerNames: [String]) -> [VoicePhrase] {
        var result: [VoicePhrase] = []
        var seen: [String: Int] = [:]

        func add(_ phrase: String, _ count: Int) {
            let trimmed = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = Normalize.customerName(trimmed)
            guard !key.isEmpty else { return }
            if let index = seen[key] {
                if result[index].count < count { result[index] = VoicePhrase(phrase: result[index].phrase, count: count) }
                return
            }
            seen[key] = result.count
            result.append(VoicePhrase(phrase: trimmed, count: count))
        }

        for phrase in fixedPhrases { add(phrase, 10) }
        for line in VoiceVocabulary.naturaLines { add(line, 20) }

        let customers = sortedUnique(customerNames).prefix(maximumCustomers)
        for customer in customers {
            add(customer, 15)
            add("para \(customer)", 10)
            add("¿qué me encargó \(customer)?", 5)
        }

        let fullNames = sortedUnique(productNames).prefix(maximumProducts)
        var names: [String] = []
        for name in fullNames {
            names.append(name)
            if let short = shortName(name) { names.append(short) }
        }
        for (index, name) in sortedUnique(names).enumerated() {
            let quantity = quantities[index % quantities.count]
            add(name, 20)
            add("\(quantity) \(name)", 10)
            add("llegaron \(quantity) del \(name)", 5)
            add("¿cuánto me queda de \(name)?", 5)
            add("quita el \(name)", 3)
            add("llegó completo el \(name)", 3)
        }

        let codes = sortedUnique(productCodes.map(Normalize.naturaSku)).prefix(maximumProducts)
        for (index, code) in codes.enumerated() {
            let quantity = quantities[index % quantities.count]
            add("\(quantity) del \(code)", 5)
            add("llegaron \(quantity) del \(code)", 3)
        }

        return Array(result.prefix(maximumPhrases))
    }

    /// Versión estable del conjunto de frases (FNV-1a de 64 bits en hex): cambia solo si cambian las frases.
    public static func version(of phrases: [VoicePhrase]) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for phrase in phrases {
            for byte in "\(phrase.phrase)|\(phrase.count)\n".utf8 {
                hash ^= UInt64(byte)
                hash = hash &* 0x0000_0100_0000_01b3
            }
        }
        let hex = String(hash, radix: 16)
        return String(repeating: "0", count: max(0, 16 - hex.count)) + hex
    }

    static func sortedUnique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in values.sorted(by: { Normalize.customerName($0) < Normalize.customerName($1) }) {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = Normalize.customerName(trimmed)
            guard !key.isEmpty, seen.insert(key).inserted else { continue }
            result.append(trimmed)
        }
        return result
    }
}
