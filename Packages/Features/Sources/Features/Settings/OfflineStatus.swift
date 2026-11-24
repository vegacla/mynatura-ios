import APIClient
import Core
import DesignSystem
import Persistence
import SwiftData
import SwiftUI
import Sync

/// Estado offline (§4.8): conectividad, pendientes, fallidos y acciones.
struct OfflineStatusSection: View {
    @Environment(SyncEngine.self) private var sync
    @Query private var mutations: [PendingMutation]
    let sellerId: String

    init(sellerId: String) {
        self.sellerId = sellerId
        _mutations = Query(filter: #Predicate<PendingMutation> { $0.sellerId == sellerId }, sort: \.createdAt)
    }

    var body: some View {
        let failed = mutations.filter { $0.status == .failed }
        Section {
            LabeledContent("Conectividad") {
                Label(sync.connectivity.isOnline ? "En línea" : "Sin conexión",
                      systemImage: sync.connectivity.isOnline ? "wifi" : "wifi.slash")
            }
            LabeledContent("Pendientes", value: "\(mutations.count - failed.count)")
            LabeledContent("Fallidos", value: "\(failed.count)")
            if let last = sync.lastPushAt {
                LabeledContent("Último envío", value: last.formatted(date: .omitted, time: .shortened))
            }
            Button {
                Task { await sync.syncNow(sellerId: sellerId) }
            } label: {
                HStack {
                    Text("Sincronizar ahora")
                    Spacer()
                    if sync.isSyncing { ProgressView() }
                }
            }
            .disabled(sync.isSyncing || !sync.connectivity.isOnline)
            ForEach(failed) { mutation in
                FailedMutationRow(mutation: mutation, sellerId: sellerId)
            }
            if failed.count > 1 {
                Button("Reintentar todos los fallidos") { sync.retryAllFailed(sellerId: sellerId) }
            }
            NavigationLink("Cola de sincronización (\(mutations.count))") { SyncQueueScreen(sellerId: sellerId) }
        } header: {
            Text("Estado offline")
        } footer: {
            Text("Los cambios se guardan primero en el iPhone y se envían solos cuando hay red. Los rechazados por el servidor quedan como fallidos para revisarlos.")
        }
    }
}

struct FailedMutationRow: View {
    @Environment(SyncEngine.self) private var sync
    let mutation: PendingMutation
    let sellerId: String
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(mutation.type?.label ?? mutation.typeRaw).font(.subheadline.weight(.medium))
                Spacer()
                StatusBadge(mutation.status == .failed ? "Falló" : "Pendiente", tone: mutation.status == .failed ? .danger : .warning)
            }
            Text(mutation.createdAt.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
            if let message = mutation.lastErrorMessage {
                Text(message).font(.caption).foregroundStyle(StatusTone.danger.color)
            }
            if let errorMessage { AlertBanner(errorMessage, tone: .danger) }
            HStack {
                if mutation.type == .saleCreate {
                    NavigationLink("Revisar") { SaleReviewScreen(saleId: mutation.entityKey, sellerId: sellerId) }
                        .buttonStyle(.bordered)
                }
                Button("Reintentar") { sync.retry(mutation, sellerId: sellerId) }
                    .buttonStyle(.bordered)
                Button("Descartar", role: .destructive) {
                    errorMessage = sync.discard(mutation, sellerId: sellerId)?.message
                }
                .buttonStyle(.bordered)
            }
            .font(.caption)
        }
        .padding(.vertical, 4)
    }
}

/// Toda la cola, en orden de envío.
struct SyncQueueScreen: View {
    @Query private var mutations: [PendingMutation]
    let sellerId: String

    init(sellerId: String) {
        self.sellerId = sellerId
        _mutations = Query(filter: #Predicate<PendingMutation> { $0.sellerId == sellerId })
    }

    var body: some View {
        let ordered = SyncQueue.sorted(mutations, type: { $0.type ?? .saleCreate }, createdAt: \.createdAt)
        List {
            ForEach(ordered) { mutation in
                VStack(alignment: .leading, spacing: 4) {
                    FailedMutationRow(mutation: mutation, sellerId: sellerId)
                    Text("Intentos: \(mutation.retryCount) · \(mutation.entityKey)")
                        .font(.caption2.monospaced()).foregroundStyle(.secondary)
                    DisclosureGroup("Payload") {
                        Text(mutation.payloadText).font(.caption2.monospaced()).textSelection(.enabled)
                    }
                    .font(.caption)
                }
            }
        }
        .overlay {
            if mutations.isEmpty {
                ContentUnavailableView("Todo sincronizado", systemImage: "checkmark.icloud")
            }
        }
        .navigationTitle("Cola")
    }
}

/// Sincronización Natura (§4.8): credenciales en memoria, nunca guardadas.
struct NaturaImportSection: View {
    @Environment(SyncEngine.self) private var sync
    let sellerId: String
    @State private var customerCode = ""
    @State private var password = ""
    @State private var importing = false
    @State private var result: (text: String, isError: Bool)?

    var body: some View {
        Section {
            TextField("Código cliente Natura", text: $customerCode)
                .keyboardType(.asciiCapable)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            SecureField("Contraseña Natura", text: $password)
                .textContentType(.password)
            Button {
                runImport()
            } label: {
                HStack {
                    Text("Cargar pedidos entregados")
                    Spacer()
                    if importing { ProgressView() }
                }
            }
            .disabled(importing || customerCode.isEmpty || password.isEmpty || !sync.connectivity.isOnline)
            if importing {
                Text("Conectando con Natura… puede tardar varios minutos.").font(.footnote).foregroundStyle(.secondary)
            }
            if let result {
                AlertBanner(result.text, tone: result.isError ? .danger : .success)
            }
        } header: {
            Text("Sincronización Natura")
        } footer: {
            if sync.connectivity.isOnline {
                Text("La contraseña de Natura se envía una sola vez al servidor y no se guarda en el iPhone.")
            } else {
                OnlineOnlyNote(text: "Importar desde Natura requiere conexión.")
            }
        }
    }

    private func runImport() {
        importing = true
        result = nil
        let code = customerCode
        let secret = password
        Task {
            switch await sync.importNaturaOrders(sellerId: sellerId, customerCode: code, password: secret) {
            case .success(let message): result = (message, false)
            case .failure(let error): result = (error.message, true)
            }
            password = ""
            importing = false
        }
    }
}

/// Historial de importaciones (online).
struct ImportRunsScreen: View {
    @Environment(SyncEngine.self) private var sync
    @State private var runs: [NaturaImportRunDTO] = []
    @State private var errorMessage: String?
    @State private var loading = true

    var body: some View {
        List {
            if let errorMessage { AlertBanner(errorMessage, tone: .warning) }
            ForEach(runs) { run in
                VStack(alignment: .leading, spacing: 2) {
                    Text(run.startedAt.formatted(date: .abbreviated, time: .shortened)).font(.subheadline.weight(.medium))
                    Text("\(run.importedOrderCount) pedido(s) · \(run.importedLineCount) línea(s)")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .overlay {
            if loading { ProgressView() } else if runs.isEmpty, errorMessage == nil {
                ContentUnavailableView("Sin importaciones", systemImage: "tray.and.arrow.down")
            }
        }
        .navigationTitle("Importaciones")
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        loading = true
        switch await sync.importRuns() {
        case .success(let value):
            runs = value
            errorMessage = nil
        case .failure(let error):
            errorMessage = error.message
        }
        loading = false
    }
}
