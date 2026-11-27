import Foundation

/// Preguntas que se responden con datos locales (§3 caso 6 de docs/voice-interaction-proposal.md).
public enum VoiceQuery: Equatable, Sendable {
    /// "¿Cuánto me queda de Kaiak?"
    case stock(ProductRef)
    /// "¿Qué me encargó Juan?"
    case customerOrders(name: String)
    /// "¿Cuánto vendí esta semana?"
    case sales(VoicePeriod)
    /// "¿Cuándo cierra el ciclo?"
    case cycle
    /// "¿Cuánto crédito tengo?"
    case credit
    /// "¿Cuándo vence mi pago?" · "¿Debo algo?" · "¿Tengo atrasos?"
    case payments
}

/// Ciclo vigente leído de Natura (M3/M6).
public struct VoiceCycleFact: Equatable, Sendable {
    public let code: Int
    public let start: Date?
    public let end: Date?

    public init(code: Int, start: Date?, end: Date?) {
        self.code = code
        self.start = start
        self.end = end
    }
}

public enum VoicePeriod: String, Equatable, Sendable, CaseIterable {
    case today, yesterday, thisWeek, lastWeek, thisMonth, lastMonth

    /// Para empezar una frase: "Hoy", "Esta semana"…
    public var label: String {
        switch self {
        case .today: "Hoy"
        case .yesterday: "Ayer"
        case .thisWeek: "Esta semana"
        case .lastWeek: "La semana pasada"
        case .thisMonth: "Este mes"
        case .lastMonth: "El mes pasado"
        }
    }

    /// Intervalo del periodo que contiene `date` (semana según `calendar.firstWeekday`).
    public func interval(containing date: Date, calendar: Calendar) -> DateInterval {
        let reference: Date
        let component: Calendar.Component
        switch self {
        case .today:
            reference = date
            component = .day
        case .yesterday:
            reference = calendar.date(byAdding: .day, value: -1, to: date) ?? date
            component = .day
        case .thisWeek:
            reference = date
            component = .weekOfYear
        case .lastWeek:
            reference = calendar.date(byAdding: .day, value: -7, to: date) ?? date
            component = .weekOfYear
        case .thisMonth:
            reference = date
            component = .month
        case .lastMonth:
            reference = calendar.date(byAdding: .month, value: -1, to: date) ?? date
            component = .month
        }
        return calendar.dateInterval(of: component, for: reference) ?? DateInterval(start: reference, duration: 0)
    }
}

/// Respuesta para mostrar (`text`) y para leer en voz alta (`speech`, sin "$" ni símbolos).
public struct VoiceAnswer: Equatable, Sendable {
    public let text: String
    public let speech: String

    public init(text: String, speech: String? = nil) {
        self.text = text
        self.speech = speech ?? text
    }
}

public struct VoiceStockFact: Equatable, Sendable {
    public let name: String
    public let quantity: Int

    public init(name: String, quantity: Int) {
        self.name = name
        self.quantity = quantity
    }
}

public struct VoiceOrderFact: Equatable, Sendable {
    public let cycle: Int
    public let lines: [VoiceStockFact]

    public init(cycle: Int, lines: [VoiceStockFact]) {
        self.cycle = cycle
        self.lines = lines
    }
}

/// Frases de respuesta, en español de Chile.
public enum VoiceAnswers {
    static let maximumListed = 6

    /// "12.990 pesos" para leer; "$12.990" para mostrar.
    public static func spoken(_ money: Money) -> String {
        let formatted = money.formatted
        let digits = formatted.replacingOccurrences(of: "$", with: "")
        return digits + (money.pesos == 1 ? " peso" : " pesos")
    }

