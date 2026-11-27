import Foundation

/// Venta fiada a un cliente (por cobrar).
public struct DebtSale: Equatable, Sendable {
    public let id: String
    public let date: Date
    public let totalPesos: Int
    /// "Kaiak Clásico ×2, Ekos ×1"
    public let summary: String

    public init(id: String, date: Date, totalPesos: Int, summary: String) {
        self.id = id
        self.date = date
        self.totalPesos = totalPesos
        self.summary = summary
    }
}

public struct UnpaidSale: Equatable, Sendable {
    public let sale: DebtSale
    public let remainingPesos: Int
}

/// Lo que debe un cliente: ventas fiadas − abonos. Los abonos pagan primero la compra más antigua.
public struct CustomerDebt: Equatable, Sendable {
    public let balancePesos: Int
    public let unpaid: [UnpaidSale]
    public let creditedPesos: Int
    public let paidPesos: Int

    public var oldest: Date? { unpaid.first?.sale.date }
    public var isEmpty: Bool { balancePesos <= 0 }
}

public enum CustomerDebtRules {
    public static func debt(sales: [DebtSale], payments: [Int]) -> CustomerDebt {
        let ordered = sales.sorted { $0.date < $1.date }
        var available = payments.filter { $0 > 0 }.reduce(0, +)
        let paid = available
        var unpaid: [UnpaidSale] = []
        for sale in ordered {
            let covered = min(available, max(sale.totalPesos, 0))
            available -= covered
            let remaining = sale.totalPesos - covered
            if remaining > 0 { unpaid.append(UnpaidSale(sale: sale, remainingPesos: remaining)) }
        }
        let credited = ordered.reduce(0) { $0 + max($1.totalPesos, 0) }
        return CustomerDebt(balancePesos: max(credited - paid, 0), unpaid: unpaid, creditedPesos: credited, paidPesos: paid)
    }

    /// Mensaje amable para WhatsApp: saldo y de qué compras viene.
    public static func reminderText(firstName: String?, debt: CustomerDebt, calendar: Calendar = .current) -> String {
        let greeting = firstName.map { "Hola \($0)! " } ?? "Hola! "
        let amount = Money(pesos: debt.balancePesos).formatted
        let dates = debt.unpaid.prefix(3).map { shortDate($0.sale.date, calendar: calendar) }
        var origin = ""
        if debt.unpaid.count == 1, let first = debt.unpaid.first {
            origin = " de tu compra del \(shortDate(first.sale.date, calendar: calendar))"
            if !first.sale.summary.isEmpty { origin += " (\(first.sale.summary))" }
        } else if !dates.isEmpty {
            origin = " de tus compras del " + VoiceAnswers.list(Array(dates)) + (debt.unpaid.count > 3 ? " y otras" : "")
        }
        return greeting + "Te recuerdo que tienes pendiente \(amount)\(origin). Cuando puedas me avisas. ¡Gracias!"
    }

    /// "12 de noviembre"
    static func shortDate(_ date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_CL")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "d 'de' MMMM"
        return formatter.string(from: date)
    }
}

/// Respuestas de voz sobre lo que deben los clientes.
public extension VoiceAnswers {
    static func debtors(_ balances: [(name: String, balancePesos: Int)]) -> VoiceAnswer {
        let owing = balances.filter { $0.balancePesos > 0 }.sorted { $0.balancePesos > $1.balancePesos }
        guard !owing.isEmpty else { return VoiceAnswer(text: "Nadie te debe: no tienes ventas por cobrar.") }
        let total = Money(pesos: owing.reduce(0) { $0 + $1.balancePesos })
        let shown = owing.prefix(maximumListed).map { "\($0.name) \(Money(pesos: $0.balancePesos).formatted)" }
        let spokenShown = owing.prefix(maximumListed).map { "\($0.name) \(spoken(Money(pesos: $0.balancePesos)))" }
        let who = owing.count == 1 ? "1 cliente te debe" : "\(owing.count) clientes te deben"
        return VoiceAnswer(text: "\(who) \(total.formatted): " + list(Array(shown)) + ".",
                           speech: "\(who) \(spoken(total)): " + list(Array(spokenShown)) + ".")
    }

    static func customerDebt(name: String, debt: CustomerDebt?) -> VoiceAnswer {
        guard let debt, !debt.isEmpty else { return VoiceAnswer(text: "\(name) no te debe nada.") }
        let amount = Money(pesos: debt.balancePesos)
        let count = debt.unpaid.count == 1 ? "1 compra" : "\(debt.unpaid.count) compras"
        return VoiceAnswer(text: "\(name) te debe \(amount.formatted) de \(count).",
                           speech: "\(name) te debe \(spoken(amount)) de \(count).")
    }
}
