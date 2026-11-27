import Foundation

/// Palabra leída por el OCR (Vision u otro), con su caja en coordenadas normalizadas 0…1 y **origen arriba a la izquierda**.
public struct OcrWord: Sendable, Equatable {
    public let text: String
    public let minX: Double
    public let maxX: Double
    public let minY: Double
    public let maxY: Double
    /// 0…1
    public let confidence: Double

    public init(text: String, minX: Double, maxX: Double, minY: Double, maxY: Double, confidence: Double) {
        self.text = text
        self.minX = minX
        self.maxX = maxX
        self.minY = minY
        self.maxY = maxY
        self.confidence = confidence
    }

    public var midX: Double { (minX + maxX) / 2 }
    public var midY: Double { (minY + maxY) / 2 }
    public var height: Double { maxY - minY }
}

/// Fila de la boleta: palabras con centro vertical parecido, de izquierda a derecha.
public struct OcrLine: Sendable, Equatable {
    public let words: [OcrWord]

    public init(words: [OcrWord]) { self.words = words.sorted { $0.minX < $1.minX } }

    public var text: String { words.map(\.text).joined(separator: " ") }
    public var confidence: Double { words.isEmpty ? 0 : words.reduce(0) { $0 + $1.confidence } / Double(words.count) }
}

/// Fila de producto extraída de la boleta (espejo de `ReceiptOcrExtractedRow` del backend).
public struct ReceiptOcrRow: Sendable, Equatable {
    public let naturaSku: String
    public let description: String
    public let quantity: Int?
    public let priceNormalPesos: Int?
    public let priceCyclePesos: Int?
    public let priceSalePesos: Int?
    public let rawText: String
    /// 0…1
    public let confidence: Double

    public init(naturaSku: String, description: String, quantity: Int?, priceNormalPesos: Int?, priceCyclePesos: Int?,
                priceSalePesos: Int?, rawText: String, confidence: Double) {
        self.naturaSku = naturaSku
        self.description = description
        self.quantity = quantity
        self.priceNormalPesos = priceNormalPesos
        self.priceCyclePesos = priceCyclePesos
        self.priceSalePesos = priceSalePesos
        self.rawText = rawText
        self.confidence = confidence
    }
}

/// Línea del pedido contra la que se cruzan las filas leídas.
public struct ReceiptOcrOrderLine: Sendable, Equatable {
    public let id: String
    public let naturaSku: String
    public let quantity: Int

    public init(id: String, naturaSku: String, quantity: Int) {
        self.id = id
        self.naturaSku = naturaSku
        self.quantity = quantity
    }
}

/// Propuesta para una línea del pedido: la consultora decide si la acepta.
public struct ReceiptOcrProposal: Sendable, Equatable {
    public let lineId: String
    public let naturaSku: String
    public let suggestedPesos: Int?
    public let receivedQuantity: Int?
    public let confidence: Double

    public init(lineId: String, naturaSku: String, suggestedPesos: Int?, receivedQuantity: Int?, confidence: Double) {
        self.lineId = lineId
        self.naturaSku = naturaSku
        self.suggestedPesos = suggestedPesos
        self.receivedQuantity = receivedQuantity
        self.confidence = confidence
    }
}

public struct ReceiptOcrMatch: Sendable, Equatable {
    public let proposals: [ReceiptOcrProposal]
    /// SKU leídos con datos útiles que no están en el pedido.
    public let unmatchedSkus: [String]

    public var status: ReceiptOcrStatus { proposals.isEmpty ? .failed : .succeeded }
}

/// Lectura de la boleta impresa del pedido (M4, espejo de `natura-order-receipt-ocr.ts` y
/// `apply-order-receipt-ocr.ts` del backend). El OCR lo hace Vision en el iPhone; aquí solo se interpreta.
public enum ReceiptOcr {
    // MARK: - Filas

    /// Agrupa palabras en filas por su centro vertical (Vision entrega columnas de una tabla como textos separados).
    public static func lines(from words: [OcrWord]) -> [OcrLine] {
        let sorted = words
            .filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
            .sorted { $0.midY < $1.midY }
        var groups: [[OcrWord]] = []
        var centers: [Double] = []
        var heights: [Double] = []
        for word in sorted {
            if let last = groups.indices.last,
               abs(word.midY - centers[last]) <= max(heights[last], word.height) * 0.5 {
                groups[last].append(word)
                let count = Double(groups[last].count)
                centers[last] += (word.midY - centers[last]) / count
                heights[last] += (word.height - heights[last]) / count
            } else {
                groups.append([word])
                centers.append(word.midY)
                heights.append(word.height)
            }
        }
        return groups.map(OcrLine.init(words:))
    }

