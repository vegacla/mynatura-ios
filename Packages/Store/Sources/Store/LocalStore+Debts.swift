import Core
import Foundation
import Persistence
import SwiftData

/// Lo que deben los clientes (ventas fiadas − abonos) y recordatorio de cobro.
extension LocalStore {
    public func customerDebt(sellerId: String, customerId: String) -> CustomerDebt {
        let sales = fetchAll(FetchDescriptor<LocalSale>(predicate: #Predicate {
            $0.sellerId == sellerId && $0.customerId == customerId && $0.onCredit
        }))
        let payments = fetchAll(FetchDescriptor<CustomerPayment>(predicate: #Predicate {
            $0.sellerId == sellerId && $0.customerId == customerId
        }))
        return CustomerDebtRules.debt(sales: sales.map(Self.debtSale), payments: payments.map(\.amountPesos))
    }

    /// Clientes con saldo por cobrar, de mayor a menor.
    public func debtors(sellerId: String) -> [(customerId: String, name: String, debt: CustomerDebt)] {
        let sales = fetchAll(FetchDescriptor<LocalSale>(predicate: #Predicate { $0.sellerId == sellerId && $0.onCredit }))
        let ids = Set(sales.compactMap(\.customerId))
        let customers = fetchAll(FetchDescriptor<Customer>(predicate: #Predicate { $0.sellerId == sellerId }))
        let names = Dictionary(customers.map { ($0.id, $0.displayName) }, uniquingKeysWith: { first, _ in first })
        return ids.map { id in (id, names[id] ?? "Cliente", customerDebt(sellerId: sellerId, customerId: id)) }
            .filter { !$0.debt.isEmpty }
            .sorted { $0.debt.balancePesos > $1.debt.balancePesos }
    }

    /// Abono del cliente; no puede superar lo que debe.
    @discardableResult
    public func registerCustomerPayment(sellerId: String, customerId: String, amountPesos: Int, note: String? = nil) -> ActionError? {
        guard amountPesos > 0 else { return ActionError("Ingresa el monto del pago.") }
        let balance = customerDebt(sellerId: sellerId, customerId: customerId).balancePesos
        guard amountPesos <= balance else {
            return ActionError("El pago supera lo que debe (\(Money(pesos: balance).formatted)).")
        }
        let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        context.insert(CustomerPayment(sellerId: sellerId, customerId: customerId, amountPesos: amountPesos,
                                       note: trimmed?.isEmpty == false ? trimmed : nil))
        save()
        return nil
    }

    /// Marca una venta ya registrada como fiada o pagada (solo ventas con cliente).
    public func setSaleOnCredit(saleId: String, onCredit: Bool) -> ActionError? {
        guard let sale = fetchAll(FetchDescriptor<LocalSale>(predicate: #Predicate { $0.id == saleId })).first else {
            return ActionError("Venta no encontrada.")
        }
        guard sale.kind == .sale else { return ActionError("Los obsequios no se cobran.") }
        guard !onCredit || sale.customerId != nil else { return ActionError("La venta no tiene cliente.") }
        sale.onCredit = onCredit
        save()
        return nil
    }

    static func debtSale(_ sale: LocalSale) -> DebtSale {
        let summary = sale.lines.prefix(3).map { "\($0.productName) ×\($0.quantity)" }.joined(separator: ", ")
            + (sale.lines.count > 3 ? "…" : "")
        return DebtSale(id: sale.id, date: sale.occurredAt, totalPesos: sale.total.pesos, summary: summary)
    }
}
