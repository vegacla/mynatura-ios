import Observation
import SwiftUI

public enum AppTab: Hashable, Sendable {
    case sell, products, receiving, customers, settings
}

/// Navegación entre pestañas (p. ej. "Convertir en venta" lleva a Vender).
@MainActor
@Observable
public final class AppRouter {
    public var tab: AppTab = .sell

    public init() {}
}
