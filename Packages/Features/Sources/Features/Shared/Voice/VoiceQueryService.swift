import Core
import Foundation
import Persistence
import Store
import SwiftData

/// Responder una consulta fuera de las hojas (Atajos de Siri que contestan sin abrir la app).
/// Usa las mismas respuestas que "Preguntar" y el Asistente; solo lectura.
public enum VoiceQueryService {
    @MainActor
    public static func answer(_ question: String, container: ModelContainer, store: LocalStore, sellerId: String) -> VoiceAnswer {
        let resolver = VoiceQueryResolver(context: container.mainContext, sellerId: sellerId, router: AppRouter.shared,
                                          store: store, close: {})
        let commands = CommandGrammar.interpret(question, context: .global)
        let queries = commands.filter { if case .query = $0 { true } else { false } }
        guard !queries.isEmpty else {
            if commands.contains(where: { if case .navigate = $0 { true } else { false } }) {
                return VoiceAnswer(text: "Para eso abre MyNatura: di “Asistente de MyNatura”.")
            }
            return VoiceAnswers.notUnderstood(question)
        }
        let answers = queries.map { resolver.resolve($0) }
        return VoiceAnswer(text: answers.map(\.text).joined(separator: " "),
                           speech: answers.map(\.speech).joined(separator: " "))
    }

    /// Consultas fijas para los Atajos directos.
    @MainActor
    public static func answer(_ query: VoiceQuery, container: ModelContainer, store: LocalStore, sellerId: String) -> VoiceAnswer {
        VoiceQueryResolver(context: container.mainContext, sellerId: sellerId, router: AppRouter.shared, store: store, close: {})
            .resolve(.query(query))
    }
}
