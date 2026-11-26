import Observation
import SwiftUI

public enum AppTab: Hashable, Sendable {
    case sell, products, receiving, customers, settings
}

/// Acción de voz pedida desde fuera de la app (Atajos / Siri, V7).
public enum VoiceLaunch: String, Identifiable, Hashable, Sendable {
    case ask
    case dictateSale
    case newCustomerOrder

    public var id: String { rawValue }
}

/// Navegación entre pestañas (p. ej. "Convertir en venta" lleva a Vender).
@MainActor
@Observable
public final class AppRouter {
    /// Instancia única: la usan la app y los App Intents (que corren en el proceso de la app).
    public static let shared = AppRouter()

    public var tab: AppTab = .sell
    /// Acción de voz pendiente; la pantalla raíz la consume al estar lista (con sesión iniciada).
    public var pendingVoice: VoiceLaunch?

    public init() {}

    public func launch(_ voice: VoiceLaunch) {
        switch voice {
        case .ask: break
        case .dictateSale: tab = .sell
        case .newCustomerOrder: tab = .customers
        }
        pendingVoice = voice
    }
}

/// Hoja que abre una acción de voz pedida desde un Atajo.
public struct VoiceLaunchSheet: View {
    let launch: VoiceLaunch
    let sellerId: String

    public init(launch: VoiceLaunch, sellerId: String) {
        self.launch = launch
        self.sellerId = sellerId
    }

    public var body: some View {
        switch launch {
        case .ask:
            VoiceQuerySheet(sellerId: sellerId)
        case .dictateSale:
            CartVoiceSheet(sellerId: sellerId) { _ in }
        case .newCustomerOrder:
            NavigationStack {
                CustomerOrderEditor(sellerId: sellerId, orderId: nil, startDictating: true)
            }
        }
    }
}