    public static func stock(spoken: String, facts: [VoiceStockFact]) -> VoiceAnswer {
        guard let first = facts.first else {
            return VoiceAnswer(text: "No encontré “\(spoken)” en tu catálogo.")
        }
        if facts.count == 1 {
            switch first.quantity {
            case ..<1: return VoiceAnswer(text: "No te quedan unidades de \(first.name).")
            case 1: return VoiceAnswer(text: "Te queda 1 unidad de \(first.name).")
            default: return VoiceAnswer(text: "Te quedan \(first.quantity) unidades de \(first.name).")
            }
        }
        let listed = facts.prefix(maximumListed).map { fact in
            fact.quantity > 0 ? "\(fact.name): \(fact.quantity)" : "\(fact.name): sin stock"
        }
        return VoiceAnswer(text: "Encontré \(facts.count) productos parecidos. " + listed.joined(separator: "; ") + ".")
    }

    public static func customerOrders(spoken: String, match: VoiceMatch, customerName: String?, orders: [VoiceOrderFact],
                                      ambiguousNames: [String] = []) -> VoiceAnswer {
        switch match {
        case .notFound:
            return VoiceAnswer(text: "No encontré a “\(spoken)” entre tus clientes.")
        case .ambiguous:
            let names = ambiguousNames.prefix(maximumListed).joined(separator: ", ")
            return VoiceAnswer(text: "Hay varios clientes parecidos: \(names). Dime también el apellido.")
        case .found:
            break
        }
        let name = customerName ?? spoken
        guard !orders.isEmpty else {
            return VoiceAnswer(text: "\(name) no tiene encargos pendientes.")
        }
        let header = orders.count == 1 ? "\(name) tiene 1 encargo pendiente" : "\(name) tiene \(orders.count) encargos pendientes"
        let details = orders.map { order -> String in
            let shown = order.lines.prefix(maximumListed).map { "\($0.quantity) \($0.name)" }
            var text = "ciclo \(order.cycle % 100) de \(order.cycle / 100): " + list(shown)
            if order.lines.count > maximumListed { text += " y \(order.lines.count - maximumListed) más" }
            return text
        }
        return VoiceAnswer(text: header + ". " + details.joined(separator: ". ") + ".")
    }

    public static func sales(period: VoicePeriod, count: Int, total: Money) -> VoiceAnswer {
        guard count > 0 else {
            return VoiceAnswer(text: "\(period.label) no registraste ventas.")
        }
        let salesText = count == 1 ? "1 venta" : "\(count) ventas"
        return VoiceAnswer(text: "\(period.label) vendiste \(total.formatted) en \(salesText).",
                           speech: "\(period.label) vendiste \(spoken(total)) en \(salesText).")
    }

