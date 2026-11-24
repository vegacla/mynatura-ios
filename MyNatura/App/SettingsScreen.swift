import Core
import SwiftUI

struct SettingsScreen: View {
    var body: some View {
        NavigationStack {
            List {
                Section("Aplicación") {
                    LabeledContent("Versión", value: AppInfo.versionLabel)
                    LabeledContent("Bundle", value: AppInfo.bundleIdentifier)
                }
                Section {
                    NavigationLink("Diagnóstico") { DiagnosticsScreen() }
                }
            }
            .navigationTitle("Ajustes")
        }
    }
}

/// Pantalla de diagnóstico para depurar sin Xcode (ver §13.1).
struct DiagnosticsScreen: View {
    @State private var sample = ""

    var body: some View {
        List {
            Section("Build") {
                LabeledContent("Versión", value: AppInfo.versionLabel)
                LabeledContent("iOS", value: UIDevice.current.systemVersion)
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
