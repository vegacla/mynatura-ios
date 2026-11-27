import Core
import Foundation
import Persistence
import Store
import SwiftData

/// Respuestas a consultas y navegación por voz con datos locales. Lo comparten "Preguntar" y el Asistente.
@MainActor
struct VoiceQueryResolver {
    let context: ModelContext
    let sellerId: String
    let router: AppRouter
    let store: LocalStore
    var logUnrecognized = false
    /// Cierra la hoja antes de navegar.
    let close: () -> Void

    func fetch<T: PersistentModel>(_ descriptor: FetchDescriptor<T>) -> [T] {
        (try? context.fetch(descriptor)) ?? []
    }

    func resolve(_ command: VoiceCommand) -> VoiceAnswer {
        if case .navigate(let destination) = command { return navigate(destination) }
        guard case .query(let query) = command else {
            if case .unrecognized(let text) = command {
                if logUnrecognized { VoicePhraseLog.append(text) }
                return VoiceAnswers.notUnderstood(text)
            }
            return VoiceAnswers.notUnderstood("")
        }
        switch query {
        case .stock(let reference):
            return stockAnswer(reference)
        case .customerOrders(let name):
            return customerOrdersAnswer(name)
        case .sales(let period):
            return salesAnswer(period)
        case .cycle:
            return cycleAnswer()
        case .credit:
            let snapshot = accountSnapshot()
            return VoiceAnswers.credit(snapshot?.credit, readAt: snapshot?.creditFetchedAt)
        case .payments:
            let snapshot = accountSnapshot()
            return VoiceAnswers.payments(snapshot?.documents, readAt: snapshot?.documentsFetchedAt)
        case .receivables(let name):
            return receivablesAnswer(name)
        }
    }