    /// Ciclo vigente con su cierre (leído de Natura al importar). Sin él, el último ciclo registrado.
    public static func cycle(current: VoiceCycleFact? = nil, latestKnown: Int?, now: Date = .now,
                             calendar: Calendar = .current) -> VoiceAnswer {
        if let current, current.code >= 10_000 {
            let name = "el ciclo \(current.code % 100) de \(current.code / 100)"
            guard let end = current.end else { return VoiceAnswer(text: "Estamos en \(name).") }
            let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: end)).day ?? 0
            let date = longDate(end, calendar: calendar)
            switch days {
            case ..<0: return VoiceAnswer(text: "El \(name) cerró el \(date). Trae tus pedidos de Natura para ver el ciclo nuevo.")
            case 0: return VoiceAnswer(text: "Estamos en \(name) y cierra hoy.")
            case 1: return VoiceAnswer(text: "Estamos en \(name). Cierra mañana, \(date).")
            default: return VoiceAnswer(text: "Estamos en \(name). Cierra el \(date): quedan \(days) días.")
            }
        }
        let pending = "Trae tus pedidos de Natura para saber la fecha de cierre."
        guard let latestKnown, latestKnown >= 10_000 else {
            return VoiceAnswer(text: "Todavía no tengo ciclos registrados. " + pending)
        }
        return VoiceAnswer(text: "El último ciclo que tengo registrado es el \(latestKnown % 100) de \(latestKnown / 100). " + pending)
    }

    /// Crédito con Natura (última lectura).
    public static func credit(_ credit: NaturaCredit?, readAt: Date?, now: Date = .now, calendar: Calendar = .current) -> VoiceAnswer {
        guard let credit, let available = credit.availablePesos else {
            return VoiceAnswer(text: "Todavía no tengo tu crédito. Actualiza tu cuenta en Ajustes › Natura.")
        }
        var text = "Tienes \(Money(pesos: available).formatted) de crédito disponible"
        var speech = "Tienes \(spoken(Money(pesos: available))) de crédito disponible"
        if let limit = credit.limitPesos {
            text += " de un límite de \(Money(pesos: limit).formatted)"
            speech += " de un límite de \(spoken(Money(pesos: limit)))"
        }
        text += "."
        speech += "."
        if credit.isBlocked {
            text += " Ojo: tu cuenta aparece bloqueada."
            speech += " Ojo: tu cuenta aparece bloqueada."
        }
        let age = readAge(readAt, now: now, calendar: calendar)
        return VoiceAnswer(text: text + age, speech: speech + age)
    }

    /// Pagos a Natura: atrasos, próximo vencimiento y saldo (última lectura de `mis-cuentas`).
    public static func payments(_ documents: [NaturaAccountDocument]?, readAt: Date?, now: Date = .now,
                                calendar: Calendar = .current) -> VoiceAnswer {
        guard let documents else {
            return VoiceAnswer(text: "Todavía no tengo tus pagos. Actualiza tu cuenta en Ajustes › Natura.")
        }
        let summary = NaturaAccountSummary(documents: documents)
        let age = readAge(readAt, now: now, calendar: calendar)
        guard summary.pendingCount > 0 else {
            return VoiceAnswer(text: "No tienes pagos pendientes con Natura." + age)
        }
        var text: [String] = []
        var speech: [String] = []
        if summary.overdueCount > 0 {
            let docs = summary.overdueCount == 1 ? "1 documento vencido" : "\(summary.overdueCount) documentos vencidos"
            text.append("Tienes \(docs) por \(Money(pesos: summary.overduePesos).formatted), con hasta \(summary.maxOverdueDays) días de atraso.")
            speech.append("Tienes \(docs) por \(spoken(Money(pesos: summary.overduePesos))), con hasta \(summary.maxOverdueDays) días de atraso.")
        }
        if let next = summary.nextDue, let due = next.dueDate {
            let amount = Money(pesos: next.balancePesos ?? 0)
            text.append("El próximo vence el \(longDate(due, calendar: calendar)) por \(amount.formatted).")
            speech.append("El próximo vence el \(longDate(due, calendar: calendar)) por \(spoken(amount)).")
        }
        let total = Money(pesos: summary.pendingPesos)
        text.append("Saldo pendiente: \(total.formatted).")
        speech.append("Saldo pendiente: \(spoken(total)).")
        return VoiceAnswer(text: text.joined(separator: " ") + age, speech: speech.joined(separator: " ") + age)
    }

    /// "martes 9 de diciembre"
    static func longDate(_ date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_CL")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "EEEE d 'de' MMMM"
        return formatter.string(from: date)
    }

    /// " (leído hace 3 días)" cuando la lectura no es de hoy.
    static func readAge(_ readAt: Date?, now: Date, calendar: Calendar) -> String {
        guard let readAt else { return "" }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: readAt), to: calendar.startOfDay(for: now)).day ?? 0
        switch days {
        case ..<1: return ""
        case 1: return " (leído ayer)"
        default: return " (leído hace \(days) días)"
        }
    }

    public static func notUnderstood(_ text: String) -> VoiceAnswer {
        VoiceAnswer(text: "No entendí “\(text)”. Prueba con “¿cuánto me queda de Kaiak?” o “¿cuánto vendí hoy?”.")
    }

    /// "a, b y c"
    static func list(_ items: [String]) -> String {
        guard items.count > 1, let last = items.last else { return items.first ?? "" }
        return items.dropLast().joined(separator: ", ") + " y " + last
    }
}
