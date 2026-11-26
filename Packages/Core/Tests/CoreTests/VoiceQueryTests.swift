import Foundation
import Testing
@testable import Core

@Suite("Voice · consultas")
struct VoiceQueryTests {
    func ask(_ utterance: String) -> [VoiceCommand] {
        CommandGrammar.interpret(utterance, context: .global)
    }

    @Test func stockQuestions() {
        #expect(ask("¿Cuánto me queda de Kaiak?") == [.query(.stock(.text("Kaiak")))])
        #expect(ask("¿Cuántos Ekos castaña tengo?") == [.query(.stock(.text("Ekos castaña")))])
        #expect(ask("stock del 12345") == [.query(.stock(.sku("12345")))])
        #expect(ask("¿Hay desodorante Humor?") == [.query(.stock(.text("desodorante Humor")))])
    }

    @Test func customerOrderQuestions() {
        #expect(ask("¿Qué me encargó Juan?") == [.query(.customerOrders(name: "Juan"))])
        #expect(ask("pedidos pendientes de María Soto") == [.query(.customerOrders(name: "María Soto"))])
        #expect(ask("¿qué pidió la señora Ana?") == [.query(.customerOrders(name: "señora Ana"))])
    }

    @Test func salesQuestions() {
        #expect(ask("¿Cuánto vendí hoy?") == [.query(.sales(.today))])
        #expect(ask("¿cuánto vendí ayer?") == [.query(.sales(.yesterday))])
        #expect(ask("ventas de esta semana") == [.query(.sales(.thisWeek))])
        #expect(ask("¿cuánto vendí la semana pasada?") == [.query(.sales(.lastWeek))])
        #expect(ask("¿cuánto vendí este mes?") == [.query(.sales(.thisMonth))])
        #expect(ask("ventas del mes pasado") == [.query(.sales(.lastMonth))])
    }

    @Test func cycleAndUnknown() {
        #expect(ask("¿Cuándo cierra el ciclo?") == [.query(.cycle)])
        #expect(ask("¿qué ciclo es?") == [.query(.cycle)])
        #expect(ask("¿cuánto?") == [.unrecognized("cuánto")])
    }

    @Test func queriesAreNotChips() {
        let proposal = VoiceProposalBuilder.build(ask("¿cuánto me queda de Kaiak?"), products: [], customers: [], referenceYear: 2026)
        #expect(proposal.items.isEmpty)
    }

    @Test func periods() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 2  // lunes, como en Chile
        // Jueves 26-11-2026 15:00 UTC.
        let date = Date(timeIntervalSince1970: 1_795_705_200)
        func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
            calendar.date(from: DateComponents(year: y, month: m, day: d))!
        }
        #expect(VoicePeriod.today.interval(containing: date, calendar: calendar).start == day(2026, 11, 26))
        #expect(VoicePeriod.yesterday.interval(containing: date, calendar: calendar).start == day(2026, 11, 25))
        #expect(VoicePeriod.thisWeek.interval(containing: date, calendar: calendar).start == day(2026, 11, 23))
        #expect(VoicePeriod.lastWeek.interval(containing: date, calendar: calendar).start == day(2026, 11, 16))
        #expect(VoicePeriod.thisMonth.interval(containing: date, calendar: calendar).start == day(2026, 11, 1))
        #expect(VoicePeriod.lastMonth.interval(containing: date, calendar: calendar).start == day(2026, 10, 1))
        #expect(VoicePeriod.thisMonth.interval(containing: date, calendar: calendar).end == day(2026, 12, 1))
    }

    @Test func stockAnswers() {
        #expect(VoiceAnswers.stock(spoken: "kaiak", facts: [VoiceStockFact(name: "Kaiak Clásico", quantity: 3)]).text
            == "Te quedan 3 unidades de Kaiak Clásico.")
        #expect(VoiceAnswers.stock(spoken: "kaiak", facts: [VoiceStockFact(name: "Kaiak Clásico", quantity: 1)]).text
            == "Te queda 1 unidad de Kaiak Clásico.")
        #expect(VoiceAnswers.stock(spoken: "kaiak", facts: [VoiceStockFact(name: "Kaiak Clásico", quantity: 0)]).text
            == "No te quedan unidades de Kaiak Clásico.")
        #expect(VoiceAnswers.stock(spoken: "xyz", facts: []).text == "No encontré “xyz” en tu catálogo.")
        #expect(VoiceAnswers.stock(spoken: "humor", facts: [
            VoiceStockFact(name: "Humor M", quantity: 2), VoiceStockFact(name: "Humor F", quantity: 0),
        ]).text == "Encontré 2 productos parecidos. Humor M: 2; Humor F: sin stock.")
    }

    @Test func orderAnswers() {
        let orders = [VoiceOrderFact(cycle: 202619, lines: [
            VoiceStockFact(name: "Kaiak Clásico", quantity: 2), VoiceStockFact(name: "Humor", quantity: 1),
        ])]
        #expect(VoiceAnswers.customerOrders(spoken: "juan", match: .found("j"), customerName: "Juan Soto", orders: orders).text
            == "Juan Soto tiene 1 encargo pendiente. ciclo 19 de 2026: 2 Kaiak Clásico y 1 Humor.")
        #expect(VoiceAnswers.customerOrders(spoken: "juan", match: .found("j"), customerName: "Juan Soto", orders: []).text
            == "Juan Soto no tiene encargos pendientes.")
        #expect(VoiceAnswers.customerOrders(spoken: "pedro", match: .notFound, customerName: nil, orders: []).text
            == "No encontré a “pedro” entre tus clientes.")
        #expect(VoiceAnswers.customerOrders(spoken: "juan", match: .ambiguous(["a", "b"]), customerName: nil, orders: [],
                                            ambiguousNames: ["Juan Soto", "Juan Pérez"]).text
            == "Hay varios clientes parecidos: Juan Soto, Juan Pérez. Dime también el apellido.")
    }

    @Test func salesAndCycleAnswers() {
        let answer = VoiceAnswers.sales(period: .thisWeek, count: 3, total: Money(pesos: 45980))
        #expect(answer.text == "Esta semana vendiste $45.980 en 3 ventas.")
        #expect(answer.speech == "Esta semana vendiste 45.980 pesos en 3 ventas.")
        #expect(VoiceAnswers.sales(period: .today, count: 0, total: .zero).text == "Hoy no registraste ventas.")
        #expect(VoiceAnswers.cycle(latestKnown: 202619).text.hasPrefix("El último ciclo que tengo registrado es el 19 de 2026."))
        #expect(VoiceAnswers.cycle(latestKnown: nil).text.hasPrefix("Todavía no tengo ciclos registrados."))
    }
}