    private func stockAnswer(_ reference: ProductRef) -> VoiceAnswer {
        let id = sellerId
        let products = fetch(FetchDescriptor<CatalogProduct>(predicate: #Predicate { $0.sellerId == id }))
        let candidates = products.map { VoiceCandidate(id: $0.id, name: $0.name, code: $0.naturaSku) }
        let chosen: [String]
        switch ProductMatcher.resolve(reference, in: candidates) {
        case .found(let found): chosen = [found]
        case .ambiguous(let options): chosen = options
        case .notFound: chosen = []
        }
        let stock = fetch(FetchDescriptor<StockItem>(predicate: #Predicate { $0.sellerId == id }))
        let quantities = Dictionary(stock.map { ($0.sellerProductId, $0.operationalQuantity) }, uniquingKeysWith: { first, _ in first })
        let names = Dictionary(products.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        let facts = chosen.map { VoiceStockFact(name: names[$0] ?? $0, quantity: quantities[$0] ?? 0) }
        return VoiceAnswers.stock(spoken: spokenText(reference), facts: facts)
    }

    private func customerOrdersAnswer(_ name: String) -> VoiceAnswer {
        let id = sellerId
        let customers = fetch(FetchDescriptor<Customer>(predicate: #Predicate { $0.sellerId == id }))
        let candidates = customers.map { VoiceCandidate(id: $0.id, name: $0.displayName) }
        let match = CustomerMatcher.resolve(name: name, in: candidates)
        let names = Dictionary(customers.map { ($0.id, $0.displayName) }, uniquingKeysWith: { first, _ in first })
        guard case .found(let customerId) = match else {
            let ambiguous: [String]
            if case .ambiguous(let options) = match { ambiguous = options.compactMap { names[$0] } } else { ambiguous = [] }
            return VoiceAnswers.customerOrders(spoken: name, match: match, customerName: nil, orders: [],
                                               ambiguousNames: ambiguous)
        }
        let orders = fetch(FetchDescriptor<CustomerOrder>(predicate: #Predicate { $0.customerId == customerId },
                                                          sortBy: [SortDescriptor(\.orderedAt)]))
        let pending = orders.filter { $0.status == .draft || $0.status == .confirmed }
        let facts = pending.map { order in
            VoiceOrderFact(cycle: order.cycle,
                           lines: (order.lines ?? []).map { VoiceStockFact(name: $0.productName, quantity: $0.quantity) })
        }
        return VoiceAnswers.customerOrders(spoken: name, match: match, customerName: names[customerId], orders: facts)
    }

    private func salesAnswer(_ period: VoicePeriod) -> VoiceAnswer {
        let interval = period.interval(containing: .now, calendar: .current)
        let id = sellerId
        let start = interval.start
        let end = interval.end
        let sales = fetch(FetchDescriptor<LocalSale>(predicate: #Predicate {
            $0.sellerId == id && $0.occurredAt >= start && $0.occurredAt < end
        })).filter { $0.syncState != .failed && $0.kind == .sale }
        let total = sales.reduce(Money.zero) { $0 + $1.total }
        return VoiceAnswers.sales(period: period, count: sales.count, total: total)
    }

    private func cycleAnswer() -> VoiceAnswer {
        let id = sellerId
        let customerCycles = fetch(FetchDescriptor<CustomerOrder>(predicate: #Predicate { $0.sellerId == id })).map(\.cycle)
        let naturaCycles = fetch(FetchDescriptor<NaturaOrder>(predicate: #Predicate { $0.sellerId == id })).map(\.cycle)
        let latest = (customerCycles + naturaCycles).filter { $0 >= 10_000 }.max()
        let settings = fetch(FetchDescriptor<SellerSettings>(predicate: #Predicate { $0.sellerId == id })).first
        let current = settings?.currentCycleCode.map {
            VoiceCycleFact(code: $0, start: settings?.currentCycleStart, end: settings?.currentCycleEnd)
        }
        return VoiceAnswers.cycle(current: current, latestKnown: latest)
    }

    /// Navegación por voz: cambia de pestaña o abre la pantalla en una hoja (cierra esta primero).
    private func navigate(_ destination: VoiceDestination) -> VoiceAnswer {
        let tab: AppTab?
        var screen: AppScreen?
        switch destination {
        case .sell: tab = .sell
        case .products: tab = .products
        case .receiving: tab = .receiving
        case .customers: tab = .customers
        case .settings: tab = .settings
        case .profit: tab = nil; screen = .profit
        case .salesHistory: tab = nil; screen = .salesHistory
        case .magazine: tab = nil; screen = .magazine
        case .orderDraft: tab = nil; screen = .orderDraft
        case .offers: tab = nil; screen = .offers
        case .account: tab = nil; screen = .account
        case .receivables: tab = nil; screen = .receivables
        case .customerOrder(let name):
            tab = nil
            let id = sellerId
            let customers = fetch(FetchDescriptor<Customer>(predicate: #Predicate { $0.sellerId == id }))
            let match = CustomerMatcher.resolve(name: name, in: customers.map { VoiceCandidate(id: $0.id, name: $0.displayName) })
            guard case .found(let customerId) = match else {
                return VoiceAnswer(text: "No encontré a “\(name)” entre tus clientes.")
            }
            var descriptor = FetchDescriptor<CustomerOrder>(predicate: #Predicate { $0.customerId == customerId },
                                                            sortBy: [SortDescriptor(\.orderedAt, order: .reverse)])
            descriptor.fetchLimit = 1
            guard let order = fetch(descriptor).first else {
                let display = customers.first { $0.id == customerId }?.displayName ?? name
                return VoiceAnswer(text: "\(display) no tiene pedidos.")
            }
            screen = .customerOrder(id: order.id)
        }
        let router = router
        if let tab { router.tab = tab }
        close()
        if let screen {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(450))
                router.pendingScreen = screen
            }
        }
        return VoiceAnswer(text: "Abriendo \(destination.label).")
    }

    private func receivablesAnswer(_ name: String?) -> VoiceAnswer {
        guard let name else {
            return VoiceAnswers.debtors(store.debtors(sellerId: sellerId).map { ($0.name, $0.debt.balancePesos) })
        }
        let id = sellerId
        let customers = fetch(FetchDescriptor<Customer>(predicate: #Predicate { $0.sellerId == id }))
        let match = CustomerMatcher.resolve(name: name, in: customers.map { VoiceCandidate(id: $0.id, name: $0.displayName) })
        guard case .found(let customerId) = match else { return VoiceAnswer(text: "No encontré a “\(name)” entre tus clientes.") }
        let display = customers.first { $0.id == customerId }?.displayName ?? name
        return VoiceAnswers.customerDebt(name: display, debt: store.customerDebt(sellerId: sellerId, customerId: customerId))
    }

    private func accountSnapshot() -> NaturaAccountSnapshot? {
        let id = sellerId
        return fetch(FetchDescriptor<NaturaAccountSnapshot>(predicate: #Predicate { $0.sellerId == id })).first
    }

    private func spokenText(_ reference: ProductRef) -> String {
        switch reference {
        case .sku(let code): "código \(code)"
        case .text(let text): text
        }
    }
}
