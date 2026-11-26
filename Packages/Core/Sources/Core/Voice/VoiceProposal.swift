import Foundation

/// Acción ya resuelta contra el catálogo y los clientes: es lo que la pantalla muestra como chip.
public enum VoiceAction: Equatable, Sendable {
    /// `.notFound` = cliente nuevo con ese nombre; `.ambiguous` = hay que elegir.
    case customer(spoken: String, match: VoiceMatch)
    /// Ciclo AAAACC.
    case cycle(Int)
    /// "ciclo actual": se mantiene el que tiene el pedido.
    case keepCycle
    case addLine(quantity: Int, reference: ProductRef, price: ParsedPrice?, match: VoiceMatch)
    case repeatLast(quantity: Int)
    case setQuantity(reference: ProductRef, quantity: Int, match: VoiceMatch)
    case removeLine(reference: ProductRef, match: VoiceMatch)
    case note(String)
    /// Recepción de una línea del pedido Natura (id de la línea en `match`).
    case receive(reference: ProductRef?, amount: ReceiveAmount, match: VoiceMatch)
    /// Conteo físico de la conciliación.
    case count(Int)
    case unrecognized(String)

    /// Se puede aplicar sin que la persona elija nada.
    public var isApplicable: Bool {
        switch self {
        case .customer(_, let match):
            if case .ambiguous = match { return false }
            return true
        case .addLine(_, _, _, let match), .setQuantity(_, _, let match), .removeLine(_, let match),
             .receive(_, _, let match):
            if case .found = match { return true }
            return false
        case .unrecognized:
            return false
        case .cycle, .keepCycle, .repeatLast, .note, .count:
            return true
        }
    }

    /// Candidatos para elegir cuando quedó ambiguo.
    public var choices: [String] {
        switch self {
        case .customer(_, .ambiguous(let ids)),
             .addLine(_, _, _, .ambiguous(let ids)),
             .setQuantity(_, _, .ambiguous(let ids)),
             .removeLine(_, .ambiguous(let ids)),
             .receive(_, _, .ambiguous(let ids)):
            return ids
        default:
            return []
        }
    }

    /// La misma acción con el candidato elegido por la persona.
    public func resolving(with id: String) -> VoiceAction {
        switch self {
        case .customer(let spoken, _):
            return .customer(spoken: spoken, match: .found(id))
        case .addLine(let quantity, let reference, let price, _):
            return .addLine(quantity: quantity, reference: reference, price: price, match: .found(id))
        case .setQuantity(let reference, let quantity, _):
            return .setQuantity(reference: reference, quantity: quantity, match: .found(id))
        case .removeLine(let reference, _):
            return .removeLine(reference: reference, match: .found(id))
        case .receive(let reference, let amount, _):
            return .receive(reference: reference, amount: amount, match: .found(id))
        default:
            return self
        }
    }
}

public struct VoiceProposalItem: Identifiable, Equatable, Sendable {
    public let id: Int
    public var action: VoiceAction

    public init(id: Int, action: VoiceAction) {
        self.id = id
        self.action = action
    }
}

/// Resultado de interpretar una frase: chips + pedidos especiales ("deshacer" sin nada antes, "listo").
public struct VoiceProposal: Equatable, Sendable {
    public var items: [VoiceProposalItem]
    /// "listo" / "eso es todo".
    public var finishRequested: Bool
    /// "deshacer" sin un chip anterior en la misma frase: deshacer lo último aplicado.
    public var undoRequested: Bool

    public init(items: [VoiceProposalItem] = [], finishRequested: Bool = false, undoRequested: Bool = false) {
        self.items = items
        self.finishRequested = finishRequested
        self.undoRequested = undoRequested
    }
}

