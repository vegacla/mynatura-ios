import Foundation

/// Producto del catálogo tal como lo necesita el reconocimiento por foto.
public struct RecognizableProduct: Equatable, Sendable {
    public let id: String
    public let name: String
    public let sku: String
    public let barcodes: [String]

    public init(id: String, name: String, sku: String, barcodes: [String]) {
        self.id = id
        self.name = name
        self.sku = sku
        self.barcodes = barcodes
    }
}

/// Por qué se propuso un candidato (se muestra: "Leí EAN 7908…").
public enum RecognitionReason: Equatable, Sendable {
    case barcode(String)
    case naturaCode(String)
    case name
}

public struct RecognitionCandidate: Equatable, Sendable {
    public let id: String
    public let score: Double
    public let reasons: [RecognitionReason]
}

public struct RecognitionResult: Equatable, Sendable {
    /// Ordenados de mayor a menor confianza.
    public let candidates: [RecognitionCandidate]
    /// `.found` si hay uno claro; `.ambiguous` si hay que elegir; `.notFound` si nada coincide.
    public let match: VoiceMatch
    /// EAN leídos en la foto que ningún producto tiene asociados (para "Asociar EAN").
    public let unknownBarcodes: [String]
    /// Códigos Natura leídos (para "Crear producto" si no se reconoció).
    public let readCodes: [String]
    /// Mejor nombre leído de la etiqueta (para "Crear producto").
    public let labelName: String?
}

/// Reconocimiento por foto (docs/product-photo-proposal.md §2): tres señales leídas en el iPhone.
/// 1. Código de barras (exacto) · 2. Código Natura impreso (OCR) · 3. Nombre de la etiqueta (OCR + parecido).
public enum ProductRecognizer {
    static let barcodeScore = 1.0
    static let explicitCodeScore = 0.97
    static let looseCodeScore = 0.9
    /// Un nombre parecido nunca vale tanto como un código.
    static let nameWeight = 0.9
    static let minimumNameScore = 0.5
    /// Para darlo por reconocido sin preguntar.
    static let foundScore = 0.75
    /// Si es el único candidato, basta con un parecido razonable.
    static let singleCandidateScore = 0.6
    static let ambiguityMargin = 0.05
    /// Cada señal extra que apunta al mismo producto suma un poco.
    static let agreementBonus = 0.05
    static let maximumCandidates = 5
    /// Palabras genéricas pesan poco en el nombre ("desodorante", "colonia"…).
    static let genericWeight = 0.3
    static let tokenFound = 0.8

    static let codeMarkers: Set<String> = ["cod", "codigo", "ref", "referencia", "sku", "art", "articulo"]

    /// Códigos Natura escritos de forma explícita: "(12345)", "Cód. 12345", "Código: 12345", "Ref 1234567".
    public static func naturaCodes(in lines: [String]) -> [String] {
        var result: [String] = []
        for line in lines {
            let characters = Array(line)
            // "(12345)"
            var index = 0
            while index < characters.count {
                if characters[index] == "(" {
                    var end = index + 1
                    while end < characters.count, characters[end].isASCIIDigit { end += 1 }
                    let digits = String(characters[(index + 1)..<end])
                    if end < characters.count, characters[end] == ")", (5...7).contains(digits.count) {
                        result.append(digits)
                    }
                    index = end
                } else {
                    index += 1
                }
            }
            // "Cód. 12345", "Código: 12345"
            let words = VoiceText.fold(line)
                .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
                .map(String.init)
            for (position, word) in words.enumerated() where codeMarkers.contains(word) {
                if position + 1 < words.count {
                    let next = words[position + 1]
                    if (5...7).contains(next.count), next.allSatisfy({ $0.isASCIIDigit }) {
                        result.append(next)
                    }
                }
            }
        }
        return unique(result)
    }

    /// Números sueltos de 5–7 dígitos (sin separadores de miles ni "$"). Solo valen si están en el catálogo.
    public static func looseNumbers(in lines: [String]) -> [String] {
        var result: [String] = []
        for line in lines {
            for raw in line.split(whereSeparator: { $0.isWhitespace }) {
                var word = Substring(raw)
                if word.hasPrefix("$") { continue }
                while let first = word.first, "(#".contains(first) { word = word.dropFirst() }
                while let last = word.last, ").,;:".contains(last) { word = word.dropLast() }
                if (5...7).contains(word.count), word.allSatisfy({ $0.isASCIIDigit }) {
                    result.append(String(word))
                }
            }
        }
        return unique(result)
    }

