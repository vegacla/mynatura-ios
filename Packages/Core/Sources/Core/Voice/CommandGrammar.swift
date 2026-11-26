import Foundation

/// Texto transcrito → comandos, según la pantalla (`VoiceContext`).
/// Cubre el editor de pedido de cliente, la recepción y la conciliación; los demás contextos devuelven `.unrecognized` por ahora.
public enum CommandGrammar {
    static let maximumQuantity = 99
    /// Un "a quince" no es un precio creíble; bajo esto se deja como texto.
    static let minimumPrice = 100

    static let leadingFillers: Set<String> = [
        "y", "e", "tambien", "ademas", "mas", "luego", "despues", "ah", "eh", "bueno", "ya", "ok", "oye", "entonces", "ahora",
    ]
    static let trailingFillers: Set<String> = ["mas", "po", "porfa", "nomas", "gracias"]
    static let donePhrases: Set<String> = [
        "listo", "lista", "eso es todo", "eso seria todo", "eso seria", "nada mas", "terminar", "termina", "terminamos", "fin",
    ]
    static let undoVerbs: Set<String> = ["deshacer", "deshaz", "deshace", "deshacelo"]
    static let undoPhrases: Set<String> = [
        "borra eso", "borra lo ultimo", "no eso", "eso no", "anula eso", "quita lo ultimo", "saca lo ultimo",
    ]
    static let noteKeywords: Set<String> = ["nota", "observacion"]
    static let repeatWords: Set<String> = ["otro", "otra", "otros", "otras"]
    static let repeatFillers: Set<String> = [
        "mas", "igual", "de", "ese", "esa", "eso", "lo", "mismo", "misma", "del", "el", "la", "vez",
    ]
    static let removeVerbs: Set<String> = [
        "quita", "quitar", "quitale", "saca", "sacar", "sacale", "elimina", "eliminar", "borra", "borrar",
    ]
    static let quantityVerbs: Set<String> = [
        "cambia", "cambiar", "cambiale", "sube", "subir", "subele", "baja", "bajar", "bajale", "deja", "dejar", "dejale",
    ]
    static let addVerbs: Set<String> = [
        "agrega", "agregar", "agregale", "agregame", "anade", "anadele", "anota", "pon", "ponle", "ponme", "suma", "sumale",
        "quiere", "quiero", "pide", "pidio", "lleva", "llevo", "va", "van", "mete", "metele", "echa", "echale", "dame",
        "necesita", "necesito", "otro", "otra", "otros", "otras", "tambien",
    ]
    static let honorifics: Set<String> = [
        "el", "la", "mi", "don", "dona", "senor", "senora", "senorita", "sr", "sra", "srta",
    ]
    /// Palabras que cierran el nombre del cliente ("para Juan, ciclo actual…").
    static let nameStoppers: Set<String> = ["ciclo", "nota", "quiere", "quiero", "pide", "pidio", "lleva", "va", "agrega", "agregale"]
    static let currentCycleWords: Set<String> = ["actual", "vigente", "este", "presente"]
    static let priceMarkers: Set<String> = ["a", "en"]
    static let leadingConnectors: Set<String> = [
        "del", "de", "el", "la", "los", "las", "lo", "codigo", "numero", "unidades", "unidad", "x", "por", "producto", "productos",
    ]
    static let trailingConnectors: Set<String> = ["de", "del", "unidades", "unidad"]

    public static func interpret(_ utterance: String, context: VoiceContext) -> [VoiceCommand] {
        UtteranceSegmenter.segments(VoiceText.tokenize(utterance)).flatMap { segment in
            interpret(segment: segment, context: context)
        }
    }

    static func interpret(segment: [VoiceToken], context: VoiceContext) -> [VoiceCommand] {
        switch context {
        case .customerOrder:
            return customerOrderCommands(segment)
        case .receiving:
            return receivingCommands(segment)
        case .reconciliation:
            return reconciliationCommands(segment)
        case .naturaDraft, .cart, .global:
            let text = VoiceText.joinRaw(segment)
            return text.isEmpty ? [] : [.unrecognized(text)]
        }
    }

