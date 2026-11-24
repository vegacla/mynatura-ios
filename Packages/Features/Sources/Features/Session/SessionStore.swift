import APIClient
import Core
import Foundation
import Observation
import Persistence

/// Estado de sesión de la app (§4.1): login, restauración online/offline y logout.
@MainActor
@Observable
public final class SessionStore {
    public struct CurrentSession: Equatable, Sendable {
        public let sellerId: String
        public let customerCode: String
        public let displayName: String
        /// Entró con el `SessionSummary` local porque el backend no respondió.
        public var isOffline: Bool
    }

    public enum Phase: Equatable, Sendable {
        case restoring
        case signedOut
        case signedIn(CurrentSession)
    }

    public private(set) var phase: Phase = .restoring
    /// Último código usado, para precargar el login.
    public private(set) var lastCustomerCode = ""
    public private(set) var isRevalidating = false

    public let api: any APIClient
    private let repository: SessionRepository

    public init(api: any APIClient, repository: SessionRepository) {
        self.api = api
        self.repository = repository
    }

    public var current: CurrentSession? {
        if case .signedIn(let session) = phase { return session }
        return nil
    }

    // MARK: - Restaurar

    public func restore() async {
        let cached = repository.current()
        if let cached { lastCustomerCode = cached.customerCode }
        let hasCredential = api.hasSessionCredential

        var remote: SessionRestorePolicy.RemoteCheck?
        var remoteSession: AuthSessionDTO?
        if SessionRestorePolicy.shouldCheckRemote(hasCredential: hasCredential) {
            (remote, remoteSession) = await checkRemote()
        }

        switch SessionRestorePolicy.outcome(hasCachedSummary: cached != nil, hasCredential: hasCredential, remote: remote) {
        case .online:
            if let remoteSession { signIn(remoteSession) } else { phase = .signedOut }
        case .offline:
            if let cached {
                phase = .signedIn(CurrentSession(
                    sellerId: cached.sellerId, customerCode: cached.customerCode,
                    displayName: cached.displayName, isOffline: true))
            } else {
                phase = .signedOut
            }
        case .signedOut:
            phase = .signedOut
        }
    }

    /// Reintenta validar contra el backend si se entró offline (al volver a foreground o a pedido).
    public func revalidateIfOffline() async {
        guard let session = current, session.isOffline, !isRevalidating else { return }
        isRevalidating = true
        defer { isRevalidating = false }
        let (remote, dto) = await checkRemote()
        switch remote {
        case .valid:
            if let dto { signIn(dto) }
        case .unauthorized:
            phase = .signedOut
        case .unreachable:
            break
        }
    }

    /// Llamar cuando cualquier request devuelva 401.
    public func handleUnauthorized() {
        api.clearSessionCredential()
        phase = .signedOut
    }

    private func checkRemote() async -> (SessionRestorePolicy.RemoteCheck, AuthSessionDTO?) {
        do throws(APIError) {
            return (.valid, try await api.send(.me))
        } catch .unauthorized {
            return (.unauthorized, nil)
        } catch {
            return (.unreachable, nil)
        }
    }

    // MARK: - Login / logout

    /// Devuelve un mensaje de error para la UI, o nil si entró.
    public func login(customerCode: String, password: String) async -> String? {
        let code = LoginForm.normalizedCustomerCode(customerCode)
        do throws(LoginFormError) {
            try LoginForm.validate(customerCode: code, password: password)
        } catch {
            return error.message
        }
        lastCustomerCode = code

        do throws(APIError) {
            let dto = try await api.send(.login(customerCode: code, password: password))
            signIn(dto)
            return nil
        } catch {
            return Self.loginMessage(for: error)
        }
    }

    /// Cierra sesión: avisa al backend si hay red y borra cookie y datos locales de la cuenta.
    public func logout() async {
        if current?.isOffline == false {
            _ = try? await api.send(.logout)
        }
        api.clearSessionCredential()
        try? repository.deleteAll()
        phase = .signedOut
    }

    private func signIn(_ dto: AuthSessionDTO) {
        let seller = dto.seller
        _ = try? repository.upsert(sellerId: seller.id, customerCode: seller.customerCode, displayName: seller.displayName)
        lastCustomerCode = seller.customerCode
        phase = .signedIn(CurrentSession(
            sellerId: seller.id, customerCode: seller.customerCode,
            displayName: seller.displayName, isOffline: false))
    }

    static func loginMessage(for error: APIError) -> String {
        switch error {
        case .unauthorized:
            "Código o contraseña incorrectos."
        case .offline:
            "No se pudo conectar con el servidor. El primer ingreso necesita conexión. "
                + "Revisa la URL del servidor y, si iOS lo pide, permite el acceso a la red local."
        default:
            error.userMessage
        }
    }
}
