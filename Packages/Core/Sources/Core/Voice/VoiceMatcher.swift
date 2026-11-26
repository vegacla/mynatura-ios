import Foundation

/// Algo que la voz puede nombrar: un producto (con código) o un cliente.
public struct VoiceCandidate: Equatable, Sendable {
    public let id: String
    public let name: String
    public let code: String?
    public let aliases: [String]

    public init(id: String, name: String, code: String? = nil, aliases: [String] = []) {
        self.id = id
        self.name = name
        self.code = code
        self.aliases = aliases
    }
}

public struct VoiceScore: Equatable, Sendable {
    public let id: String
    public let score: Double
}

public enum VoiceMatch: Equatable, Sendable {
    case found(String)
    /// Candidatos casi empatados: la pantalla los ofrece en el chip.
    case ambiguous([String])
    case notFound
}

/// Resuelve un `ProductRef` contra el catálogo: código exacto, o nombre/alias por parecido fonético.
public enum ProductMatcher {
    public static func rank(_ reference: ProductRef, in candidates: [VoiceCandidate]) -> [VoiceScore] {
        VoiceMatching.rank(candidates) { candidate in
            switch reference {
            case .sku(let code):
                guard let candidateCode = candidate.code else { return 0 }
                return Normalize.naturaSku(candidateCode) == Normalize.naturaSku(code) ? 1 : 0
            case .text(let text):
                return VoiceMatching.textScore(query: text, targets: [candidate.name] + candidate.aliases, ignoring: [])
            }
        }
    }

    public static func resolve(_ reference: ProductRef, in candidates: [VoiceCandidate]) -> VoiceMatch {
        VoiceMatching.resolve(rank(reference, in: candidates))
    }
}

/// Resuelve el nombre dictado de un cliente ("la señora Ana" → Ana Rojas).
public enum CustomerMatcher {
    public static func rank(name: String, in candidates: [VoiceCandidate]) -> [VoiceScore] {
        VoiceMatching.rank(candidates) { candidate in
            VoiceMatching.textScore(query: name, targets: [candidate.name] + candidate.aliases, ignoring: VoiceMatching.honorifics)
        }
    }

    public static func resolve(name: String, in candidates: [VoiceCandidate]) -> VoiceMatch {
        VoiceMatching.resolve(rank(name: name, in: candidates))
    }
}

enum VoiceMatching {
    /// Puntaje mínimo para proponer un candidato.
    static let minimumScore = 0.75
    /// Candidatos a menos de esta distancia del primero se consideran empate.
    static let ambiguityMargin = 0.05
    /// Un parecido (no idéntico) nunca vale lo mismo que el nombre exacto.
    static let fuzzyWeight = 0.9
    /// Bajo este parecido, una palabra no cuenta.
    static let tokenThreshold = 0.7
    static let maximumAmbiguous = 5

    static let stopwords: Set<String> = [
        "de", "del", "la", "el", "los", "las", "un", "una", "uno", "para", "con", "y", "en", "al", "lo", "por", "a",
    ]
    static let honorifics: Set<String> = ["don", "dona", "senor", "senora", "senorita", "sr", "sra", "srta", "mi"]

    static func rank(_ candidates: [VoiceCandidate], score: (VoiceCandidate) -> Double) -> [VoiceScore] {
        candidates.enumerated()
            .map { entry in (order: entry.offset, score: VoiceScore(id: entry.element.id, score: score(entry.element))) }
            .filter { $0.score.score >= minimumScore }
            .sorted { lhs, rhs in
                lhs.score.score != rhs.score.score ? lhs.score.score > rhs.score.score : lhs.order < rhs.order
            }
            .map { $0.score }
    }

    static func resolve(_ ranked: [VoiceScore]) -> VoiceMatch {
        guard let top = ranked.first else { return .notFound }
        let close = ranked.filter { top.score - $0.score <= ambiguityMargin }
        return close.count == 1 ? .found(top.id) : .ambiguous(close.prefix(maximumAmbiguous).map(\.id))
    }

    static func textScore(query: String, targets: [String], ignoring extra: Set<String>) -> Double {
        let normalizedQuery = Normalize.customerName(query)
        guard !normalizedQuery.isEmpty else { return 0 }
        if targets.contains(where: { Normalize.customerName($0) == normalizedQuery }) {
            return 1
        }
        let best = targets.map { similarity(query: query, target: $0, ignoring: extra) }.max() ?? 0
        return best * fuzzyWeight
    }

    /// Promedio, por palabra dictada, de su mejor parecido con alguna palabra del nombre.
    static func similarity(query: String, target: String, ignoring extra: Set<String>) -> Double {
        let queryTokens = mergeFragments(significantTokens(query, ignoring: extra))
        let targetTokens = significantTokens(target, ignoring: extra)
        guard !queryTokens.isEmpty, !targetTokens.isEmpty else { return 0 }
        let targetKeys = targetTokens.map { (token: $0, key: VoiceText.phoneticKey($0)) }

        var total = 0.0
        for token in queryTokens {
            let key = VoiceText.phoneticKey(token)
            var best = 0.0
            for target in targetKeys {
                best = max(best, tokenSimilarity(token, key, target.token, target.key))
            }
            total += best >= tokenThreshold ? best : 0
        }
        return total / Double(queryTokens.count)
    }

    static func significantTokens(_ text: String, ignoring extra: Set<String>) -> [String] {
        VoiceText.fold(text)
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { !stopwords.contains($0) && !extra.contains($0) }
    }

    /// Une trozos cortos con la palabra siguiente: "e cos" → "ecos" (≈ "ekos").
    static func mergeFragments(_ tokens: [String]) -> [String] {
        var result: [String] = []
        var pending = ""
        for token in tokens {
            if token.count <= 2, !token.allSatisfy({ $0.isASCIIDigit }) {
                pending += token
                continue
            }
            result.append(pending + token)
            pending = ""
        }
        if result.isEmpty, !pending.isEmpty {
            result.append(pending)
        }
        return result
    }

    static func tokenSimilarity(_ query: String, _ queryKey: String, _ target: String, _ targetKey: String) -> Double {
        let queryIsNumber = query.allSatisfy { $0.isASCIIDigit }
        let targetIsNumber = target.allSatisfy { $0.isASCIIDigit }
        if queryIsNumber || targetIsNumber {
            return query == target ? 1 : 0
        }
        if queryKey == targetKey { return 1 }
        if queryKey.count >= 3, targetKey.hasPrefix(queryKey) { return 0.9 }
        let longest = max(queryKey.count, targetKey.count)
        guard longest > 0 else { return 0 }
        return 1 - Double(VoiceText.editDistance(queryKey, targetKey)) / Double(longest)
    }
}
