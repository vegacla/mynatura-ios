import APIClient
import Core
import DesignSystem
import Persistence
import SwiftData
import SwiftUI
import Sync

/// Ajustes (§4.8): sesión, datos locales, salida de inventario, diagnóstico.
public struct SettingsScreen: View {
    @Environment(SessionStore.self) private var session
    @Environment(SyncEngine.self) private var sync
    @Query private var mutations: [PendingMutation]
    @State private var confirmingLogout = false
    private let sellerId: String

    public init(sellerId: String) {
        self.sellerId = sellerId
        _mutations = Query(filter: #Predicate<PendingMutation> { $0.sellerId == sellerId })
    }

    public var body: some View {
        NavigationStack {
            List {
                if let current = session.current {
                    SessionSection(current: current)
                    OfflineStatusSection(sellerId: sellerId)
                    IssueStrategySection(sellerId: sellerId, isOffline: !sync.connectivity.isOnline)
                    NaturaImportSection(sellerId: sellerId)
                    Section("Historial y reportes") {
                        NavigationLink("Historial de importaciones") { ImportRunsScreen() }
                        NavigationLink("Historial de ventas") { SalesHistoryScreen(sellerId: sellerId) }
                        NavigationLink("Reporte de margen") { MarginReportScreen(sellerId: sellerId) }
                    }
                    DatasetsSection(sellerId: sellerId, isOffline: !sync.connectivity.isOnline)
                    Section {
                        Button("Cerrar sesión", role: .destructive) { confirmingLogout = true }
                    }
                }
                Section("Aplicación") {
                    LabeledContent("Versión", value: AppInfo.versionLabel)
                    LabeledContent("Bundle", value: AppInfo.bundleIdentifier)
                }
                Section {
                    NavigationLink("Diagnóstico") { DiagnosticsScreen(sellerId: sellerId) }
                }
            }
            .navigationTitle("Ajustes")
            .syncStatusToolbar(sellerId: sellerId)
            .confirmationDialog("¿Cerrar sesión?", isPresented: $confirmingLogout, titleVisibility: .visible) {
                Button("Cerrar sesión", role: .destructive) {
                    Task { await session.logout() }
                }
            } message: {
                if mutations.isEmpty {
                    Text("Se borrarán los datos locales de esta cuenta en el iPhone.")
                } else {
                    Text("Hay \(mutations.count) cambio(s) sin sincronizar que se perderán. Sincroniza antes de salir si puedes.")
                }
            }
        }
    }
}

private struct SessionSection: View {
    @Environment(SessionStore.self) private var session
    let current: SessionStore.CurrentSession