    // MARK: - Pedido de cliente

    static func customerOrderCommands(_ segment: [VoiceToken]) -> [VoiceCommand] {
        var words = Array(segment.drop { $0.isSeparator || leadingFillers.contains($0.text) })
        guard let first = words.first else { return [] }

        if let note = noteCommand(words) { return [note] }

        let joined = words.map(\.text).joined(separator: " ")
        if donePhrases.contains(joined) { return [.done] }
        if undoVerbs.contains(first.text) || undoPhrases.contains(joined) { return [.undo] }
        if let repeatCommand = repeatLastCommand(words) { return [repeatCommand] }

        words = dropTrailingFillers(words)
        guard let head = words.first else { return [] }

        if let prefix = customerPrefixLength(words) {
            return customerCommands(words, prefix: prefix)
        }
        if head.text == "ciclo" {
            return cycleCommands(words)
        }
        if removeVerbs.contains(head.text) {
            guard let product = extractItem(Array(words.dropFirst())).product else {
                return [.unrecognized(VoiceText.joinRaw(words))]
            }
            return [.removeLine(product)]
        }
        if quantityVerbs.contains(head.text) {
            return [setQuantityCommand(words)]
        }
        return [addLineCommand(words)]
    }

    static func noteCommand(_ words: [VoiceToken]) -> VoiceCommand? {
        let texts = words.map(\.text)
        var bodyStart: Int?
        if let first = texts.first, noteKeywords.contains(first) {
            bodyStart = 1
        } else if texts.count > 1, texts[0] == "anota", texts[1] == "que" {
            bodyStart = 2
        }
        guard let bodyStart else { return nil }
        let note = VoiceText.joinRaw(words.dropFirst(bodyStart))
        return note.isEmpty ? .unrecognized(VoiceText.joinRaw(words)) : .note(note)
    }

    static func repeatLastCommand(_ words: [VoiceToken]) -> VoiceCommand? {
        guard let first = words.first else { return nil }
        if repeatWords.contains(first.text) {
            let rest = words.dropFirst().filter { !repeatFillers.contains($0.text) }
            if rest.isEmpty { return .repeatLast(quantity: 1) }
            if let number = SpanishNumberParser.parse(rest, at: 0), number.tokenCount == rest.count,
               (1...maximumQuantity).contains(number.value) {
                return .repeatLast(quantity: number.value)
            }
            return nil
        }
        // "dos más"
        if words.count >= 2, words.last?.text == "mas",
           let number = SpanishNumberParser.parse(words, at: 0), number.tokenCount == words.count - 1,
           (1...maximumQuantity).contains(number.value) {
            return .repeatLast(quantity: number.value)
        }
        return nil
    }

    static func dropTrailingFillers(_ words: [VoiceToken]) -> [VoiceToken] {
        var result = words
        while let last = result.last {
            if last.text == "favor", result.count >= 2, result[result.count - 2].text == "por" {
                result.removeLast(2)
            } else if trailingFillers.contains(last.text) {
                result.removeLast()
            } else {
                break
            }
        }
        return result
    }

    static func customerPrefixLength(_ words: [VoiceToken]) -> Int? {
        let texts = words.map(\.text)
        guard let first = texts.first else { return nil }
        if first == "para" || first == "cliente" || first == "clienta" { return 1 }
        if texts.count >= 2, first == "pedido", texts[1] == "de" || texts[1] == "para" { return 2 }
        if texts.count >= 2, first == "es", texts[1] == "para" { return 2 }
        return nil
    }

    /// "para la señora Ana Rojas dos del 12345" → cliente "Ana Rojas" + la línea que sigue.
    static func customerCommands(_ words: [VoiceToken], prefix: Int) -> [VoiceCommand] {
        var nameStart = prefix
        while nameStart < words.count, honorifics.contains(words[nameStart].text) {
            nameStart += 1
        }
        var nameEnd = nameStart
        while nameEnd < words.count,
              SpanishNumberParser.parse(words, at: nameEnd) == nil,
              !nameStoppers.contains(words[nameEnd].text) {
            nameEnd += 1
        }
        let name = VoiceText.joinRaw(words[nameStart..<nameEnd])
        guard !name.isEmpty else { return [.unrecognized(VoiceText.joinRaw(words))] }
        return [.setCustomer(name: name)] + continuation(Array(words[nameEnd...]))
    }

