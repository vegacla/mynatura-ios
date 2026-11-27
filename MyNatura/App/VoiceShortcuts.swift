import AppIntents
import Core
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

// MARK: - Respuestas sin abrir la app (solo lectura)

@MainActor
private func spokenAnswer(_ answer: VoiceAnswer) -> IntentDialog {
    IntentDialog(full: LocalizedStringResource(stringLiteral: answer.speech),
                 supporting: LocalizedStringResource(stringLiteral: answer.text))
}

@MainActor
private func answer(_ query: VoiceQuery) -> IntentDialog {
    spokenAnswer(VoiceQueryService.answer(query, container: AppDependencies.container, store: AppDependencies.store,
                                          sellerId: AppDependencies.profile.sellerId))
}

/// "Consultar en MyNatura": Siri pregunta qué quieres saber y responde con los datos del iPhone.
struct QueryMyNaturaIntent: AppIntent {
    static var title: LocalizedStringResource { "Consultar en MyNatura" }
    static var description: IntentDescription {
        IntentDescription("Responde sin abrir la app: stock, encargos, ventas, ciclo, crédito, pagos y lo que te deben.")
    }
    static var openAppWhenRun: Bool { false }

    @Parameter(title: "Pregunta", requestValueDialog: "¿Qué quieres saber?")
    var question: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let reply = VoiceQueryService.answer(question, container: AppDependencies.container, store: AppDependencies.store,
                                             sellerId: AppDependencies.profile.sellerId)
        return .result(dialog: spokenAnswer(reply))
    }
}

struct WhoOwesMeIntent: AppIntent {
    static var title: LocalizedStringResource { "Quién me debe" }
    static var description: IntentDescription { IntentDescription("Dice quién te debe y cuánto (ventas fiadas).") }
    static var openAppWhenRun: Bool { false }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: answer(.receivables(name: nil)))
    }
}

struct CycleCloseIntent: AppIntent {
    static var title: LocalizedStringResource { "Cuándo cierra el ciclo" }
    static var description: IntentDescription { IntentDescription("Dice el ciclo vigente y cuántos días quedan.") }
    static var openAppWhenRun: Bool { false }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: answer(.cycle))
    }
}

struct CreditIntent: AppIntent {
    static var title: LocalizedStringResource { "Crédito Natura" }
    static var description: IntentDescription { IntentDescription("Dice tu crédito disponible (última lectura de Natura).") }
    static var openAppWhenRun: Bool { false }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: answer(.credit))
    }
}

struct SalesTodayIntent: AppIntent {
    static var title: LocalizedStringResource { "Ventas de hoy" }
    static var description: IntentDescription { IntentDescription("Dice cuánto vendiste hoy.") }
    static var openAppWhenRun: Bool { false }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: answer(.sales(.today)))
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
        AppShortcut(
            intent: QueryMyNaturaIntent(),
            phrases: [
                "Consultar en \(.applicationName)",
                "Pregúntale a \(.applicationName)",
            ],
            shortTitle: "Consultar",
            systemImageName: "text.bubble")
        AppShortcut(
            intent: WhoOwesMeIntent(),
            phrases: [
                "Quién me debe en \(.applicationName)",
                "Por cobrar en \(.applicationName)",
            ],
            shortTitle: "Quién me debe",
            systemImageName: "banknote")
        AppShortcut(
            intent: CycleCloseIntent(),
            phrases: [
                "Cuándo cierra el ciclo en \(.applicationName)",
                "Ciclo de \(.applicationName)",
            ],
            shortTitle: "Cierre del ciclo",
            systemImageName: "calendar")
        AppShortcut(
            intent: CreditIntent(),
            phrases: [
                "Cuánto crédito tengo en \(.applicationName)",
                "Crédito de \(.applicationName)",
            ],
            shortTitle: "Crédito",
            systemImageName: "creditcard")
        AppShortcut(
            intent: SalesTodayIntent(),
            phrases: [
                "Cuánto vendí hoy en \(.applicationName)",
                "Ventas de hoy en \(.applicationName)",
            ],
            shortTitle: "Ventas de hoy",
            systemImageName: "chart.bar")
    }
}
