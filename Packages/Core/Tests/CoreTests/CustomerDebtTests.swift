import Foundation
import Testing
@testable import Core

@Suite("Clientes · por cobrar y recordatorio")
struct CustomerDebtTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Santiago")!
        return calendar
    }

    private func day(_ value: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: value, hour: 12))!
    }

    @Test func paymentsCoverOldestFirst() {
        let sales = [DebtSale(id: "b", date: day(20), totalPesos: 10000, summary: "Ekos ×1"),
                     DebtSale(id: "a", date: day(12), totalPesos: 25980, summary: "Kaiak ×2")]
        let debt = CustomerDebtRules.debt(sales: sales, payments: [20000])
        #expect(debt.balancePesos == 15980)
        #expect(debt.unpaid.map(\.sale.id) == ["a", "b"])
        #expect(debt.unpaid[0].remainingPesos == 5980)
        #expect(CustomerDebtRules.debt(sales: sales, payments: [40000]).isEmpty)
    }

    @Test func reminderTexts() {
        let one = CustomerDebtRules.debt(sales: [DebtSale(id: "a", date: day(12), totalPesos: 25980, summary: "Kaiak ×2")], payments: [])
        #expect(CustomerDebtRules.reminderText(firstName: "Ana", debt: one, calendar: calendar)
            == "Hola Ana! Te recuerdo que tienes pendiente $25.980 de tu compra del 12 de noviembre (Kaiak ×2). Cuando puedas me avisas. ¡Gracias!")
        let two = CustomerDebtRules.debt(sales: [DebtSale(id: "a", date: day(12), totalPesos: 1000, summary: ""),
                                                 DebtSale(id: "b", date: day(20), totalPesos: 2000, summary: "")], payments: [])
        #expect(CustomerDebtRules.reminderText(firstName: nil, debt: two, calendar: calendar)
            == "Hola! Te recuerdo que tienes pendiente $3.000 de tus compras del 12 de noviembre y 20 de noviembre. Cuando puedas me avisas. ¡Gracias!")
    }

    @Test func voiceAnswers() {
        #expect(VoiceAnswers.debtors([]).text == "Nadie te debe: no tienes ventas por cobrar.")
        #expect(VoiceAnswers.debtors([("Ana", 5000), ("Juan", 0), ("Luis", 12000)]).text
            == "2 clientes te deben $17.000: Luis $12.000 y Ana $5.000.")
        #expect(VoiceAnswers.customerDebt(name: "Ana", debt: nil).text == "Ana no te debe nada.")
    }
}