    var body: some View {
        Section("Sesión") {
            LabeledContent("Nombre", value: current.displayName)
            LabeledContent("Código", value: current.customerCode)
            if current.isOffline {
                Label("Sin conexión: usando datos locales", systemImage: "icloud.slash")
                    .foregroundStyle(StatusTone.warning.color)
                Button {
                    Task { await session.revalidateIfOffline() }
                } label: {
                    if session.isRevalidating {
                        ProgressView()
                    } else {
                        Text("Reintentar conexión")
                    }
                }
                .disabled(session.isRevalidating)
            } else {
                Label("En línea", systemImage: "checkmark.icloud")
                    .foregroundStyle(StatusTone.success.color)
            }
        }
    }
}

/// FIFO / LIFO (§4.8). Se cambia solo con conexión.
private struct IssueStrategySection: View {
    @Environment(SyncEngine.self) private var sync
    @Query private var settings: [SellerSettings]
    let sellerId: String
    let isOffline: Bool
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(sellerId: String, isOffline: Bool) {
        self.sellerId = sellerId
        self.isOffline = isOffline
        _settings = Query(filter: #Predicate<SellerSettings> { $0.sellerId == sellerId })
    }

    private var strategy: IssueStrategy { settings.first?.issueStrategy ?? .fifo }

    var body: some View {
        Section {
            Picker("Estrategia", selection: Binding(get: { strategy }, set: { newValue in save(newValue) })) {
                ForEach(IssueStrategy.allCases, id: \.self) { option in
                    Text(option.label).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .disabled(isOffline || isSaving || settings.isEmpty)
            if let errorMessage {
                AlertBanner(errorMessage, tone: .danger)
            }
        } header: {
            Text("Salida de inventario")
        } footer: {
            Text(isOffline ? "Disponible solo con conexión." : strategy.detail)
        }
    }

    private func save(_ newValue: IssueStrategy) {
        guard newValue != strategy else { return }
        isSaving = true
        errorMessage = nil
        Task {
            errorMessage = await sync.updateIssueStrategy(newValue, sellerId: sellerId)
            isSaving = false
        }
    }
}

/// Última descarga por dataset + "Sincronizar ahora" (§4.8; la cola de pendientes llega en la etapa 4).
private struct DatasetsSection: View {
    @Environment(SyncEngine.self) private var sync
    @Query private var states: [DatasetSyncState]
    let sellerId: String
    let isOffline: Bool

    init(sellerId: String, isOffline: Bool) {
        self.sellerId = sellerId
        self.isOffline = isOffline
        _states = Query(filter: #Predicate<DatasetSyncState> { $0.sellerId == sellerId }, sort: \.datasetRaw)
    }

    var body: some View {
        Section("Datos locales") {
            ForEach(states) { state in
                DatasetRow(state: state)
            }
            Button {
                Task { await sync.syncNow(sellerId: sellerId) }
            } label: {
                HStack {
                    Text("Descargar todo")
                    Spacer()
                    if sync.isPulling { ProgressView() }
                }
            }
            .disabled(sync.isSyncing || isOffline)
        }
    }
}

private struct DatasetRow: View {
    let state: DatasetSyncState

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(state.dataset?.label ?? state.datasetRaw)
                Spacer()
                switch state.status {
                case .synced: StatusBadge("Al día", tone: .success)
                case .syncing: StatusBadge("Sincronizando", tone: .info)
                case .failed: StatusBadge("Falló", tone: .danger)
                case .idle: StatusBadge("Sin datos")
                }
            }
            if let date = state.lastSyncedAt {
                Text("Última: \(date.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if state.status == .failed, let message = state.errorMessage {
                Text(message).font(.caption).foregroundStyle(StatusTone.danger.color)
            }
        }
    }
}

/// Pantalla de diagnóstico para depurar sin Xcode (§13.1): servidor, logs, cola, último error.
struct DiagnosticsScreen: View {
    @Environment(SessionStore.self) private var session
    @Environment(SyncEngine.self) private var sync
    @AppStorage(BackendSettings.key) private var backendURL = ""
    @State private var sample = ""
    @State private var healthResult: String?
    @State private var isChecking = false
    @State private var logLines: [String] = []
    let sellerId: String

    var body: some View {
        List {
            Section("Build") {
                LabeledContent("Versión", value: AppInfo.versionLabel)
                LabeledContent("iOS", value: UIDevice.current.systemVersion)
            }
            Section("Servidor") {
                ServerURLField(text: $backendURL)
                Button("Probar conexión", action: checkHealth)
                    .disabled(isChecking)
                if isChecking {
                    ProgressView()
                } else if let healthResult {
                    Text(healthResult).font(.footnote)
                }
                LabeledContent("Cookie de sesión", value: session.api.hasSessionCredential ? "Guardada" : "No")
                LabeledContent("Red", value: sync.connectivity.isOnline ? "Con conexión" : "Sin conexión")
                if let error = sync.lastErrorMessage {
                    LabeledContent("Último error", value: error)
                }
            }
            Section {
                NavigationLink("Cola de mutaciones") { SyncQueueScreen(sellerId: sellerId) }
            }
            Section {
                if logLines.isEmpty {
                    Text("Sin registros recientes").foregroundStyle(.secondary)
                } else {
                    ShareLink("Compartir log", item: logLines.joined(separator: "\n"))
                    ForEach(Array(logLines.suffix(80).reversed().enumerated()), id: \.offset) { _, line in
                        Text(line).font(.caption2.monospaced())
                    }
                }
            } header: {
                HStack {
                    Text("Log (últimas 6 h)")
                    Spacer()
                    Button("Actualizar") { logLines = AppLog.recentEntries() }.font(.caption)
                }
            }
            Section("Prueba de reglas (Core)") {
                TextField("Código EAN o SKU", text: $sample)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                LabeledContent("Normalizado", value: Normalize.scanCode(sample))
                LabeledContent("Ejemplo dinero", value: Money(pesos: 12990).formatted)
            }
        }
        .navigationTitle("Diagnóstico")
        .task { logLines = AppLog.recentEntries() }
    }

    private func checkHealth() {
        isChecking = true
        Task {
            do throws(APIError) {
                let health = try await session.api.send(.health)
                healthResult = "OK: \(health.status)"
            } catch {
                healthResult = error.userMessage
            }
            isChecking = false
        }
    }
}

enum AppInfo {
    static var versionLabel: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

    static var bundleIdentifier: String { Bundle.main.bundleIdentifier ?? "?" }
}