public enum VoiceProposalBuilder {
    /// Comandos → chips, resolviendo productos y clientes. `firstId` permite acumular varias frases;
    /// `previousProductId` es el último producto (o línea) mencionado antes, para "falta uno" u "otro más".
    public static func build(_ commands: [VoiceCommand], products: [VoiceCandidate], customers: [VoiceCandidate],
                             referenceYear: Int, firstId: Int = 0, previousProductId: String? = nil) -> VoiceProposal {
        var proposal = VoiceProposal()
        var nextId = firstId
        var lastProductId = previousProductId

        func append(_ action: VoiceAction) {
            proposal.items.append(VoiceProposalItem(id: nextId, action: action))
            nextId += 1
        }

        func resolve(_ reference: ProductRef) -> VoiceMatch {
            let match = ProductMatcher.resolve(reference, in: products)
            if case .found(let id) = match { lastProductId = id }
            return match
        }

        for command in commands {
            switch command {
            case .setCustomer(let name):
                append(.customer(spoken: name, match: CustomerMatcher.resolve(name: name, in: customers)))
            case .setCycle(.current):
                append(.keepCycle)
            case .setCycle(.number(let spoken)):
                if let code = cycleCode(spoken, referenceYear: referenceYear) {
                    append(.cycle(code))
                } else {
                    append(.unrecognized("ciclo \(spoken)"))
                }
            case .addLine(let quantity, let reference, let price):
                append(.addLine(quantity: quantity, reference: reference, price: price, match: resolve(reference)))
            case .repeatLast(let quantity):
                append(.repeatLast(quantity: quantity))
            case .setQuantity(let reference, let quantity):
                append(.setQuantity(reference: reference, quantity: quantity, match: resolve(reference)))
            case .removeLine(let reference):
                append(.removeLine(reference: reference, match: resolve(reference)))
            case .receive(let reference, let amount):
                let match: VoiceMatch
                if let reference {
                    match = resolve(reference)
                } else {
                    match = lastProductId.map { VoiceMatch.found($0) } ?? .notFound
                }
                append(.receive(reference: reference, amount: amount, match: match))
            case .physicalCount(let counted):
                append(.count(counted))
            case .query:
                // Las consultas no son chips: las responde la pantalla de consultas.
                continue
            case .note(let text):
                append(.note(text))
            case .undo:
                if proposal.items.isEmpty {
                    proposal.undoRequested = true
                } else {
                    proposal.items.removeLast()
                }
            case .done:
                proposal.finishRequested = true
            case .unrecognized(let text):
                append(.unrecognized(text))
            }
        }
        return proposal
    }

    /// "202619" → 202619; "19" con año de referencia 2026 → 202619.
    public static func cycleCode(_ spoken: Int, referenceYear: Int) -> Int? {
        if CycleCode.parse(String(spoken)) != nil { return spoken }
        if (1...99).contains(spoken), (2000...2099).contains(referenceYear) {
            return referenceYear * 100 + spoken
        }
        return nil
    }
}

/// Estado del editor de pedido de cliente, sin SwiftUI ni SwiftData, para aplicar chips y probarlo.
public struct VoiceOrderState: Equatable, Sendable {
    public struct Line: Equatable, Sendable {
        public var productId: String
        public var quantity: Int
        public var finalPesos: Int?

        public init(productId: String, quantity: Int, finalPesos: Int? = nil) {
            self.productId = productId
            self.quantity = quantity
            self.finalPesos = finalPesos
        }
    }

    public var customerId: String?
    public var customerName: String
    public var cycle: Int?
    public var note: String
    public var lines: [Line]

    public init(customerId: String? = nil, customerName: String = "", cycle: Int? = nil, note: String = "", lines: [Line] = []) {
        self.customerId = customerId
        self.customerName = customerName
        self.cycle = cycle
        self.note = note
        self.lines = lines
    }
}

public struct VoiceApplyResult: Equatable, Sendable {
    public var state: VoiceOrderState
    public var applied: Int
    public var skipped: Int
    /// Cantidades ajustadas al stock disponible (solo con `limits`).
    public var capped: Int = 0
    /// Productos sin stock que se omitieron (solo con `limits`).
    public var outOfStock: Int = 0
}

public enum VoiceOrderApplier {
    /// Mismo tope que el stepper del editor.
    public static let maximumQuantity = 999

