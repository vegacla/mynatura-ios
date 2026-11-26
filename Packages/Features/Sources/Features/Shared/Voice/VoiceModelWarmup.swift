import Foundation
import Persistence
import SwiftData

/// Prepara el vocabulario propio con todo el catálogo y los clientes de la consultora, para que todas las
/// pantallas de voz compartan el mismo modelo (misma versión ⇒ se arma una sola vez).
@MainActor
enum VoiceModelWarmup {
    static func prepare(_ speech: SpeechCaptureService, sellerId: String, context: ModelContext) async {
        let id = sellerId
        let products = (try? context.fetch(FetchDescriptor<CatalogProduct>(predicate: #Predicate { $0.sellerId == id }))) ?? []
        let customers = (try? context.fetch(FetchDescriptor<Customer>(predicate: #Predicate { $0.sellerId == id }))) ?? []
        await speech.prepareCustomModel(productNames: products.map(\.name), productCodes: products.map(\.naturaSku),
                                        customerNames: customers.map(\.displayName))
    }
}
