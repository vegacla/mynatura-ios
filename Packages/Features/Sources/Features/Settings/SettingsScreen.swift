import Core
import DesignSystem
import Persistence
import SwiftData
import SwiftUI
import Store

/// Ajustes: cuenta Natura, costeo, importación, respaldo, reportes y diagnóstico. Sin backend (M7).
public struct SettingsScreen: View {
    @Environment(AppProfile.self) private var profile
    @State private var confirmingErase = false
    private let sellerId: String

    public init(sellerId: String) {
        self.sellerId = sellerId
    }

    public var body: some View {
        NavigationStack {
            List {
                Section("Consultora") {
                    LabeledContent("Código Natura", value: profile.customerCode.isEmpty ? "—" : profile.customerCode)
                }
                IssueStrategySection(sellerId: sellerId)
                NaturaImportSection(sellerId: sellerId)
                BackupSection(sellerId: sellerId)
                Section("Historial y reportes") {
                    NavigationLink("Historial de ventas") { SalesHistoryScreen(sellerId: sellerId) }
                    NavigationLink("Ganancias") { MarginReportScreen(sellerId: sellerId) }
                }
                Section {
                    Button("Borrar datos del iPhone", role: .destructive) { confirmingErase = true }
                } footer: {
                    Text("Deja la app como recién instalada: borra productos, lotes, ventas, clientes, pedidos y la contraseña guardada.")
                }
                Section("Aplicación") {
                    LabeledContent("Versión", value: AppInfo.versionLabel)
                    LabeledContent("Bundle", value: AppInfo.bundleIdentifier)
                }
                Section {
                    NavigationLink("Diagnóstico") { DiagnosticsScreen() }
                }
            }
            .navigationTitle("Ajustes")
            .mainToolbar(sellerId: sellerId)
            .confirmationDialog("¿Borrar todos los datos del iPhone?", isPresented: $confirmingErase, titleVisibility: .visible) {
                Button("Borrar todo", role: .destructive) { profile.eraseAll() }
            } message: {
                Text("No se puede deshacer. Exporta un respaldo antes si quieres conservar tus datos.")
            }
        }
    }
}

/// Método de costeo (docs/local-first-migration.md §4.4): local, sin conexión.
private struct IssueStrategySection: View {
    @Environment(LocalStore.self) private var store
    @Query private var settings: [SellerSettings]
    let sellerId: String

    init(sellerId: String) {
        self.sellerId = sellerId
        _settings = Query(filter: #Predicate<SellerSettings> { $0.sellerId == sellerId })
    }

    private var method: CostingMethod { settings.first?.costingMethod ?? .fifo }

    var body: some View {
        Section {
            Picker("Método", selection: Binding(get: { method }, set: { store.setCostingMethod($0, sellerId: sellerId) })) {
                ForEach(CostingMethod.allCases, id: \.self) { option in
                    Text(option.label).tag(option)
                }
            }
            .pickerStyle(.segmented)
        } header: {
            Text("Método de costeo")
        } footer: {
            Text(method.detail + " Una unidad que llegó gratis de Natura se valoriza con el precio de compra conocido según este método. Cambiarlo afecta solo las salidas futuras.")
        }
    }
}

/// Diagnóstico para depurar sin Xcode (§13.1): build, red, último error y log.
struct DiagnosticsScreen: View {
    @Environment(LocalStore.self) private var store
    @State private var sample = ""
    @State private var logLines: [String] = []

    var body: some View {
        List {
            Section("Build") {
                LabeledContent("Versión", value: AppInfo.versionLabel)
                LabeledContent("iOS", value: UIDevice.current.systemVersion)
                LabeledContent("Red", value: store.connectivity.isOnline ? "Con conexión" : "Sin conexión")
                if let error = store.lastErrorMessage {
                    LabeledContent("Último error", value: error)
                }
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