    /// - Parameters:
    ///   - limits: stock disponible por producto (carro de venta). Sin stock ⇒ se omite; más que el stock ⇒ se ajusta.
    ///   - allowsNewCustomer: el pedido de cliente crea clientes nuevos; el carro solo usa clientes existentes.
    public static func apply(_ items: [VoiceProposalItem], to initial: VoiceOrderState, customers: [VoiceCandidate],
                             limits: [String: Int]? = nil, allowsNewCustomer: Bool = true) -> VoiceApplyResult {
        var state = initial
        var applied = 0
        var skipped = 0
        var capped = 0
        var outOfStock = 0
        var lastProductId = initial.lines.last?.productId

        func limit(_ productId: String) -> Int {
            guard let limits else { return maximumQuantity }
            return min(limits[productId] ?? 0, maximumQuantity)
        }

        /// Deja la línea en `quantity` respetando el límite; false si el producto no tiene stock.
        func setLine(_ productId: String, quantity: Int, finalPesos: Int?) -> Bool {
            let maximum = limit(productId)
            guard maximum > 0 else {
                outOfStock += 1
                return false
            }
            if quantity > maximum { capped += 1 }
            let value = min(quantity, maximum)
            if let index = state.lines.firstIndex(where: { $0.productId == productId }) {
                state.lines[index].quantity = value
                if let finalPesos { state.lines[index].finalPesos = finalPesos }
            } else {
                state.lines.append(VoiceOrderState.Line(productId: productId, quantity: value, finalPesos: finalPesos))
            }
            return true
        }

        func currentQuantity(_ productId: String) -> Int {
            state.lines.first { $0.productId == productId }?.quantity ?? 0
        }

        for item in items {
            guard item.action.isApplicable else {
                skipped += 1
                continue
            }
            switch item.action {
            case .customer(let spoken, let match):
                if case .notFound = match, !allowsNewCustomer {
                    skipped += 1
                    continue
                }
                if case .found(let id) = match {
                    state.customerId = id
                    state.customerName = customers.first { $0.id == id }?.name ?? spoken
                } else {
                    state.customerId = nil
                    state.customerName = spoken
                }
            case .cycle(let code):
                state.cycle = code
            case .keepCycle:
                break
            case .addLine(let quantity, _, let price, .found(let id)):
                lastProductId = id
                guard setLine(id, quantity: currentQuantity(id) + quantity, finalPesos: price?.amount.pesos) else {
                    skipped += 1
                    continue
                }
            case .repeatLast(let quantity):
                guard let id = lastProductId, state.lines.contains(where: { $0.productId == id }),
                      setLine(id, quantity: currentQuantity(id) + quantity, finalPesos: nil) else {
                    skipped += 1
                    continue
                }
            case .setQuantity(_, let quantity, .found(let id)):
                lastProductId = id
                if quantity == 0 {
                    state.lines.removeAll { $0.productId == id }
                } else if !setLine(id, quantity: quantity, finalPesos: nil) {
                    skipped += 1
                    continue
                }
            case .removeLine(_, .found(let id)):
                guard state.lines.contains(where: { $0.productId == id }) else {
                    skipped += 1
                    continue
                }
                state.lines.removeAll { $0.productId == id }
            case .note(let text):
                state.note = state.note.isEmpty ? text : state.note + "\n" + text
            default:
                skipped += 1
                continue
            }
            applied += 1
        }
        return VoiceApplyResult(state: state, applied: applied, skipped: skipped, capped: capped, outOfStock: outOfStock)
    }
}

/// Línea de un pedido Natura para aplicar la recepción dictada.
public struct VoiceReceivingLine: Equatable, Sendable {
    public let id: String
    public let ordered: Int
    public var received: Int

    public init(id: String, ordered: Int, received: Int) {
        self.id = id
        self.ordered = ordered
        self.received = received
    }
}

public struct VoiceReceivingResult: Equatable, Sendable {
    public var lines: [VoiceReceivingLine]
    public var applied: Int
    public var skipped: Int
    /// Cantidades dichas que superaban lo pedido y se ajustaron al máximo.
    public var capped: Int
}

public enum VoiceReceivingApplier {
    /// Cantidad recibida resultante, sin pasar de lo pedido.
    public static func target(_ amount: ReceiveAmount, ordered: Int, received: Int) -> (quantity: Int, capped: Bool) {
        switch amount {
        case .received(let quantity):
            return (min(max(quantity, 0), ordered), quantity > ordered)
        case .missing(let missing):
            return (max(ordered - missing, 0), missing > ordered)
        case .complete:
            return (ordered, false)
        case .increment(let extra):
            return (min(received + extra, ordered), received + extra > ordered)
        }
    }

    public static func apply(_ items: [VoiceProposalItem], to lines: [VoiceReceivingLine]) -> VoiceReceivingResult {
        var result = VoiceReceivingResult(lines: lines, applied: 0, skipped: 0, capped: 0)
        for item in items {
            guard case .receive(_, let amount, .found(let id)) = item.action,
                  let index = result.lines.firstIndex(where: { $0.id == id }) else {
                result.skipped += 1
                continue
            }
            let line = result.lines[index]
            let outcome = target(amount, ordered: line.ordered, received: line.received)
            result.lines[index].received = outcome.quantity
            result.applied += 1
            if outcome.capped { result.capped += 1 }
        }
        return result
    }
}

/// Palabras que el reconocedor debe esperar: líneas Natura, clientes y productos del catálogo.
public enum VoiceVocabulary {
    public static let naturaLines = [
        "Natura", "Ekos", "Kaiak", "Chronos", "Tododia", "Una", "Humor", "Essencial", "Luna", "Kriska",
        "Homem", "Biografia", "Mamãe e Bebê", "Faces", "Lumina", "Plant", "Águas", "Sève",
    ]

    /// Sin repetidos (ignorando mayúsculas y tildes) y con tope, en este orden: líneas, clientes, productos.
    public static func contextualStrings(productNames: [String], customerNames: [String], limit: Int = 100) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for candidate in naturaLines + customerNames + productNames {
            guard result.count < limit else { break }
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = Normalize.customerName(trimmed)
            guard !key.isEmpty, seen.insert(key).inserted else { continue }
            result.append(trimmed)
        }
        return result
    }
}
