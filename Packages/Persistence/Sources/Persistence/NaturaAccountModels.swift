import Core
import Foundation
import SwiftData

/// Última lectura de la cuenta con Natura (M6): crédito, bloqueo y documentos de `mis-cuentas`.
/// Es caché: se muestra con "actualizado hace X" y se refresca bajo demanda. No va en el respaldo.
@Model
public final class NaturaAccountSnapshot {
    @Attribute(.unique) public var sellerId: String
    public var fetchedAt: Date
    public var creditAvailablePesos: Int?
    public var creditLimitPesos: Int?
    public var creditAdditionalPesos: Int?
    public var isBlocked: Bool
    /// nil = no se pudo leer el crédito en la última actualización.
    public var creditFetchedAt: Date?
    public var documentsData: Data?
    public var documentsFetchedAt: Date?

    public init(sellerId: String) {
        self.sellerId = sellerId
        self.fetchedAt = .now
        self.isBlocked = false
    }

    public var credit: NaturaCredit? {
        get {
            creditFetchedAt == nil ? nil : NaturaCredit(availablePesos: creditAvailablePesos, limitPesos: creditLimitPesos,
                                                        additionalPesos: creditAdditionalPesos, isBlocked: isBlocked)
        }
        set {
            creditAvailablePesos = newValue?.availablePesos
            creditLimitPesos = newValue?.limitPesos
            creditAdditionalPesos = newValue?.additionalPesos
            isBlocked = newValue?.isBlocked ?? false
            creditFetchedAt = newValue == nil ? nil : .now
        }
    }

    public var documents: [NaturaAccountDocument]? {
        get { documentsData.flatMap { try? JSONDecoder().decode([NaturaAccountDocument].self, from: $0) } }
        set {
            documentsData = newValue.flatMap { try? JSONEncoder().encode($0) }
            documentsFetchedAt = newValue == nil ? documentsFetchedAt : .now
        }
    }
}
