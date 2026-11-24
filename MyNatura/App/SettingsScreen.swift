import APIClient
import Core
import SwiftUI

struct SettingsScreen: View {
    @Environment(SessionStore.self) private var session
    @State private var confirmingLogout = false

    var body: some View {
        NavigationStack {
            List {
                if let current = session.current {
                    Section("Sesión") {
                        LabeledContent("Nombre", value: current.displayName)
                        LabeledContent("Código", value: current.customerCode)
                        if current.isOffline {
                            Label("Sin conexión: usando datos locales", systemImage: "icloud.slash")
                                .foregroundStyle(.orange)
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
                                .foregroundStyle(.green)
                        }
                    }
                    Section {
                        Button("Cerrar sesión", role: .destructive) { confirmingLogout = true }
                    }
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
            .confirmationDialog("¿Cerrar sesión?", isPresented: $confirmingLogout, titleVisibility: .visible) {
                Button("Cerrar sesión", role: .destructive) {
                    Task { await session.logout() }
                }
            } message: {
                Text("Se borrarán los datos locales de esta cuenta en el iPhone.")
            }
        }
    }
}

/// Pantalla de diagnóstico para depurar sin Xcode (ver §13.1).
struct DiagnosticsScreen: View {
    @Environment(SessionStore.self) private var session
    @AppStorage(BackendSettings.key) private var backendURL = ""
    @State private var sample = ""
    @State private var healthResult: String?
    @State private var isChecking = false

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
