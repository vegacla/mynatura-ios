import Foundation

/// A dónde llevar con la voz (docs/voice-interaction-proposal.md §3, caso 7): "ir a recepción", "abre el pedido de María".
public enum VoiceDestination: Equatable, Sendable {
    case sell
    case products
    case receiving
    case customers
    case settings
    case profit
    case salesHistory
    case magazine
    case orderDraft
    case offers
    case account
    /// El pedido más reciente de ese cliente.
    case customerOrder(name: String)

    /// Para la respuesta: "Abriendo Recepción".
    public var label: String {
        switch self {
        case .sell: "Vender"
        case .products: "Productos"
        case .receiving: "Recepción"
        case .customers: "Clientes"
        case .settings: "Ajustes"
        case .profit: "Ganancias"
        case .salesHistory: "el historial de ventas"
        case .magazine: "la revista del ciclo"
        case .orderDraft: "el pedido del ciclo"
        case .offers: "las ofertas del ciclo"
        case .account: "tu cuenta Natura"
        case .customerOrder(let name): "el pedido de \(name)"
        }
    }
}

public enum VoiceNavigation {
    static let verbs: Set<String> = [
        "ir", "ve", "vamos", "anda", "abre", "abrir", "abreme", "muestra", "muestrame", "mostrar", "llevame", "lleva",
        "ver", "quiero", "pasa", "cambia",
    ]
    static let fillers: Set<String> = ["a", "al", "la", "el", "los", "las", "mi", "mis", "de", "del", "ver", "pantalla", "pestana", "por", "favor"]

    /// Solo si la frase empieza con un verbo de navegación ("abre…", "ir a…", "muéstrame…").
    public static func destination(_ words: [String]) -> VoiceDestination? {
        guard let first = words.first, verbs.contains(first) else { return nil }
        let rest = Array(words.dropFirst()).filter { !fillers.contains($0) || $0 == "de" }
        let texts = Set(rest)

        // "abre el pedido de María" / "el encargo de Juan"
        if let index = rest.firstIndex(where: { $0 == "pedido" || $0 == "encargo" }),
           index + 2 <= rest.count, rest.dropFirst(index + 1).first == "de" {
            let name = rest.dropFirst(index + 2).filter { !fillers.contains($0) }.joined(separator: " ")
            if !name.isEmpty, !["natura", "ciclo"].contains(name) { return .customerOrder(name: name) }
        }
        if texts.contains("revista") || texts.contains("catalogo") && texts.contains("ciclo") { return .magazine }
        if texts.contains("ofertas") || texts.contains("oferta") { return .offers }
        if texts.contains("ganancias") || texts.contains("ganancia") || texts.contains("margen") { return .profit }
        if texts.contains("historial") || texts.contains("ventas") { return .salesHistory }
        if texts.contains("cuenta") || texts.contains("credito") || texts.contains("pagos") { return .account }
        if texts.contains("pedido") && (texts.contains("natura") || texts.contains("armar") || texts.contains("ciclo")) { return .orderDraft }
        if texts.contains("recepcion") || texts.contains("recibir") { return .receiving }
        if texts.contains("clientes") || texts.contains("cliente") || texts.contains("encargos") || texts.contains("pedidos") { return .customers }
        if texts.contains("productos") || texts.contains("catalogo") || texts.contains("inventario") || texts.contains("stock") { return .products }
        if texts.contains("ajustes") || texts.contains("configuracion") || texts.contains("respaldo") { return .settings }
        if texts.contains("vender") || texts.contains("venta") || texts.contains("carro") || texts.contains("caja") { return .sell }
        return nil
    }
}

/// Registro local y opcional de frases que la app no entendió (para mejorar la gramática). Nunca sale del iPhone.
public enum UnrecognizedPhrases {
    public static let capacity = 50

    public struct Entry: Codable, Equatable, Sendable {
        public let text: String
        public let date: Date

        public init(text: String, date: Date) {
            self.text = text
            self.date = date
        }
    }

    /// Agrega al inicio, sin repetir la misma frase seguida, y conserva las `capacity` más recientes.
    public static func appending(_ text: String, to entries: [Entry], date: Date) -> [Entry] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return entries }
        if entries.first?.text == trimmed { return entries }
        return Array(([Entry(text: trimmed, date: date)] + entries).prefix(capacity))
    }
}