    static func cycleCommands(_ words: [VoiceToken]) -> [VoiceCommand] {
        let rest = Array(words.dropFirst())
        if let first = rest.first, currentCycleWords.contains(first.text) {
            return [.setCycle(.current)] + continuation(Array(rest.dropFirst()))
        }
        if let number = SpanishNumberParser.parse(rest, at: 0) {
            return [.setCycle(.number(number.value))] + continuation(Array(rest.dropFirst(number.tokenCount)))
        }
        return [.unrecognized(VoiceText.joinRaw(words))]
    }

    static func continuation(_ rest: [VoiceToken]) -> [VoiceCommand] {
        rest.isEmpty ? [] : customerOrderCommands(rest)
    }

    /// "sube a tres el Ekos" · "cambia el 12345 a cuatro" · "deja dos del 12345".
    static func setQuantityCommand(_ words: [VoiceToken]) -> VoiceCommand {
        let rest = Array(words.dropFirst())
        if rest.first?.text == "a", let number = SpanishNumberParser.parse(rest, at: 1),
           (0...maximumQuantity).contains(number.value),
           let product = extractItem(Array(rest.dropFirst(1 + number.tokenCount))).product {
            return .setQuantity(product: product, quantity: number.value)
        }
        if let marker = rest.lastIndex(where: { $0.text == "a" }), marker > 0,
           let number = SpanishNumberParser.parse(rest, at: marker + 1),
           marker + 1 + number.tokenCount == rest.count,
           (0...maximumQuantity).contains(number.value),
           let product = extractItem(Array(rest[..<marker])).product {
            return .setQuantity(product: product, quantity: number.value)
        }
        let item = extractItem(rest)
        if let quantity = item.quantity, let product = item.product {
            return .setQuantity(product: product, quantity: quantity)
        }
        return .unrecognized(VoiceText.joinRaw(words))
    }

    /// "agrega dos del 12345" · "un desodorante Humor" · "dos Kaiak clásico a nueve noventa".
    static func addLineCommand(_ words: [VoiceToken]) -> VoiceCommand {
        var body = Array(words.drop { addVerbs.contains($0.text) })
        var price: ParsedPrice?
        if body.count >= 3 {
            for index in stride(from: body.count - 2, through: 1, by: -1) where priceMarkers.contains(body[index].text) {
                if let parsed = SpanishNumberParser.parsePrice(body, at: index + 1),
                   index + 1 + parsed.tokenCount == body.count,
                   parsed.amount.pesos >= minimumPrice {
                    price = parsed
                    body = Array(body[..<index])
                    break
                }
            }
        }
        let item = extractItem(body)
        guard let product = item.product else { return .unrecognized(VoiceText.joinRaw(words)) }
        let quantity = item.quantity ?? 1
        guard (1...maximumQuantity).contains(quantity) else { return .unrecognized(VoiceText.joinRaw(words)) }
        return .addLine(quantity: quantity, product: product, price: price)
    }

    // MARK: - Recepción

    static let receivedVerbs: Set<String> = [
        "llegaron", "llego", "llegan", "llega", "vinieron", "vino", "recibi", "recibimos", "recibido", "recibidos",
        "recibidas", "recibe", "entraron", "entro",
    ]
    static let missingWords: Set<String> = ["falta", "faltan", "faltaron", "falto", "faltante", "faltantes"]
    static let completeWords: Set<String> = [
        "completo", "completos", "completa", "completas", "entero", "enteros", "todo", "todos", "todas",
    ]

