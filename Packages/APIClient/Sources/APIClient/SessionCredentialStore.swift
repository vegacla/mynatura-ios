import Foundation

/// Dónde se guarda la cookie de sesión de la app (Keychain en iOS).
/// Nunca guarda credenciales de Natura.
public protocol SessionCredentialStore: Sendable {
    func load() -> [String: String]
    func save(_ cookies: [String: String])
    func clear()
}

/// Implementación en memoria (tests y previews).
public final class InMemoryCredentialStore: SessionCredentialStore, @unchecked Sendable {
    private let lock = NSLock()
    private var cookies: [String: String]

    public init(_ cookies: [String: String] = [:]) {
        self.cookies = cookies
    }

    public func load() -> [String: String] {
        lock.lock(); defer { lock.unlock() }
        return cookies
    }

    public func save(_ cookies: [String: String]) {
        lock.lock(); defer { lock.unlock() }
        self.cookies = cookies
    }

    public func clear() { save([:]) }
}
