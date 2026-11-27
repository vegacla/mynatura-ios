import Core
import DesignSystem
import Persistence
import Store
import SwiftData
import SwiftUI

/// "Por cobrar" en la ficha del cliente: saldo, compras pendientes, abonos y recordatorio por WhatsApp.
struct CustomerDebtSection: View {
    @Environment(LocalStore.self) private var store
    @Environment(\.openURL) private var openURL
    let customer: Customer
    let debt: CustomerDebt
    let payments: [CustomerPayment]
    let sellerId: String
    @State private var paying = false
    @State private var sharing = false

    private var reminder: String {
        CustomerDebtRules.reminderText(firstName: customer.displayName.split(separator: " ").first.map(String.init), debt: debt)
    }

    var body: some View {
        Section {
            LabeledContent("Te debe") {
                Text(Money(pesos: debt.balancePesos).formatted)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(debt.isEmpty ? StatusTone.success.color : StatusTone.warning.color)
            }
            ForEach(debt.unpaid, id: \.sale.id) { item in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(item.sale.date.formatted(date: .abbreviated, time: .omitted))
                        Spacer()
                        Text(Money(pesos: item.remainingPesos).formatted).monospacedDigit()
                    }
                    .font(.subheadline)
                    if !item.sale.summary.isEmpty {
                        Text(item.sale.summary).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            if !debt.isEmpty {
                Button { paying = true } label: { Label("Registrar pago", systemImage: "banknote") }
                if let link = NaturaMagazine.whatsAppURL(phone: customer.phone ?? "", text: reminder) {
                    Button { openURL(link) } label: { Label("Recordar cobro por WhatsApp", systemImage: "message") }
                } else {
                    Button { sharing = true } label: { Label("Recordar cobro", systemImage: "square.and.arrow.up") }
                }
            }
            if !payments.isEmpty {
                DisclosureGroup("Pagos recibidos (\(payments.count))") {
                    ForEach(payments) { payment in
                        HStack {
                            Text(payment.paidAt.formatted(date: .abbreviated, time: .omitted))
                            if let note = payment.note { Text(note).foregroundStyle(.secondary) }
                            Spacer()
                            Text(Money(pesos: payment.amountPesos).formatted).monospacedDigit()
                        }
                        .font(.caption)
                    }
                }
            }
        } header: {
            Text("Por cobrar")
        } footer: {
            Text("Las ventas fiadas se marcan en el carro (o en el historial). Cada pago descuenta primero la compra más antigua.")
        }
        .sheet(isPresented: $paying) {
            CustomerPaymentSheet(customer: customer, balancePesos: debt.balancePesos, sellerId: sellerId)
                .presentationDetents([.medium])
        }
        .sheet(isPresented: $sharing) {
            ActivityView(items: [reminder]) { _ in sharing = false }.ignoresSafeArea()
        }
    }
}

/// Registrar un abono del cliente.
struct CustomerPaymentSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(LocalStore.self) private var store
    let customer: Customer
    let balancePesos: Int
    let sellerId: String
    @State private var amount = Money.zero
    @State private var note = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                LabeledContent("Debe", value: Money(pesos: balancePesos).formatted)
                LabeledContent("Pago") { MoneyField("Monto", money: $amount).frame(maxWidth: 160) }
                Button("Pagó todo") { amount = Money(pesos: balancePesos) }
                TextField("Nota (opcional): efectivo, transferencia…", text: $note)
                if let errorMessage { AlertBanner(errorMessage, tone: .danger) }
            }
            .navigationTitle("Pago de \(customer.displayName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        if let error = store.registerCustomerPayment(sellerId: sellerId, customerId: customer.id,
                                                                     amountPesos: amount.pesos, note: note) {
                            errorMessage = error.message
                            Haptics.error()
                        } else {
                            Haptics.success()
                            dismiss()
                        }
                    }
                    .disabled(amount.pesos <= 0)
                }
            }
        }
    }
}

/// Clientes que te deben (Ajustes › Historial y reportes, y por voz: "abre por cobrar").
struct ReceivablesScreen: View {
    @Environment(LocalStore.self) private var store
    @Query private var sales: [LocalSale]
    @Query private var payments: [CustomerPayment]
    let sellerId: String

    init(sellerId: String) {
        self.sellerId = sellerId
        _sales = Query(filter: #Predicate<LocalSale> { $0.sellerId == sellerId && $0.onCredit })
        _payments = Query(filter: #Predicate<CustomerPayment> { $0.sellerId == sellerId })
    }

    var body: some View {
        // Leer `sales` y `payments` hace que la lista se refresque al registrar ventas fiadas o pagos.
        let _ = (sales.count, payments.count)
        let debtors = store.debtors(sellerId: sellerId)
        let total = debtors.reduce(0) { $0 + $1.debt.balancePesos }
        List {
            if !debtors.isEmpty {
                Section {
                    LabeledContent("Total por cobrar", value: Money(pesos: total).formatted)
                }
            }
            ForEach(debtors, id: \.customerId) { item in
                NavigationLink {
                    CustomerDetailScreen(customerId: item.customerId, sellerId: sellerId)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(item.name).font(.body.weight(.medium))
                            Spacer()
                            Text(Money(pesos: item.debt.balancePesos).formatted).monospacedDigit()
                        }
                        if let oldest = item.debt.oldest {
                            Text("\(item.debt.unpaid.count) compra(s) · desde \(oldest.formatted(date: .abbreviated, time: .omitted))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Por cobrar")
        .overlay {
            if debtors.isEmpty {
                ContentUnavailableView("Nadie te debe", systemImage: "checkmark.seal",
                                       description: Text("Marca una venta como fiada en el carro para llevar lo que te deben."))
            }
        }
    }
}
