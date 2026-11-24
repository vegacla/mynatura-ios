import Foundation

/// Reglas de sesión espejo de backend/src/modules/auth (repo mynatura).
public enum LoginFormError: Error, Equatable, Sendable {
    case customerCodeTooShort
    case passwordTooShort

    public var message: String {
        switch self {
        case .customerCodeTooShort: "El código de cliente debe tener al menos 3 caracteres."
        case .passwordTooShort: "La contraseña debe tener al menos 8 caracteres."
        }
    }
}

public enum LoginForm {
    public static let minCustomerCodeLength = 3
    public static let minPasswordLength = 8

    /// Mismas reglas que `loginBodySchema` (zod): código con trim ≥ 3, contraseña ≥ 8.
    public static func validate(customerCode: String, password: String) throws(LoginFormError) {
        guard normalizedCustomerCode(customerCode).count >= minCustomerCodeLength else {
            throw .customerCodeTooShort
        }
        guard password.count >= minPasswordLength else { throw .passwordTooShort }
    }

    public static func normalizedCustomerCode(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Decide cómo entrar a la app al abrirla (§4.1).
public enum SessionRestorePolicy {
    /// Resultado de `GET /api/auth/me`.
    public enum RemoteCheck: Equatable, Sendable {
        case valid
        case unauthorized
        /// Sin red, servidor caído o no configurado.
        case unreachable
    }

    public enum Outcome: Equatable, Sendable {
        case online
        case offline
        case signedOut
    }

    /// - Parameters:
    ///   - hasCachedSummary: hay un `SessionSummary` local de la última sesión.
    ///   - hasCredential: hay cookie de sesión guardada.
    ///   - remote: resultado de validar contra el backend (nil si no se intentó).
    public static func outcome(hasCachedSummary: Bool, hasCredential: Bool, remote: RemoteCheck?) -> Outcome {
        guard hasCredential else { return .signedOut }
        switch remote {
        case .valid: return .online
        case .unauthorized: return .signedOut
        case .unreachable, nil: return hasCachedSummary ? .offline : .signedOut
        }
    }

    /// Si hay que llamar al backend antes de decidir.
    public static func shouldCheckRemote(hasCredential: Bool) -> Bool { hasCredential }
}
