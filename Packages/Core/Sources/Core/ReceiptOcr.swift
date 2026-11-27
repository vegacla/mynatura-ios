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

/// Formato de la boleta impresa.
public enum ReceiptLayout: Sendable, Equatable {
    /// El vigente, igual al Excel del pedido: `Cant.` · `Código` · `Descripción` · `Marca` · `Precio revista (uni.)` ·
    /// `Precio revista (total)` · `Precio CB (total)` · `Ganancia (total)`.
    case magazine
    /// El que leía el backend: `Código` · `Descripción` · `Cant.` · `Precio Normal` · `Precio Ciclo` · `Precio Venta`.
    case cycle
}

/// Fila de producto extraída de la boleta (espejo de `ReceiptOcrExtractedRow` del backend, más las columnas del
/// formato vigente).
public struct ReceiptOcrRow: Sendable, Equatable {
    public let naturaSku: String
    public let description: String
    public let quantity: Int?
    /// Formato `cycle`.
    public let priceNormalPesos: Int?
    public let priceCyclePesos: Int?
    public let priceSalePesos: Int?
    /// Formato `magazine`: precio revista unitario y total, y costo (precio CB) total de la línea.
    public let unitSalePesos: Int?
    public let totalSalePesos: Int?
    public let costTotalPesos: Int?
    public let rawText: String
    /// 0…1
    public let confidence: Double

