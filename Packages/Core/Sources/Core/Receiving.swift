public enum ReceivingStatus: String, Sendable, Codable {
    case pending
    case partial
    case complete

    /// Espejo de update-natura-order-receiving.ts.
    public static func derive(receivedUnits: Int, pendingUnits: Int) -> ReceivingStatus {
        if receivedUnits <= 0 { return .pending }
        if pendingUnits <= 0 { return .complete }
        return .partial
    }
}

public enum ReceivingRules {
    /// Unidades pedidas aún no confirmadas.
    public static func shortage(ordered: Int, confirmed: Int) -> Int {
        max(ordered - confirmed, 0)
    }

    /// Conteo sugerido al aplicar un faltante al stock.
    public static func suggestedCount(operationalStock: Int, shortage: Int) -> Int {
        max(operationalStock - shortage, 0)
    }
}

public struct NaturaCycle: Hashable, Sendable, Codable {
    public let year: Int
    public let cycle: Int

    public init(year: Int, cycle: Int) {
        self.year = year
        self.cycle = cycle
    }

    /// Ciclo en formato AAAACC (202606) o solo número de ciclo + año de referencia.
    public static func normalize(raw: Int, referenceYear: Int) -> NaturaCycle {
        if raw >= 10_000 {
            return NaturaCycle(year: raw / 100, cycle: raw % 100)
        }
        return NaturaCycle(year: referenceYear, cycle: raw)
    }

    /// Representación AAAACC.
    public var code: Int { year * 100 + cycle }
}
