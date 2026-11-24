#if canImport(Security)
import Foundation
import Security

/// Cookie de sesión de la app en Keychain (solo este dispositivo, disponible tras el primer desbloqueo).
/// Nunca se guardan aquí credenciales de Natura.
///
/// Mantiene además una copia en memoria: si Keychain no está disponible (p. ej. un build de simulador sin firmar,
/// como en Appetize, donde SecItemAdd falla por falta de entitlements) la sesión igual funciona mientras la app
/// esté abierta; solo se pierde al cerrarla.
public final class KeychainCredentialStore: SessionCredentialStore, @unchecked Sendable {
    private let service = "cl.mynatura.app.session"
    private let account = "cookies"
    private let lock = NSLock()
    private var cache: [String: String]?

    public init() {}

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    public func load() -> [String: String] {
        lock.lock(); defer { lock.unlock() }
        if let cache { return cache }
        let stored = readKeychain()
        cache = stored
        return stored
    }

    public func save(_ cookies: [String: String]) {
        lock.lock(); defer { lock.unlock() }
        cache = cookies
        SecItemDelete(baseQuery as CFDictionary)
        guard !cookies.isEmpty, let data = try? JSONEncoder().encode(cookies) else { return }
        var attributes = baseQuery
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(attributes as CFDictionary, nil)
    }

    public func clear() { save([:]) }

    private func readKeychain() -> [String: String] {
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
}
#endif
