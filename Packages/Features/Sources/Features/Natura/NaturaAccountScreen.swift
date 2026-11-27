import Core
import DesignSystem
import Natura
import Persistence
import SwiftData
import SwiftUI
import Sync

/// Cuenta Natura (M6): ciclo vigente con fechas, crédito, bloqueo y pagos (`mis-cuentas`).
/// Muestra la última lectura guardada; "Actualizar" usa la contraseña guardada (Touch ID).
struct NaturaAccountScreen: View {
    @Environment(SyncEngine.self) private var sync
    @Query private var snapshots: [NaturaAccountSnapshot]
    @Query private var settings: [SellerSettings]
    let sellerId: String
    @State private var refreshing = false
    @State private var message: (text: String, isError: Bool)?

    init(sellerId: String) {
        self.sellerId = sellerId
        _snapshots = Query(filter: #Predicate<NaturaAccountSnapshot> { $0.sellerId == sellerId })
        _settings = Query(filter: #Predicate<SellerSettings> { $0.sellerId == sellerId })
    }

    private var snapshot: NaturaAccountSnapshot? { snapshots.first }

    var body: some View {
        List {
            CycleSection(settings: settings.first)
            if let credit = snapshot?.credit {
                if credit.isBlocked {
                    AlertBanner("Tu cuenta Natura aparece bloqueada. Revisa tus pagos o consulta a tu líder.", tone: .danger,
                                systemImage: "lock.fill")
                }
                Section("Crédito") {
                    money("Disponible", credit.availablePesos)
                    money("Límite", credit.limitPesos)
                    if let additional = credit.additionalPesos, additional > 0 { money("Adicional", additional) }
                }
            }
            if let documents = snapshot?.documents {
                PaymentsSection(documents: documents)
            }
            Section {
                Button(action: refresh) {
                    HStack {
                        Label("Actualizar", systemImage: "arrow.clockwise")
                        Spacer()
                        if refreshing { ProgressView() }
                    }
                }
                .disabled(refreshing || !sync.connectivity.isOnline)
                if let message { AlertBanner(message.text, tone: message.isError ? .danger : .success) }
            } footer: {
                if !sync.connectivity.isOnline {
                    Text("Sin conexión: se muestra la última lectura.")
                } else if let fetched = snapshot?.fetchedAt {
                    Text("Actualizado \(fetched.formatted(.relative(presentation: .named))). También se actualiza al traer pedidos de Natura.")
                } else {
                    Text("Se lee de Natura al actualizar o al traer pedidos.")
                }
            }
        }
        .navigationTitle("Cuenta Natura")
        .overlay {
            if snapshot == nil && settings.first?.currentCycleCode == nil {
                ContentUnavailableView("Sin datos de tu cuenta", systemImage: "person.text.rectangle",
                                       description: Text("Toca Actualizar o trae tus pedidos desde Ajustes › Natura."))
            }
        }
    }

    private func money(_ label: String, _ pesos: Int?) -> some View {
        LabeledContent(label, value: pesos.map { Money(pesos: $0).formatted } ?? "—")
    }

    private func refresh() {
        guard NaturaCredentialStore.hasSavedPassword(), let code = NaturaCredentialStore.savedCustomerCode() else {
            message = ("Guarda tu contraseña en Ajustes › Natura (Touch ID) para actualizar desde aquí, o usa “Actualizar desde Natura”.", true)
            return
        }
        refreshing = true
        message = nil
        Task {
            defer { refreshing = false }
            let password: String
            do throws(NaturaCredentialStore.StoreError) {
                password = try await NaturaCredentialStore.loadPassword(reason: "Leer tu cuenta Natura")
            } catch {
                message = (error.message, true)
                return
            }
            switch await sync.refreshNaturaAccount(sellerId: sellerId, customerCode: code, password: password) {
            case .success(let text):
                message = (text, false)
            case .failure(let error):
                if error.isCredentialError { NaturaCredentialStore.delete() }
                message = (error.isCredentialError ? error.message + " Se borró la contraseña guardada." : error.message, true)
            }
        }
    }
}

private struct CycleSection: View {
    let settings: SellerSettings?

    var body: some View {
        if let code = settings?.currentCycleCode {
            Section("Ciclo vigente") {
                LabeledContent("Ciclo", value: CycleCode.label(code))
                if let start = settings?.currentCycleStart {
                    LabeledContent("Inicio", value: start.formatted(date: .abbreviated, time: .omitted))
                }
                if let end = settings?.currentCycleEnd {
                    LabeledContent("Cierre", value: end.formatted(date: .abbreviated, time: .omitted))
                    let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: .now),
                                                               to: Calendar.current.startOfDay(for: end)).day ?? 0
                    LabeledContent("Quedan", value: days > 1 ? "\(days) días" : days == 1 ? "1 día" : days == 0 ? "Cierra hoy" : "Cerrado")
                }
            }
        }
    }
}

private struct PaymentsSection: View {
    let documents: [NaturaAccountDocument]

    var body: some View {
        let summary = NaturaAccountSummary(documents: documents)
        let pending = documents.filter(\.isPending).sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
        Section {
            if summary.overdueCount > 0 {
                AlertBanner("\(summary.overdueCount) documento(s) vencido(s) por \(Money(pesos: summary.overduePesos).formatted) · hasta \(summary.maxOverdueDays) día(s) de atraso.",
                            tone: .danger, systemImage: "exclamationmark.triangle.fill")
            }
            LabeledContent("Saldo pendiente", value: Money(pesos: summary.pendingPesos).formatted)
            if let next = summary.nextDue, let due = next.dueDate {
                LabeledContent("Próximo vencimiento") {
                    Text("\(due.formatted(date: .abbreviated, time: .omitted)) · \(Money(pesos: next.balancePesos ?? 0).formatted)")
                }
            }
            ForEach(pending, id: \.number) { document in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Pedido \(document.orderNumber)").font(.subheadline.weight(.medium))
                        Spacer()
                        Text(Money(pesos: document.balancePesos ?? 0).formatted).font(.subheadline.monospacedDigit())
                    }
                    HStack(spacing: 6) {
                        if let due = document.dueDate { Text("Vence \(due.formatted(date: .abbreviated, time: .omitted))") }
                        if document.isOverdue || document.overdueDays > 0 {
                            StatusBadge("Vencido · \(document.overdueDays) d", tone: .danger)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Pagos")
        } footer: {
            if pending.isEmpty { Text("Sin documentos pendientes.") }
        }
    }
}
