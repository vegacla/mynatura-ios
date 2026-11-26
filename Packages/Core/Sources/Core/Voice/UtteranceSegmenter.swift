import Foundation

/// Corta una transcripción en trozos, uno por comando o línea:
/// "Para Juan, dos del 12345 y un Humor" → [para juan] [dos del 12345] [un humor].
public enum UtteranceSegmenter {
    /// Palabras que pueden separar líneas ("y", "más", "también"…).
    static let conjunctions: Set<String> = ["y", "mas", "tambien", "ademas", "luego", "despues"]

    /// Palabras que abren un comando o una línea nueva después de una conjunción.
    static let itemStarters: Set<String> = [
        "otro", "otra", "otros", "otras", "nota", "quita", "quitar", "quitale", "saca", "sacar", "sacale",
        "elimina", "eliminar", "borra", "borrar", "para", "cliente", "clienta", "agrega", "agregar", "agregale",
        "anade", "anota", "pon", "ponle", "suma", "cambia", "cambiar", "sube", "subir", "baja", "bajar",
        "deja", "dejar", "ciclo", "media", "listo", "deshacer", "deshaz", "del", "codigo",
        "llegaron", "llego", "llegan", "vinieron", "vino", "falta", "faltan", "no",
    ]

    /// "más" después de un número u "otro" es parte de la línea ("uno más del 12345", "otro más").
    static let moreAfter: Set<String> = ["otro", "otra", "otros", "otras"]

    /// Una nota se lleva el resto de la frase, con comas incluidas.
    static let noteKeywords: Set<String> = ["nota", "observacion"]

    /// Mínimo de dígitos para considerar que un trozo ya tiene un código Natura.
    static let codeDigits = 5

    public static func segments(_ tokens: [VoiceToken]) -> [[VoiceToken]] {
        // Números (con su largo) para no cortar "treinta y cinco" en el "y".
        var numberStarts: [Int: ParsedNumber] = [:]
        var insideNumber = Set<Int>()
        var index = 0
        while index < tokens.count {
            if let number = SpanishNumberParser.parse(tokens, at: index) {
                numberStarts[index] = number
                for covered in (index + 1)..<(index + number.tokenCount) {
                    insideNumber.insert(covered)
                }
                index += number.tokenCount
            } else {
                index += 1
            }
        }

        var segments: [[VoiceToken]] = []
        var current: [VoiceToken] = []
        var currentHasCode = false

        func close() {
            if !current.isEmpty { segments.append(current) }
            current = []
            currentHasCode = false
        }

        index = 0
        while index < tokens.count {
            let token = tokens[index]

            if current.isEmpty, !token.isSeparator, noteKeywords.contains(token.text) {
                segments.append(Array(tokens[index...]))
                return segments
            }
            if token.isSeparator {
                close()
                index += 1
                continue
            }
            let followsNumberOrRepeat = index > 0
                && (numberStarts[index - 1] != nil || insideNumber.contains(index - 1) || moreAfter.contains(tokens[index - 1].text))
            if conjunctions.contains(token.text), !insideNumber.contains(index),
               !(token.text == "mas" && followsNumberOrRepeat) {
                if current.isEmpty {
                    index += 1
                    continue
                }
                // Corta si lo que sigue abre una línea, o si este trozo ya tiene su código
                // ("dos del 12345 y desodorante Humor"). Así "jabón avena y miel" queda entero.
                if startsItem(at: index + 1, tokens, numberStarts) || currentHasCode {
                    close()
                    index += 1
                    continue
                }
            }
            if let number = numberStarts[index], number.digits.count >= codeDigits {
                currentHasCode = true
            }
            current.append(token)
            index += 1
        }
        close()
        return segments
    }

    static func startsItem(at index: Int, _ tokens: [VoiceToken], _ numberStarts: [Int: ParsedNumber]) -> Bool {
        guard index < tokens.count, !tokens[index].isSeparator else { return false }
        return numberStarts[index] != nil || itemStarters.contains(tokens[index].text)
    }
}