    /// "llegaron cuatro del 87654" · "del Kaiak llegaron dos, falta uno" · "llegó completo el Ekos" ·
    /// "no llegó el 12345" · "otro más" · "Kaiak" (suma 1, como un escaneo).
    static func receivingCommands(_ segment: [VoiceToken]) -> [VoiceCommand] {
        var words = Array(segment.drop { $0.isSeparator || leadingFillers.contains($0.text) })
        guard let first = words.first else { return [] }
        let joined = words.map(\.text).joined(separator: " ")
        if donePhrases.contains(joined) { return [.done] }
        if undoVerbs.contains(first.text) || undoPhrases.contains(joined) { return [.undo] }

        // "otro más", "otros dos del 12345"
        if repeatWords.contains(first.text) {
            let rest = words.dropFirst().filter { !repeatFillers.contains($0.text) }
            let item = extractItem(rest)
            return [.receive(product: item.product, amount: .increment(item.quantity ?? 1))]
        }
        // "uno más del 12345", "dos más"
        if let number = SpanishNumberParser.parse(words, at: 0), number.tokenCount < words.count,
           words[number.tokenCount].text == "mas", isQuantity(number) {
            let rest = Array(words.dropFirst(number.tokenCount + 1))
            return [.receive(product: extractItem(rest).product, amount: .increment(number.value))]
        }

        words = dropTrailingFillers(words)
        guard !words.isEmpty else { return [] }

        // "no llegó el 12345"
        if words.count > 1, words[0].text == "no", receivedVerbs.contains(words[1].text) {
            let rest = Array(words.dropFirst(2))
            return [.receive(product: extractItem(rest).product, amount: .received(0))]
        }

        // "falta uno del Kaiak", "del 12345 faltan dos"
        if let marker = words.firstIndex(where: { missingWords.contains($0.text) }) {
            var missing = 1
            var restEnd = marker + 1
            if let number = SpanishNumberParser.parse(words, at: marker + 1), isQuantity(number) {
                missing = number.value
                restEnd = marker + 1 + number.tokenCount
            }
            let rest = (Array(words[..<marker]) + Array(words[restEnd...])).filter { !receivedVerbs.contains($0.text) }
            return [.receive(product: extractItem(rest).product, amount: .missing(missing))]
        }

        // "llegó completo el Ekos", "llegaron todos los Kaiak"
        if words.contains(where: { completeWords.contains($0.text) }) {
            let rest = words.filter { !completeWords.contains($0.text) && !receivedVerbs.contains($0.text) }
            return [.receive(product: extractItem(rest).product, amount: .complete)]
        }

        let rest = words.filter { !receivedVerbs.contains($0.text) }
        let item = extractItem(rest)
        if item.product == nil, item.quantity == nil {
            return [.unrecognized(VoiceText.joinRaw(words))]
        }
        if let quantity = item.quantity {
            return [.receive(product: item.product, amount: .received(quantity))]
        }
        return [.receive(product: item.product, amount: .increment(1))]
    }

    // MARK: - Conciliación

    static let countWords: Set<String> = [
        "conte", "contamos", "conto", "cuento", "conteo", "son", "hay", "tengo", "tenemos", "quedan", "queda",
        "fisico", "total", "stock", "no", "el", "la", "los", "las", "de", "del", "unidades", "unidad", "en",
    ]
    static let zeroWords: Set<String> = ["ninguno", "ninguna", "nada"]

    /// "conté siete" · "son doce unidades" · "no hay ninguno" · "nota: dos rotos".
    static func reconciliationCommands(_ segment: [VoiceToken]) -> [VoiceCommand] {
        var words = Array(segment.drop { $0.isSeparator || leadingFillers.contains($0.text) })
        guard let first = words.first else { return [] }
        if let note = noteCommand(words) { return [note] }
        let joined = words.map(\.text).joined(separator: " ")
        if donePhrases.contains(joined) { return [.done] }
        if undoVerbs.contains(first.text) || undoPhrases.contains(joined) { return [.undo] }

        words = dropTrailingFillers(words)
        let core = words.filter { !countWords.contains($0.text) }
        if !core.isEmpty, core.allSatisfy({ zeroWords.contains($0.text) }) {
            return [.physicalCount(0)]
        }
        if let number = SpanishNumberParser.parse(core, at: 0), number.tokenCount == core.count {
            return [.physicalCount(number.value)]
        }
        return [.unrecognized(VoiceText.joinRaw(words))]
    }