    /// Mejor nombre leído: la línea con más letras entre las primeras 6, sin códigos ni precios.
    public static func labelName(in lines: [String]) -> String? {
        let candidates = lines.prefix(6).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { line in
            let letters = line.filter(\.isLetter).count
            let digits = line.filter(\.isASCIIDigit).count
            return letters >= 3 && digits <= 3 && !line.contains("$")
        }
        return candidates.max { $0.filter(\.isLetter).count < $1.filter(\.isLetter).count }
    }

    public static func recognize(barcodes: [String], textLines: [String], catalog: [RecognizableProduct]) -> RecognitionResult {
        let readBarcodes = unique(barcodes.map(Normalize.ean).filter { !$0.isEmpty })
        let explicitCodes = naturaCodes(in: textLines)
        let looseCodes = looseNumbers(in: textLines).filter { !explicitCodes.contains($0) }
        let labelTokens = VoiceMatching.significantTokens(textLines.joined(separator: " "), ignoring: [])
            .map { (token: $0, key: VoiceText.phoneticKey($0)) }

        var linkedBarcodes = Set<String>()
        var candidates: [(order: Int, candidate: RecognitionCandidate)] = []
        for (order, product) in catalog.enumerated() {
            var scores: [Double] = []
            var reasons: [RecognitionReason] = []
            let productBarcodes = Set(product.barcodes.map(Normalize.ean))
            for barcode in readBarcodes where productBarcodes.contains(barcode) {
                scores.append(barcodeScore)
                reasons.append(.barcode(barcode))
                linkedBarcodes.insert(barcode)
            }
            let sku = Normalize.naturaSku(product.sku).lowercased()
            if let code = explicitCodes.first(where: { $0.lowercased() == sku }) {
                scores.append(explicitCodeScore)
                reasons.append(.naturaCode(code))
            } else if let code = looseCodes.first(where: { $0.lowercased() == sku }) {
                scores.append(looseCodeScore)
                reasons.append(.naturaCode(code))
            }
            let name = nameScore(product.name, labelTokens: labelTokens)
            if name >= minimumNameScore {
                scores.append(name)
                reasons.append(.name)
            }
            guard let best = scores.max() else { continue }
            let score = min(1, best + agreementBonus * Double(scores.count - 1))
            candidates.append((order, RecognitionCandidate(id: product.id, score: score, reasons: reasons)))
        }
        candidates.sort { lhs, rhs in
            lhs.candidate.score != rhs.candidate.score ? lhs.candidate.score > rhs.candidate.score : lhs.order < rhs.order
        }
        let ranked = candidates.prefix(maximumCandidates).map { $0.candidate }

        let match: VoiceMatch
        if let top = ranked.first {
            let close = ranked.filter { top.score - $0.score <= ambiguityMargin }
            if close.count == 1, top.score >= foundScore || (ranked.count == 1 && top.score >= singleCandidateScore) {
                match = .found(top.id)
            } else {
                match = .ambiguous(ranked.map(\.id))
            }
        } else {
            match = .notFound
        }
        return RecognitionResult(candidates: Array(ranked), match: match,
                                 unknownBarcodes: readBarcodes.filter { !linkedBarcodes.contains($0) },
                                 readCodes: explicitCodes + looseCodes, labelName: labelName(in: textLines))
    }

    /// Cuánto del nombre del producto aparece en la etiqueta (las palabras genéricas pesan poco).
    /// 0 si no aparece ninguna palabra distintiva.
    static func nameScore(_ name: String, labelTokens: [(token: String, key: String)]) -> Double {
        let tokens = VoiceMatching.significantTokens(name, ignoring: [])
        guard !tokens.isEmpty, !labelTokens.isEmpty else { return 0 }
        var total = 0.0
        var found = 0.0
        var distinctiveFound = false
        for token in tokens {
            let isGeneric = VoiceTraining.genericWords.contains(token)
            let weight = isGeneric ? genericWeight : 1
            total += weight
            let key = VoiceText.phoneticKey(token)
            let best = labelTokens.map { VoiceMatching.tokenSimilarity(token, key, $0.token, $0.key) }.max() ?? 0
            if best >= tokenFound {
                found += weight * best
                if !isGeneric { distinctiveFound = true }
            }
        }
        guard distinctiveFound, total > 0 else { return 0 }
        return found / total * nameWeight
    }

    static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }
}
