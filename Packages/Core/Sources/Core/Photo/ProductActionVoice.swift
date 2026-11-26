import Foundation

/// Lo que se pide por voz en la ficha de un producto reconocido por foto (P3).
/// Solo elige o prepara el botón: la acción se ejecuta con un toque.
public enum ProductActionIntent: Equatable, Sendable {
    /// "conté siete" (con conteo) o "tomar inventario".
    case inventory(count: Int?)
    case addToSale
    case addToCustomerOrder
    case linkBarcode
    case receive
    case openDetail
}

public enum ProductActionVoice {
    static let linkWords: Set<String> = ["asocia", "asociar", "asocialo", "ean", "barras", "vincula", "vincular"]
    static let receiveWords: Set<String> = ["recibir", "recibe", "recibelo", "recibido", "llego", "llegaron", "recepcion"]
    static let saleWords: Set<String> = ["venta", "vender", "vende", "vendelo", "carro", "cobrar"]
    static let orderWords: Set<String> = ["pedido", "encargo", "encargar", "cliente", "clienta"]
    static let detailWords: Set<String> = ["ficha", "kardex", "detalle", "historial", "movimientos"]
    static let inventoryWords: Set<String> = ["inventario", "conteo", "contar", "conciliar", "conciliacion", "conte", "cuento"]

    public static func intent(for utterance: String) -> ProductActionIntent? {
        for command in CommandGrammar.interpret(utterance, context: .reconciliation) {
            if case .physicalCount(let count) = command { return .inventory(count: count) }
        }
        let words = Set(VoiceText.tokenize(utterance).filter { !$0.isSeparator }.map(\.text))
        if !words.isDisjoint(with: linkWords) { return .linkBarcode }
        if !words.isDisjoint(with: receiveWords) { return .receive }
        if !words.isDisjoint(with: saleWords) { return .addToSale }
        if !words.isDisjoint(with: orderWords) { return .addToCustomerOrder }
        if !words.isDisjoint(with: detailWords) { return .openDetail }
        if !words.isDisjoint(with: inventoryWords) { return .inventory(count: nil) }
        return nil
    }

    /// El botón de la ficha que corresponde a la intención, si está disponible.
    public static func action(for intent: ProductActionIntent, in actions: [ProductAction]) -> ProductAction? {
        actions.first { action in
            switch (intent, action) {
            case (.inventory, .takeInventory), (.addToSale, .addToSale), (.addToCustomerOrder, .addToCustomerOrder),
                 (.linkBarcode, .linkBarcode), (.receive, .receive), (.openDetail, .openDetail):
                return true
            default:
                return false
            }
        }
    }
}