    /// Puntaje para elegir la orientación correcta de la foto: palabras de la boleta, SKU y montos.
    public static func score(text: String) -> Int {
        let normalized = normalize(text)
        let keywords = ["codigo", "descripcion", "cant", "precio ciclo", "precio venta", "natura", "subtotal"]
        let keywordScore = keywords.reduce(0) { normalized.contains($1) ? $0 + 10 : $0 }
        let skuMatches = matches(#"\b\d{5,6}\b"#, in: normalized).count
        let moneyMatches = matches(moneyPattern, in: normalized).count
        return keywordScore + skuMatches * 2 + moneyMatches
    }

    /// Filas de producto: por columnas si se encuentra el encabezado; si no, por el texto de cada fila.
    public static func extractRows(from words: [OcrWord]) -> [ReceiptOcrRow] {
        let grouped = lines(from: words)
        let byColumns = extractRows(lines: grouped)
        return byColumns.isEmpty ? extractRows(rawText: grouped.map(\.text).joined(separator: "\n")) : byColumns
    }

    struct ColumnStarts: Equatable {
        var description = Double.infinity
        var quantity = Double.infinity
        var priceNormal = Double.infinity
        var priceCycle = Double.infinity
        var priceSale = Double.infinity
    }

    static func columnStarts(_ lines: [OcrLine]) -> ColumnStarts? {
        guard let header = lines.first(where: {
            let text = normalize($0.text)
            return text.contains("codigo") && text.contains("descripcion") && text.contains("precio")
        }) else { return nil }
        var starts = ColumnStarts()
        for (index, word) in header.words.enumerated() {
            let text = normalize(word.text)
            // "Precio Normal": la columna parte en "Precio", no en "Normal".
            var priceStart = word.minX
            if index > 0, normalize(header.words[index - 1].text).hasPrefix("precio") {
                priceStart = header.words[index - 1].minX
            }
            if text.contains("descripcion") { starts.description = min(starts.description, word.minX) }
            if text.contains("cant") { starts.quantity = min(starts.quantity, word.minX) }
            if text.contains("normal") { starts.priceNormal = min(starts.priceNormal, priceStart) }
            if text.contains("ciclo") { starts.priceCycle = min(starts.priceCycle, priceStart) }
            if text.contains("venta") { starts.priceSale = min(starts.priceSale, priceStart) }
        }
        guard starts.description.isFinite, starts.quantity.isFinite, starts.priceNormal.isFinite, starts.priceCycle.isFinite
        else { return nil }
        return starts
    }

    static func extractRows(lines: [OcrLine]) -> [ReceiptOcrRow] {
        guard let starts = columnStarts(lines) else { return [] }
        var rows: [ReceiptOcrRow] = []
        for line in lines {
            guard let skuWord = line.words.first(where: { longestDigitRun($0.text) >= 5 }),
                  skuWord.minX < starts.description else { continue }
            let sku = skuWord.text.filter(\.isASCIIDigit)
            guard sku.count >= 5 else { continue }

            func words(from lower: Double, to upper: Double) -> [String] {
                line.words.filter { $0.midX >= lower && $0.midX < upper }.map(\.text)
            }
            let description = words(from: starts.description, to: starts.quantity).joined(separator: " ")
                .trimmingCharacters(in: .whitespaces)
            guard !description.isEmpty else { continue }
            let quantity = integer(words(from: starts.quantity, to: starts.priceNormal).joined(separator: " "))
            let normal = words(from: starts.priceNormal, to: starts.priceCycle).lazy.compactMap(money).first
            let cycle = words(from: starts.priceCycle, to: starts.priceSale).lazy.compactMap(money).first
            let sale = words(from: starts.priceSale, to: .infinity).lazy.compactMap(money).first
            rows.append(ReceiptOcrRow(naturaSku: sku, description: description, quantity: quantity,
                                      priceNormalPesos: normal, priceCyclePesos: cycle, priceSalePesos: sale,
                                      rawText: line.text, confidence: line.confidence))
        }
        return dedupeBySku(rows)
    }

    /// Respaldo sin encabezado: SKU, descripción, cantidad (1–2 dígitos antes del primer monto) y montos en orden.
    public static func extractRows(rawText: String) -> [ReceiptOcrRow] {
        var rows: [ReceiptOcrRow] = []
        let lines = rawText.components(separatedBy: .newlines)
            .map { $0.replacingOccurrences(of: "|", with: " ").split(whereSeparator: \.isWhitespace).joined(separator: " ") }
            .filter { !$0.isEmpty }
        for line in lines {
            guard let skuRange = matches(#"\b\d{5,6}\b"#, in: line).first else { continue }
            let sku = String(line[skuRange])
            let afterSku = String(line[skuRange.upperBound...]).trimmingCharacters(in: .whitespaces)
            let moneyRanges = matches(moneyPattern, in: afterSku)
            guard let firstMoney = moneyRanges.first else { continue }
            let prefix = String(afterSku[..<firstMoney.lowerBound]).trimmingCharacters(in: .whitespaces)
            let quantityRange = matches(#"\b\d{1,2}\b"#, in: prefix).last
            let quantity = quantityRange.flatMap { Int(prefix[$0]) }
            let description = (quantityRange.map { String(prefix[..<$0.lowerBound]) } ?? prefix)
                .trimmingCharacters(in: .whitespaces)
            guard !description.isEmpty else { continue }
            let prices = moneyRanges.compactMap { money(String(afterSku[$0])) }
            rows.append(ReceiptOcrRow(naturaSku: sku, description: description, quantity: quantity,
                                      priceNormalPesos: prices.first, priceCyclePesos: prices.count > 1 ? prices[1] : nil,
                                      priceSalePesos: prices.last, rawText: line, confidence: 0.55))
        }
        return dedupeBySku(rows)
    }

    // MARK: - Propuestas

    /// Precio de venta unitario propuesto (`resolveSuggestedSaleUnitPrice` del backend).
    public static func suggestedSalePrice(_ row: ReceiptOcrRow) -> Int? {
        if let quantity = row.quantity, quantity > 1 {
            if let cycle = row.priceCyclePesos, cycle > 0, cycle % quantity == 0 { return cycle / quantity }
            if let sale = row.priceSalePesos, sale > 0, sale % quantity == 0 { return sale / quantity }
        }
        if let cycle = row.priceCyclePesos, cycle > 0 { return cycle }
        if let sale = row.priceSalePesos, sale > 0, row.quantity == 1, row.priceNormalPesos != sale { return sale }
        return nil
    }

    /// Cantidad recibida propuesta, sin pasar lo pedido.
    public static func receivedQuantity(_ row: ReceiptOcrRow, max ordered: Int?) -> Int? {
        guard let quantity = row.quantity, quantity >= 0 else { return nil }
        return ordered.map { min($0, quantity) } ?? quantity
    }

    /// Cruza las filas leídas con las líneas del pedido por SKU.
    public static func match(rows: [ReceiptOcrRow], lines: [ReceiptOcrOrderLine]) -> ReceiptOcrMatch {
        var lineBySku: [String: ReceiptOcrOrderLine] = [:]
        for line in lines where lineBySku[skuKey(line.naturaSku)] == nil { lineBySku[skuKey(line.naturaSku)] = line }
        var proposals: [ReceiptOcrProposal] = []
        var unmatched: [String] = []
        for row in rows {
            let line = lineBySku[skuKey(row.naturaSku)]
            let price = suggestedSalePrice(row)
            let quantity = receivedQuantity(row, max: line?.quantity)
            guard price != nil || quantity != nil else { continue }
            if let line {
                proposals.append(ReceiptOcrProposal(lineId: line.id, naturaSku: line.naturaSku, suggestedPesos: price,
                                                    receivedQuantity: quantity, confidence: row.confidence))
            } else {
                unmatched.append(row.naturaSku)
            }
        }
        return ReceiptOcrMatch(proposals: proposals, unmatchedSkus: unmatched)
    }

    // MARK: - Ayudas

    static let moneyPattern = #"\b\d{1,3}(?:[.,]\d{3})+\b"#

    static func skuKey(_ sku: String) -> String {
        let digits = Normalize.naturaSku(sku).filter(\.isASCIIDigit)
        let trimmed = digits.drop { $0 == "0" }
        return trimmed.isEmpty ? Normalize.naturaSku(sku).lowercased() : String(trimmed)
    }

    static func normalize(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es_CL"))
            .lowercased()
            .replacingOccurrences(of: "|", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    /// Monto CLP con separador de miles ("12.990", "$1.234.567"); nil si el texto no lo trae.
    static func money(_ text: String) -> Int? {
        guard let range = matches(moneyPattern, in: text).first else { return nil }
        return Int(text[range].filter(\.isASCIIDigit))
    }

    static func integer(_ text: String) -> Int? {
        let digits = text.filter(\.isASCIIDigit)
        return digits.isEmpty ? nil : Int(digits)
    }

    static func longestDigitRun(_ text: String) -> Int {
        var best = 0
        var current = 0
        for character in text {
            current = character.isASCIIDigit ? current + 1 : 0
            best = max(best, current)
        }
        return best
    }

    static func dedupeBySku(_ rows: [ReceiptOcrRow]) -> [ReceiptOcrRow] {
        var order: [String] = []
        var best: [String: ReceiptOcrRow] = [:]
        for row in rows {
            if let current = best[row.naturaSku] {
                if row.confidence > current.confidence { best[row.naturaSku] = row }
            } else {
                order.append(row.naturaSku)
                best[row.naturaSku] = row
            }
        }
        return order.compactMap { best[$0] }
    }

    static func matches(_ pattern: String, in text: String) -> [Range<String.Index>] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            .compactMap { Range($0.range, in: text) }
    }
}
