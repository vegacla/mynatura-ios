import Foundation

/// Valores de prellenado del login inyectados en Info.plist por el build de simulador (Appetize).
/// En el IPA quedan vacíos. Nunca son credenciales de Natura.
struct DevLoginDefaults {
    let serverURL: String?
    let customerCode: String?
    let password: String?

    static let current = DevLoginDefaults(bundle: .main)

    init(bundle: Bundle) {
        func value(_ key: String) -> String? {
            guard let raw = bundle.object(forInfoDictionaryKey: key) as? String else { return nil }
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty || trimmed.hasPrefix("$(") ? nil : trimmed
        }
        serverURL = value("MNDevServerURL")
        customerCode = value("MNDevCustomerCode")
        password = value("MNDevPassword")
    }
}
