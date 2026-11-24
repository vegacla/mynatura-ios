#if canImport(Security)
import Foundation
import Security

/// Cookie de sesión de la app en Keychain (solo este dispositivo, disponible tras el primer desbloqueo).
/// Nunca se guardan aquí credenciales de Natura.
public final class KeychainCredentialStore: SessionCredentialStore {
    private let service = "cl.mynatura.app.session"
    private let account = "cookies"

    public init() {}

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    public func load() -> [String: String] {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let cookies = try? JSONDecoder().decode([String: String].self, from: data)
        else { return [:] }
        return cookies
    }

    public func save(_ cookies: [String: String]) {
        guard !cookies.isEmpty, let data = try? JSONEncoder().encode(cookies) else {
            clear()
            return
        }
        SecItemDelete(baseQuery as CFDictionary)
        var attributes = baseQuery
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(attributes as CFDictionary, nil)
    }

    public func clear() {
        SecItemDelete(baseQuery as CFDictionary)
    }
}
#endif