    // MARK: - Cantidad + producto

    struct Item: Equatable {
        var quantity: Int?
        var product: ProductRef?
    }

    struct NumberGroup {
        let start: Int
        let number: ParsedNumber
        var end: Int { start + number.tokenCount }
    }

    static func isCode(_ digits: String) -> Bool { (5...7).contains(digits.count) }

    static func isQuantity(_ number: ParsedNumber) -> Bool {
        (1...maximumQuantity).contains(number.value) && number.digits.count <= 2
    }

    /// Separa cantidad y producto. Un código Natura tiene 5–7 dígitos y puede venir en varios grupos
    /// ("ciento veintitrés cuarenta y cinco" → 12345); un número ≤ 99 al inicio o al final es la cantidad.
    static func extractItem(_ tokens: [VoiceToken]) -> Item {
        var groups: [NumberGroup] = []
        var index = 0
        while index < tokens.count {
            if let number = SpanishNumberParser.parse(tokens, at: index) {
                groups.append(NumberGroup(start: index, number: number))
                index += number.tokenCount
            } else {
                index += 1
            }
        }

        var consumed = Set<Int>()
        var quantity: Int?
        var quantityEnd: Int?
        var code: String?

        func consume(_ group: NumberGroup) {
            for position in group.start..<group.end {
                consumed.insert(position)
            }
        }

        var runStart = 0
        while code == nil, runStart < groups.count {
            var runEnd = runStart
            while runEnd + 1 < groups.count, groups[runEnd + 1].start == groups[runEnd].end {
                runEnd += 1
            }
            let run = Array(groups[runStart...runEnd])
            let allDigits = run.map { $0.number.digits }.joined()
            let afterFirst = run.dropFirst().map { $0.number.digits }.joined()
            let beforeLast = run.dropLast().map { $0.number.digits }.joined()

            if run.count >= 2, isQuantity(run[0].number), isCode(afterFirst) {
                // "dos 12345"
                quantity = run[0].number.value
                quantityEnd = run[0].end
                code = afterFirst
                for group in run { consume(group) }
            } else if run.count >= 2, let last = run.last, isQuantity(last.number), isCode(beforeLast) {
                // "12345 tres"
                quantity = last.number.value
                quantityEnd = last.end
                code = beforeLast
                for group in run { consume(group) }
            } else if isCode(allDigits) {
                code = allDigits
                for group in run { consume(group) }
            }
            runStart = runEnd + 1
        }

        if quantity == nil {
            let free = groups.filter { !consumed.contains($0.start) }
            if let first = free.first, first.start == 0, isQuantity(first.number) {
                quantity = first.number.value
                quantityEnd = first.end
                consume(first)
            } else if let last = free.last, last.start > 0, last.end == tokens.count, isQuantity(last.number) {
                quantity = last.number.value
                quantityEnd = last.end
                consume(last)
            } else if tokens.count >= 2, tokens[0].text == "media", tokens[1].text == "docena" {
                quantity = 6
                consumed.insert(0)
                consumed.insert(1)
            }
        }
        if let end = quantityEnd, let current = quantity, end < tokens.count,
           tokens[end].text == "docena" || tokens[end].text == "docenas" {
            quantity = current * 12
            consumed.insert(end)
        }

        let product: ProductRef?
        if let code {
            product = .sku(code)
        } else {
            var rest = tokens.indices.filter { !consumed.contains($0) }.map { tokens[$0] }
            while let first = rest.first, leadingConnectors.contains(first.text) {
                rest.removeFirst()
            }
            while let last = rest.last, trailingConnectors.contains(last.text) {
                rest.removeLast()
            }
            let text = VoiceText.joinRaw(rest)
            product = text.isEmpty ? nil : .text(text)
        }
        return Item(quantity: quantity, product: product)
    }
}
