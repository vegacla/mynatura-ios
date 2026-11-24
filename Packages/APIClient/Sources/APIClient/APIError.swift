/// Errores de red normalizados (§8). Los mensajes de UI van en español.
public enum APIError: Error, Equatable, Sendable {
    /// No hay URL de servidor configurada o es inválida.
    case notConfigured
    /// Sin conexión (o el servidor no responde).
    case offline
    /// Otro error de transporte.
    case network(String)
    /// 401: sesión inválida o credenciales incorrectas.
    case unauthorized(message: String?)
    /// 400/422 y otros 4xx de regla de negocio.
    case validation(message: String)
    case conflict(message: String)
    case notFound
    case server(status: Int)
    case decoding(String)

    /// El backend no se pudo alcanzar: la app puede seguir en modo offline.
    public var isUnreachable: Bool {
        switch self {
        case .notConfigured, .offline, .network, .server: true
        default: false
        }
    }

    public var userMessage: String {
        switch self {
        case .notConfigured: "Configura la URL del servidor."
        case .offline: "Sin conexión con el servidor."
        case .network(let detail): "Error de red: \(detail)"
        case .unauthorized: "Tu sesión expiró. Vuelve a ingresar."
        case .validation(let message), .conflict(let message): message
        case .notFound: "No encontrado."
        case .server(let status): "El servidor respondió con error (\(status))."
        case .decoding: "Respuesta inesperada del servidor."
        }
    }

    static func from(status: Int, message: String?) -> APIError {
        switch status {
        case 401: .unauthorized(message: message)
        case 404: .notFound
        case 409: .conflict(message: message ?? "Conflicto (409).")
        case 400..<500: .validation(message: message ?? "Solicitud rechazada (\(status)).")
        default: .server(status: status)
        }
    }
}
