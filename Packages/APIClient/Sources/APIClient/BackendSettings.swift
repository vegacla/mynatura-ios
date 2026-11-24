import Foundation

/// URL del backend elegida por la persona (Login › Servidor o Diagnóstico), en UserDefaults. Ver §13.5.
public enum BackendSettings {
    public static let key = "backendURL"

    public static var url: URL? {
        BackendURL.parse(UserDefaults.standard.string(forKey: key) ?? "")
    }
}
