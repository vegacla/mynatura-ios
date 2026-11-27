import AppIntents
import Features

// Atajos de Siri / app Atajos (V7 de docs/voice-interaction-proposal.md). Viven en el target de la app (sin
// extensión: compatible con Apple ID gratis) y siempre abren la app: la acción sigue siendo "la voz propone,
// la pantalla confirma", con la sesión y los datos locales de siempre.

struct AskMyNaturaIntent: AppIntent {
    static var title: LocalizedStringResource { "Preguntar a MyNatura" }
    static var description: IntentDescription {
        IntentDescription("Abre las consultas por voz: stock, encargos, ventas y ciclo.")
    }
    static var openAppWhenRun: Bool { true }

    @MainActor
    func perform() async throws -> some IntentResult {
        AppRouter.shared.launch(.ask)
        return .result()
    }
}

struct DictateSaleIntent: AppIntent {
    static var title: LocalizedStringResource { "Dictar venta" }
    static var description: IntentDescription {
        IntentDescription("Abre Vender con el dictado del carro. La venta se registra siempre con un toque.")
    }
    static var openAppWhenRun: Bool { true }

    @MainActor
    func perform() async throws -> some IntentResult {
        AppRouter.shared.launch(.dictateSale)
        return .result()
    }
}

struct NewCustomerOrderIntent: AppIntent {
    static var title: LocalizedStringResource { "Nuevo pedido de cliente" }
    static var description: IntentDescription {
        IntentDescription("Abre un pedido de cliente nuevo con el dictado listo.")
    }
    static var openAppWhenRun: Bool { true }

    @MainActor
    func perform() async throws -> some IntentResult {
        AppRouter.shared.launch(.newCustomerOrder)
        return .result()
    }
}

struct ProductPhotoIntent: AppIntent {
    static var title: LocalizedStringResource { "Foto de producto" }
    static var description: IntentDescription {
        IntentDescription("Abre la cámara para reconocer un producto y elegir qué hacer con él.")
    }
    static var openAppWhenRun: Bool { true }

    @MainActor
    func perform() async throws -> some IntentResult {
        AppRouter.shared.launch(.productPhoto)
        return .result()
    }
}

struct AssistantIntent: AppIntent {
    static var title: LocalizedStringResource { "Asistente de MyNatura" }
    static var description: IntentDescription {
        IntentDescription("Abre el Asistente: escanea o nombra un producto o cliente y elige qué hacer.")
    }
    static var openAppWhenRun: Bool { true }

    @MainActor
    func perform() async throws -> some IntentResult {
        AppRouter.shared.launch(.assistant)
        return .result()
    }
}

struct MyNaturaShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AssistantIntent(),
            phrases: [
                "Asistente de \(.applicationName)",
                "Abrir asistente de \(.applicationName)",
            ],
            shortTitle: "Asistente",
            systemImageName: "sparkles")
        AppShortcut(
            intent: AskMyNaturaIntent(),
            phrases: [
                "Preguntar a \(.applicationName)",
                "Consultar en \(.applicationName)",
            ],
            shortTitle: "Preguntar",
            systemImageName: "mic.circle")
        AppShortcut(
            intent: DictateSaleIntent(),
            phrases: [
                "Dictar venta en \(.applicationName)",
                "Nueva venta en \(.applicationName)",
            ],
            shortTitle: "Dictar venta",
            systemImageName: "cart")
        AppShortcut(
            intent: NewCustomerOrderIntent(),
            phrases: [
                "Nuevo pedido en \(.applicationName)",
                "Anotar pedido en \(.applicationName)",
            ],
            shortTitle: "Nuevo pedido",
            systemImageName: "person.badge.plus")
        AppShortcut(
            intent: ProductPhotoIntent(),
            phrases: [
                "Foto de producto en \(.applicationName)",
                "Reconocer producto en \(.applicationName)",
            ],
            shortTitle: "Foto de producto",
            systemImageName: "camera.viewfinder")
    }
}