    public init(naturaSku: String, description: String, quantity: Int?, priceNormalPesos: Int? = nil,
                priceCyclePesos: Int? = nil, priceSalePesos: Int? = nil, unitSalePesos: Int? = nil,
                totalSalePesos: Int? = nil, costTotalPesos: Int? = nil, rawText: String, confidence: Double) {
        self.naturaSku = naturaSku
        self.description = description
        self.quantity = quantity
        self.priceNormalPesos = priceNormalPesos
        self.priceCyclePesos = priceCyclePesos
        self.priceSalePesos = priceSalePesos
        self.unitSalePesos = unitSalePesos
        self.totalSalePesos = totalSalePesos
        self.costTotalPesos = costTotalPesos
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
        let keywords = ["codigo", "descrip", "cant", "precio revista", "precio cb", "ganancia", "marca",
                        "precio ciclo", "precio venta", "natura", "total"]
        let keywordScore = keywords.reduce(0) { normalized.contains($1) ? $0 + 10 : $0 }
        let skuMatches = matches(#"\b\d{5,6}\b"#, in: normalized).count
        let moneyMatches = matches(moneyPattern, in: normalized).count
        return keywordScore + skuMatches * 2 + moneyMatches
    }

    /// Filas de producto: por columnas si se encuentra el encabezado; si no, por el texto de cada fila.
    public static func extractRows(from words: [OcrWord]) -> [ReceiptOcrRow] {
        let grouped = lines(from: words)
        let header = header(in: grouped)
        let byColumns = header.map { extractRows(lines: grouped, header: $0) } ?? []
        if !byColumns.isEmpty { return byColumns }
        let text = grouped.map(\.text).joined(separator: "\n")
        return extractRows(rawText: text, layout: header?.layout ?? guessLayout(text))
    }

    struct Header: Equatable {
        var layout: ReceiptLayout
        var quantity = Double.infinity
        var sku = Double.infinity
        var description = Double.infinity
        var brand = Double.infinity
        /// Inicio de cada columna de precio, de izquierda a derecha (`magazine`: revista uni., revista total, CB, ganancia).
        var prices: [Double] = []
        /// `cycle`
        var priceNormal = Double.infinity
        var priceCycle = Double.infinity
        var priceSale = Double.infinity
    }

    static func header(in lines: [OcrLine]) -> Header? {
        guard let line = lines.first(where: {
            let text = normalize($0.text)
            return text.contains("codigo") && text.contains("descrip") && text.contains("precio")
        }) else { return nil }
        let text = normalize(line.text)
        let isCycle = (text.contains("normal") || text.contains("ciclo")) && !text.contains("revista")
        var header = Header(layout: isCycle ? .cycle : .magazine)
        for (index, word) in line.words.enumerated() {
            let token = normalize(word.text)
            // "Precio Normal": la columna parte en "Precio", no en "Normal".
            var priceStart = word.minX
            if index > 0, normalize(line.words[index - 1].text).hasPrefix("precio") {
                priceStart = line.words[index - 1].minX
            }
            if token.contains("cant") { header.quantity = min(header.quantity, word.minX) }
            if token.contains("codigo") { header.sku = min(header.sku, word.minX) }
            if token.contains("descrip") { header.description = min(header.description, word.minX) }
            if token.contains("marca") { header.brand = min(header.brand, word.minX) }
            if token.hasPrefix("precio") || token.hasPrefix("ganancia") { header.prices.append(word.minX) }
            if token.contains("normal") { header.priceNormal = min(header.priceNormal, priceStart) }
            if token.contains("ciclo") { header.priceCycle = min(header.priceCycle, priceStart) }
            if token.contains("venta") { header.priceSale = min(header.priceSale, priceStart) }
        }
        header.prices.sort()
        switch header.layout {
        case .magazine:
            guard header.description.isFinite, !header.prices.isEmpty else { return nil }
        case .cycle:
            guard header.description.isFinite, header.quantity.isFinite, header.priceNormal.isFinite,
                  header.priceCycle.isFinite else { return nil }
        }
        return header
    }

    static func guessLayout(_ text: String) -> ReceiptLayout {
        let normalized = normalize(text)
        if normalized.contains("revista") || normalized.contains("ganancia") || normalized.contains("precio cb") { return .magazine }
        if normalized.contains("precio ciclo") || normalized.contains("precio normal") { return .cycle }
        return .magazine
    }

    static func extractRows(lines: [OcrLine], header: Header) -> [ReceiptOcrRow] {
        var rows: [ReceiptOcrRow] = []
        for line in lines {
            guard let skuWord = line.words.first(where: { longestDigitRun($0.text) >= 5 && $0.midX < header.description })
            else { continue }
            let sku = skuWord.text.filter(\.isASCIIDigit)
            guard sku.count >= 5 else { continue }

            func words(from lower: Double, to upper: Double) -> [String] {
                line.words.filter { $0.midX >= lower && $0.midX < upper }.map(\.text)
            }
            switch header.layout {
            case .magazine:
                let firstPrice = header.prices[0]
                let description = words(from: header.description, to: min(header.brand, firstPrice))
                    .joined(separator: " ").trimmingCharacters(in: .whitespaces)
                guard !description.isEmpty, !isServiceFee(description) else { continue }
                // La cantidad es la primera columna, a la izquierda del código.
                let quantity = line.words.filter { $0.maxX <= skuWord.minX }.lazy.compactMap { amount($0.text) }.first
                let bounds = header.prices + [.infinity]
                let prices = (0..<header.prices.count).map {
                    words(from: bounds[$0], to: bounds[$0 + 1]).lazy.compactMap(amount).first
                }
                func price(_ index: Int) -> Int? { index < prices.count ? prices[index] : nil }
                rows.append(ReceiptOcrRow(naturaSku: sku, description: description, quantity: quantity,
                                          unitSalePesos: price(0), totalSalePesos: price(1), costTotalPesos: price(2),
                                          rawText: line.text, confidence: line.confidence))
            case .cycle:
                let description = words(from: header.description, to: header.quantity).joined(separator: " ")
                    .trimmingCharacters(in: .whitespaces)
                guard !description.isEmpty else { continue }
                let quantity = integer(words(from: header.quantity, to: header.priceNormal).joined(separator: " "))
                let normal = words(from: header.priceNormal, to: header.priceCycle).lazy.compactMap(money).first
                let cycle = words(from: header.priceCycle, to: header.priceSale).lazy.compactMap(money).first
                let sale = words(from: header.priceSale, to: .infinity).lazy.compactMap(money).first
                rows.append(ReceiptOcrRow(naturaSku: sku, description: description, quantity: quantity,
                                          priceNormalPesos: normal, priceCyclePesos: cycle, priceSalePesos: sale,
                                          rawText: line.text, confidence: line.confidence))
            }
        }
        return dedupeBySku(rows)
    }

    /// Respaldo sin encabezado: interpreta cada fila como texto, según el formato.
    public static func extractRows(rawText: String, layout: ReceiptLayout = .magazine) -> [ReceiptOcrRow] {
        let lines = rawText.components(separatedBy: .newlines)
            .map { $0.replacingOccurrences(of: "|", with: " ").split(whereSeparator: \.isWhitespace).joined(separator: " ") }
            .filter { !$0.isEmpty }
        let rows = lines.compactMap { layout == .magazine ? magazineRow(line: $0) : cycleRow(line: $0) }
        return dedupeBySku(rows)
    }

    /// "1 59313 BLUSH … 30 ML NATURA 9.090 9.090 6.824 2.266": cantidad, código, descripción (con la marca) y,
    /// al final, los montos (revista uni., revista total, CB total, ganancia).
    static func magazineRow(line: String) -> ReceiptOcrRow? {
        let tokens = line.split(separator: " ").map(String.init)
        guard let skuIndex = tokens.firstIndex(where: { $0.count >= 5 && $0.count <= 6 && $0.allSatisfy(\.isASCIIDigit) })
        else { return nil }
        var end = tokens.count
        while end > skuIndex + 1, tokens.count - end < 4, amount(tokens[end - 1]) != nil { end -= 1 }
        let amounts = tokens[end...].compactMap(amount)
        // Con un solo número al final podría ser parte de la descripción ("30 ML").
        guard amounts.count >= 2 else { return nil }
        let description = tokens[(skuIndex + 1)..<end].joined(separator: " ")
        guard !description.isEmpty, !isServiceFee(description) else { return nil }
        let quantity = skuIndex > 0 && tokens[skuIndex - 1].count <= 3 ? Int(tokens[skuIndex - 1]) : nil
        return ReceiptOcrRow(naturaSku: tokens[skuIndex], description: description, quantity: quantity,
                             unitSalePesos: amounts[0], totalSalePesos: amounts[1],
                             costTotalPesos: amounts.count > 2 ? amounts[2] : nil, rawText: line, confidence: 0.55)
    }

    /// Formato anterior (backend): SKU, descripción, cantidad (1–2 dígitos antes del primer monto) y montos en orden.
    static func cycleRow(line: String) -> ReceiptOcrRow? {
        guard let skuRange = matches(#"\b\d{5,6}\b"#, in: line).first else { return nil }
        let sku = String(line[skuRange])
        let afterSku = String(line[skuRange.upperBound...]).trimmingCharacters(in: .whitespaces)
        let moneyRanges = matches(moneyPattern, in: afterSku)
        guard let firstMoney = moneyRanges.first else { return nil }
        let prefix = String(afterSku[..<firstMoney.lowerBound]).trimmingCharacters(in: .whitespaces)
        let quantityRange = matches(#"\b\d{1,2}\b"#, in: prefix).last
        let quantity = quantityRange.flatMap { Int(prefix[$0]) }
        let description = (quantityRange.map { String(prefix[..<$0.lowerBound]) } ?? prefix)
            .trimmingCharacters(in: .whitespaces)
        guard !description.isEmpty else { return nil }
        let prices = moneyRanges.compactMap { money(String(afterSku[$0])) }
        return ReceiptOcrRow(naturaSku: sku, description: description, quantity: quantity,
                             priceNormalPesos: prices.first, priceCyclePesos: prices.count > 1 ? prices[1] : nil,
                             priceSalePesos: prices.last, rawText: line, confidence: 0.55)
    }

    /// "TASA DE SERVICIO" (código 1, todo en 0): no es producto (igual que en el Excel).
    static func isServiceFee(_ description: String) -> Bool {
        normalize(description).contains("tasa de servicio")
    }

    // MARK: - Propuestas

    /// Precio de venta unitario propuesto: el precio revista unitario; en el formato anterior,
    /// `resolveSuggestedSaleUnitPrice` del backend.
    public static func suggestedSalePrice(_ row: ReceiptOcrRow) -> Int? {
        // Formato vigente: el precio revista unitario viene impreso.
        if let unit = row.unitSalePesos, unit > 0 { return unit }
        if let total = row.totalSalePesos, total > 0, let quantity = row.quantity, quantity > 0, total % quantity == 0 {
            return total / quantity
        }
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

    /// Monto en una celda: "9.090", "$9.090", "9090" o "0". nil si trae letras.
    static func amount(_ text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: CharacterSet(charactersIn: "$ "))
        guard !trimmed.isEmpty, trimmed.first?.isASCIIDigit == true,
              trimmed.allSatisfy({ $0.isASCIIDigit || $0 == "." || $0 == "," }) else { return nil }
        if trimmed.contains(where: { $0 == "." || $0 == "," }), money(trimmed) == nil { return nil }
        return Int(trimmed.filter(\.isASCIIDigit))
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
