import Core
import Foundation
import Persistence
import SwiftData

/// Borrador del pedido Natura del ciclo (M8 etapa 2, docs/natura-order-placement.md §5.3 y §5.5). Local, sin conexión.
extension LocalStore {
    /// Ciclo del borrador: el vigente leído de Natura o, si no hay, el último de los pedidos de clientes.
    public func draftCycle(sellerId: String) -> Int? {
        if let code = settings(sellerId: sellerId).currentCycleCode { return code }
        return fetchAll(FetchDescriptor<CustomerOrder>(predicate: #Predicate { $0.sellerId == sellerId })).map(\.cycle).max()
    }

    /// El borrador del ciclo; si no existe, se crea con el tope del ciclo anterior y los encargos confirmados.
    @discardableResult
    public func orderDraft(sellerId: String, cycle: Int) -> NaturaOrderDraft {
        let key = NaturaOrderDraft.key(sellerId: sellerId, cycle: cycle)
        if let existing = fetchAll(FetchDescriptor<NaturaOrderDraft>(predicate: #Predicate { $0.key == key })).first {
            return existing
        }
        let draft = NaturaOrderDraft(sellerId: sellerId, cycle: cycle)
        var previous = FetchDescriptor<NaturaOrderDraft>(predicate: #Predicate { $0.sellerId == sellerId },
                                                         sortBy: [SortDescriptor(\.cycle, order: .reverse)])
        previous.fetchLimit = 1
        draft.pointsLimit = fetchAll(previous).first?.pointsLimit
        context.insert(draft)
        refreshDraftFromCustomers(draft)
        return draft
    }

    /// Recalcula las líneas de encargos (pedidos de clientes confirmados del ciclo − stock) y los puntos y precios.
    public func refreshDraftFromCustomers(sellerId: String, cycle: Int) {
        refreshDraftFromCustomers(orderDraft(sellerId: sellerId, cycle: cycle))
    }

    func refreshDraftFromCustomers(_ draft: NaturaOrderDraft) {
        let sellerId = draft.sellerId
        let cycle = draft.cycle
        let confirmed = CustomerOrderStatus.confirmed.rawValue
        let orders = fetchAll(FetchDescriptor<CustomerOrder>(predicate: #Predicate {
            $0.sellerId == sellerId && $0.cycle == cycle && $0.statusRaw == confirmed
        }))
        let demand = orders.flatMap { order in
            (order.lines ?? []).map {
                DraftDemand(sku: $0.naturaSku, name: $0.productName, customer: order.customerDisplayName, quantity: $0.quantity)
            }
        }
        let stock = stockBySku(sellerId: sellerId)
        let merged = OrderDraftRules.merge(draft.lines, suggestions: OrderDraftRules.suggestions(demand: demand, stock: stock))
        draft.lines = merged.map { withCycleInfo($0, sellerId: sellerId, cycle: cycle) }
        save()
    }

    /// "¿Qué tengo que pedir?": encargos confirmados del ciclo − stock, sin tocar el borrador.
    public func cycleSuggestions(sellerId: String, cycle: Int) -> [OrderDraftLine] {
        let confirmed = CustomerOrderStatus.confirmed.rawValue
        let orders = fetchAll(FetchDescriptor<CustomerOrder>(predicate: #Predicate {
            $0.sellerId == sellerId && $0.cycle == cycle && $0.statusRaw == confirmed
        }))
        let demand = orders.flatMap { order in
            (order.lines ?? []).map {
                DraftDemand(sku: $0.naturaSku, name: $0.productName, customer: order.customerDisplayName, quantity: $0.quantity)
            }
        }
        return OrderDraftRules.suggestions(demand: demand, stock: stockBySku(sellerId: sellerId))
    }

    /// Pedidos de clientes del ciclo en borrador: no suman hasta confirmarlos.
    public func unconfirmedCustomerOrders(sellerId: String, cycle: Int) -> Int {
        let draftStatus = CustomerOrderStatus.draft.rawValue
        return fetchAll(FetchDescriptor<CustomerOrder>(predicate: #Predicate {
            $0.sellerId == sellerId && $0.cycle == cycle && $0.statusRaw == draftStatus
        })).count
    }

    public func addDraftProduct(sellerId: String, cycle: Int, productId: String, source: OrderDraftSource, quantity: Int = 1) {
        guard let product = product(id: productId) else { return }
        let draft = orderDraft(sellerId: sellerId, cycle: cycle)
        var lines = draft.lines
        let sku = Normalize.naturaSku(product.naturaSku)
        if let index = lines.firstIndex(where: { $0.sku == sku }) {
            lines[index].quantity += quantity
        } else {
            lines.append(withCycleInfo(OrderDraftLine(sku: sku, name: product.name, quantity: quantity, source: source),
                                       sellerId: sellerId, cycle: cycle))
        }
        draft.lines = lines
        save()
    }

    /// Cantidad de una línea; 0 la quita.
    public func setDraftQuantity(sellerId: String, cycle: Int, sku: String, quantity: Int) {
        let draft = orderDraft(sellerId: sellerId, cycle: cycle)
        var lines = draft.lines
        guard let index = lines.firstIndex(where: { $0.sku == sku }) else { return }
        if quantity <= 0 { lines.remove(at: index) } else { lines[index].quantity = quantity }
        draft.lines = lines
        save()
    }

    public func setDraftPointsLimit(sellerId: String, cycle: Int, limit: Int?) {
        orderDraft(sellerId: sellerId, cycle: cycle).pointsLimit = limit.flatMap { $0 > 0 ? $0 : nil }
        save()
    }

    public func clearDraft(sellerId: String, cycle: Int) {
        orderDraft(sellerId: sellerId, cycle: cycle).lines = []
        save()
    }

    // MARK: - Ayudas

    func stockBySku(sellerId: String) -> [String: Int] {
        let products = fetchAll(FetchDescriptor<CatalogProduct>(predicate: #Predicate { $0.sellerId == sellerId }))
        let stock = fetchAll(FetchDescriptor<StockItem>(predicate: #Predicate { $0.sellerId == sellerId }))
        let byProduct = Dictionary(stock.map { ($0.sellerProductId, $0.operationalQuantity) }, uniquingKeysWith: { first, _ in first })
        var result: [String: Int] = [:]
        for product in products {
            result[Normalize.naturaSku(product.naturaSku), default: 0] += byProduct[product.id] ?? 0
        }
        return result
    }

    /// Puntos y precio de compra del ciclo (catálogo de GSP), solo si el producto está en ese ciclo.
    func withCycleInfo(_ line: OrderDraftLine, sellerId: String, cycle: Int) -> OrderDraftLine {
        var line = line
        guard let product = product(sku: line.sku, sellerId: sellerId) else { return line }
        if product.cycleCode == cycle {
            line.pointsPerUnit = product.cyclePoints ?? line.pointsPerUnit
            line.purchasePesos = product.cyclePurchasePesos ?? line.purchasePesos
        }
        if line.name.isEmpty { line.name = product.name }
        return line
    }
}
