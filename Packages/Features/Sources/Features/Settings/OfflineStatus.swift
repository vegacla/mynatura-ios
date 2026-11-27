import APIClient
import Core
import DesignSystem
import Natura
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

/// Importación directa desde Natura (M3): pedidos entregados (Excel del pedido), ciclo vigente y catálogo del ciclo.
/// La contraseña se puede guardar en el Keychain con Touch ID (M5) y se borra desde aquí.
struct NaturaImportSection: View {
    @Environment(SyncEngine.self) private var sync
    @Query private var settings: [SellerSettings]
    let sellerId: String
    @State private var customerCode = ""
    @State private var password = ""
    @State private var savedCode: String?
    @State private var hasSavedPassword = false
    @State private var rememberPassword = true
    @State private var importing = false
    @State private var progress: String?
    @State private var result: (text: String, isError: Bool)?

    init(sellerId: String) {
        self.sellerId = sellerId
        _settings = Query(filter: #Predicate<SellerSettings> { $0.sellerId == sellerId })
    }

    private var current: SellerSettings? { settings.first }

    var body: some View {
        Section {
            TextField("Código de consultora Natura", text: $customerCode)
                .keyboardType(.asciiCapable)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if usesSavedPassword {
                LabeledContent("Contraseña") {
                    Label("Guardada · Touch ID", systemImage: "touchid")
                }
                Button("Olvidar contraseña", role: .destructive) {
                    NaturaCredentialStore.delete()
                    hasSavedPassword = false
                    savedCode = nil
                }
            } else {
                SecureField("Contraseña Natura", text: $password)
                    .textContentType(.password)
                Toggle("Guardar en este iPhone (Touch ID)", isOn: $rememberPassword)
            }
            Button {
                runImport()
            } label: {
                HStack {
                    Text(current?.naturaDirectSince == nil ? "Traer mis pedidos de Natura" : "Actualizar desde Natura")
                    Spacer()
                    if importing { ProgressView() }
                }
            }
            .disabled(importing || customerCode.isEmpty || (!usesSavedPassword && password.isEmpty) || !sync.connectivity.isOnline)
            if importing, let progress {
                Text(progress).font(.footnote).foregroundStyle(.secondary)
            }
            if let result {
                AlertBanner(result.text, tone: result.isError ? .danger : .success)
            } else if let summary = current?.lastNaturaImportSummary, let date = current?.lastNaturaImportAt {
                LabeledContent("Última importación", value: date.formatted(date: .abbreviated, time: .shortened))
                Text(summary).font(.footnote).foregroundStyle(.secondary)
            }
            if let code = current?.currentCycleCode {
                LabeledContent("Ciclo vigente") {
                    Text(cycleText(code: code, end: current?.currentCycleEnd))
                }
            }
            NavigationLink {
                NaturaAccountScreen(sellerId: sellerId)
            } label: {
                Label("Cuenta Natura (crédito y pagos)", systemImage: "person.text.rectangle")
            }
            NavigationLink {
                CycleOffersScreen(sellerId: sellerId)
            } label: {
                Label("Ofertas del ciclo", systemImage: "tag")
            }
            if sync.needsInitialInventory(sellerId: sellerId) {
                NavigationLink {
                    InitialInventoryScreen(sellerId: sellerId)
                } label: {
                    Label("Agregar inventario actual", systemImage: "shippingbox.and.arrow.backward")
                }
            }
        } header: {
            Text("Natura")
        } footer: {
            if !sync.connectivity.isOnline {
                OnlineOnlyNote(text: "Traer pedidos desde Natura requiere conexión.")
            } else if current?.naturaDirectSince == nil {
                Text("La primera vez trae todos tus pedidos entregados (con su costo y precio sugerido) y el catálogo del ciclo. Reemplaza lo que venía del servidor anterior. Si guardas la contraseña, queda solo en este iPhone, protegida con Touch ID.")
            } else {
                Text("Trae los pedidos entregados nuevos y actualiza el catálogo del ciclo. La contraseña guardada queda solo en este iPhone, protegida con Touch ID.")
            }
        }
        .onAppear(perform: loadSavedCredentials)
    }

    /// La contraseña guardada corresponde al código escrito.
    private var usesSavedPassword: Bool {
        hasSavedPassword && savedCode == customerCode.trimmingCharacters(in: .whitespaces)
    }

    private func loadSavedCredentials() {
        savedCode = NaturaCredentialStore.savedCustomerCode()
        hasSavedPassword = NaturaCredentialStore.hasSavedPassword()
        if customerCode.isEmpty, let savedCode { customerCode = savedCode }
    }

    private func cycleText(code: Int, end: Date?) -> String {
        let label = CycleCode.label(code)
        guard let end else { return label }
        return "\(label) · cierra \(end.formatted(date: .abbreviated, time: .omitted))"
    }

    private func runImport() {
        importing = true
        result = nil
        progress = "Conectando con Natura…"
        let code = customerCode.trimmingCharacters(in: .whitespaces)
        let usingSaved = usesSavedPassword
        let shouldSave = !usingSaved && rememberPassword
        let typed = password
        Task {
            var secret = typed
            defer {
                password = ""
                importing = false
                progress = nil
            }
            if usingSaved {
                do throws(NaturaCredentialStore.StoreError) {
                    secret = try await NaturaCredentialStore.loadPassword()
                } catch {
                    result = (error.message, true)
                    if case .unavailable = error { loadSavedCredentials() }
                    return
                }
            }
            let outcome = await sync.importFromNatura(sellerId: sellerId, customerCode: code, password: secret) { message in
                progress = message
            }
            switch outcome {
            case .success(let message):
                result = (message, false)
                if shouldSave {
                    do throws(NaturaCredentialStore.StoreError) {
                        try NaturaCredentialStore.save(customerCode: code, password: secret)
                        loadSavedCredentials()
                    } catch {
                        result = (message + " " + error.message, false)
                    }
                }
            case .failure(let error):
                if error.isCredentialError, usingSaved {
                    NaturaCredentialStore.delete()
                    loadSavedCredentials()
                    result = (error.message + " Se borró la contraseña guardada: escríbela de nuevo.", true)
                } else {
                    result = (error.message, true)
                }
            }
        }
    }
}

/// Resumen de la última importación (reemplaza el historial que guardaba el servidor).
struct ImportRunsScreen: View {
    var body: some View {
        ContentUnavailableView("Ver en Ajustes › Natura", systemImage: "tray.and.arrow.down",
                               description: Text("La última importación y su resumen se muestran en la sección Natura."))
            .navigationTitle("Importaciones")
    }
}
