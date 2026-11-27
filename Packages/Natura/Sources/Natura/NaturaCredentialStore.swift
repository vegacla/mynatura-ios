#if canImport(Security) && canImport(LocalAuthentication)
import Foundation
import LocalAuthentication
import Security

/// Credenciales de Natura en el Keychain (docs/local-first-migration.md §3, decisión del 2026-11-26).
/// - El código de consultora se guarda sin biometría (para prellenar el campo).
/// - La contraseña, con `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` y Touch ID (o el código del iPhone):
///   no va al respaldo de iCloud ni a otro equipo, y se invalida si cambian las huellas.
/// Se leen solo al llamar a Natura y se pueden borrar desde Ajustes.
public enum NaturaCredentialStore {
    static let service = "cl.mynatura.app.natura"
    static let codeAccount = "customerCode"
    static let passwordAccount = "password"

    public enum StoreError: Error, Equatable, Sendable {
        case cancelled
        case unavailable(String)

        public var message: String {
            switch self {
            case .cancelled: "Se canceló la verificación. Escribe la contraseña o vuelve a intentarlo."
            case .unavailable(let detail): detail
            }
        }
    }

    // MARK: Código de consultora

    public static func savedCustomerCode() -> String? {
        var query = baseQuery(account: codeAccount)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: Contraseña

    /// Hay una contraseña guardada (sin pedir Touch ID).
    public static func hasSavedPassword() -> Bool {
        let context = LAContext()
        context.interactionNotAllowed = true
        var query = baseQuery(account: passwordAccount)
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecUseAuthenticationContext as String] = context
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess || status == errSecInteractionNotAllowed
    }

    /// Guarda código y contraseña (reemplaza lo anterior).
    public static func save(customerCode: String, password: String) throws(StoreError) {
        delete()
        var codeItem = baseQuery(account: codeAccount)
        codeItem[kSecValueData as String] = Data(customerCode.utf8)
        codeItem[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        SecItemAdd(codeItem as CFDictionary, nil)

        var error: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
                                                           [.biometryCurrentSet, .or, .devicePasscode], &error) else {
            throw .unavailable("No se pudo proteger la contraseña en este iPhone.")
        }
        var passwordItem = baseQuery(account: passwordAccount)
        passwordItem[kSecValueData as String] = Data(password.utf8)
        passwordItem[kSecAttrAccessControl as String] = access
        let status = SecItemAdd(passwordItem as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw .unavailable(status == errSecAuthFailed || status == errSecNotAvailable
                ? "Para guardar la contraseña, activa el código del iPhone (Ajustes › Touch ID y código)."
                : "No se pudo guardar la contraseña en el Keychain (\(status)).")
        }
    }

    /// Lee la contraseña pidiendo Touch ID (o el código del iPhone). Bloquea mientras se verifica: fuera del hilo principal.
    public static func loadPassword(reason: String = "Usar tu contraseña de Natura") async throws(StoreError) -> String {
        let result: Result<String, StoreError> = await Task.detached(priority: .userInitiated) {
            let context = LAContext()
            context.localizedReason = reason
            var query = baseQuery(account: passwordAccount)
            query[kSecReturnData as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne
            query[kSecUseAuthenticationContext as String] = context
            var item: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &item)
            switch status {
            case errSecSuccess:
                guard let data = item as? Data, let password = String(data: data, encoding: .utf8) else {
                    return .failure(.unavailable("La contraseña guardada no se pudo leer. Escríbela de nuevo."))
                }
                return .success(password)
            case errSecUserCanceled:
                return .failure(.cancelled)
            case errSecItemNotFound:
                return .failure(.unavailable("No hay contraseña guardada (o cambiaron las huellas). Escríbela de nuevo."))
            default:
                return .failure(.unavailable("No se pudo verificar tu identidad (\(status))."))
            }
        }.value
        return try result.get()
    }

    /// Borra código y contraseña.
    public static func delete() {
        SecItemDelete(baseQuery(account: codeAccount) as CFDictionary)
        SecItemDelete(baseQuery(account: passwordAccount) as CFDictionary)
    }

    static func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
#endif
