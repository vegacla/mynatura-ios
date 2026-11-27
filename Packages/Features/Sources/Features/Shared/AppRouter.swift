import Observation
import SwiftUI

public enum AppTab: Hashable, Sendable {
    case sell, products, receiving, customers, settings
}

/// Acción pedida desde fuera de la app (Atajos / Siri, V7): voz o foto de producto.
public enum VoiceLaunch: String, Identifiable, Hashable, Sendable {
    case ask
    case dictateSale
    case newCustomerOrder
    case productPhoto

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
    /// Pantalla pedida por voz ("abre la revista"); la raíz la muestra en una hoja.
    public var pendingScreen: AppScreen?

    public init() {}

    public func launch(_ voice: VoiceLaunch) {
        switch voice {
        case .ask: break
        case .dictateSale: tab = .sell
        case .newCustomerOrder: tab = .customers
        case .productPhoto: break
        }
        pendingVoice = voice
    }
}

/// Pantallas que se abren por voz en una hoja (navegación por voz).
public enum AppScreen: Identifiable, Hashable, Sendable {
    case profit, salesHistory, magazine, orderDraft, offers, account
    case customerOrder(id: String)

    public var id: String {
        switch self {
        case .customerOrder(let id): "customerOrder-\(id)"
        default: String(describing: self)
        }
    }
}

/// Hoja con una pantalla pedida por voz.
public struct AppScreenSheet: View {
    @Environment(\.dismiss) private var dismiss
    let screen: AppScreen
    let sellerId: String

    public init(screen: AppScreen, sellerId: String) {
        self.screen = screen
        self.sellerId = sellerId
    }

    public var body: some View {
        NavigationStack {
            Group {
                switch screen {
                case .profit: MarginReportScreen(sellerId: sellerId)
                case .salesHistory: SalesHistoryScreen(sellerId: sellerId)
                case .magazine: MagazineView(sellerId: sellerId).navigationTitle("Revista")
                case .orderDraft: NaturaOrderDraftEntry(sellerId: sellerId)
                case .offers: CycleOffersScreen(sellerId: sellerId)
                case .account: NaturaAccountScreen(sellerId: sellerId)
                case .customerOrder(let id): CustomerOrderEditor(sellerId: sellerId, orderId: id)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cerrar") { dismiss() } }
            }
        }
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
        case .productPhoto:
            ProductPhotoSheet(sellerId: sellerId)
        }
    }
}
