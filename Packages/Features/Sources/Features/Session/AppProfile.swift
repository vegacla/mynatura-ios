import Foundation
import Natura
import Observation
import Persistence

/// Perfil local (M7): reemplaza al login con el backend. La app abre directo; los datos se identifican con el
/// `sellerId` del perfil. "Borrar datos del iPhone" deja la app como recién instalada.
@MainActor
@Observable
public final class AppProfile {
    public private(set) var sellerId: String
    public private(set) var customerCode: String

    private let repository: SessionRepository

    public init(repository: SessionRepository) {
        self.repository = repository
        let profile = repository.ensureLocalProfile()
        sellerId = profile.sellerId
        customerCode = profile.customerCode
    }

    /// Recuerda el código de consultora (tras importar desde Natura).
    public func rememberCustomerCode(_ code: String) {
        let trimmed = code.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        repository.updateCustomerCode(trimmed)
        customerCode = trimmed
    }

    /// Borra todos los datos y las credenciales de Natura; crea un perfil nuevo.
    public func eraseAll() {
        NaturaCredentialStore.delete()
        try? repository.deleteAll()
        let profile = repository.ensureLocalProfile()
        sellerId = profile.sellerId
        customerCode = profile.customerCode
    }
}
