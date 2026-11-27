import Foundation

/// Lo que el Asistente reconoce (docs/unified-assistant-proposal.md §3). La última queda activa para "¿y cuánto queda?".
public enum AssistantEntity: Equatable, Hashable, Sendable {
    case product(String)
    case customer(String)
    case cycle
    case account
    case magazine
}

public enum AssistantActionID: String, CaseIterable, Sendable {
    // Producto
    case productStock, productAddToSale, productReceive, productDetail, productWhoOrdered, productPricing
    case productSalesMonth, productOffer, productShare, productAddToDraft
    // Cliente
    case customerPending, customerLastOrder, customerNewOrder, customerPurchases, customerDetail
    case customerSendMagazine, customerWhatsApp, customerCall
    // Ciclo
    case cycleInfo, cycleWhatToOrder, cycleOrderDraft, cycleOffers, cycleMagazine
    // Cuenta
    case accountCredit, accountPayments, accountOpen
    // Revista
    case magazineOpen, magazineShare
}

/// Una acción del registro: la UI de botones, la voz y la ayuda salen de aquí (§7).
public struct AssistantAction: Equatable, Sendable, Identifiable {
    public let id: AssistantActionID
    public let title: String
    public let systemImage: String
    /// Frases (sin tildes, minúsculas) que la eligen por voz o texto.
    public let phrases: [String]
    public let requiresNetwork: Bool
    /// Cambia datos: la hoja muestra el resultado y nunca se hace "en silencio".
    public let changesData: Bool
}

/// Lo que se sabe de la entidad y del entorno para decidir qué acciones aplican.
public struct AssistantContext: Sendable, Equatable {
    public var isOnline: Bool
    public var stock: Int
    public var isSellable: Bool
    public var hasOpenReceivingLine: Bool
    public var hasPhone: Bool
    public var hasCustomerOrders: Bool
    public var hasOffer: Bool
    public var hasCycle: Bool

    public init(isOnline: Bool = true, stock: Int = 0, isSellable: Bool = true, hasOpenReceivingLine: Bool = false,
                hasPhone: Bool = false, hasCustomerOrders: Bool = false, hasOffer: Bool = false, hasCycle: Bool = false) {
        self.isOnline = isOnline
        self.stock = stock
        self.isSellable = isSellable
        self.hasOpenReceivingLine = hasOpenReceivingLine
        self.hasPhone = hasPhone
        self.hasCustomerOrders = hasCustomerOrders
        self.hasOffer = hasOffer
        self.hasCycle = hasCycle
    }
}

public enum AssistantActions {
    static func make(_ id: AssistantActionID, _ title: String, _ image: String, _ phrases: [String],
                     network: Bool = false, changes: Bool = false) -> AssistantAction {
        AssistantAction(id: id, title: title, systemImage: image, phrases: phrases, requiresNetwork: network, changesData: changes)
    }

    /// Registro (§4), en orden de prioridad dentro de cada entidad.
    public static let registry: [AssistantAction] = [
        make(.productStock, "¿Cuánto queda?", "shippingbox", ["cuanto queda", "cuantos quedan", "cuanto me queda", "stock", "cuantos hay"]),
        make(.productAddToSale, "A la venta", "cart.badge.plus", ["a la venta", "al carro", "vendelo", "venderlo", "vender"], changes: true),
        make(.productReceive, "Recibir +1", "tray.and.arrow.down", ["recibelo", "recibir", "llego", "en que pedido viene"], changes: true),
        make(.productDetail, "Ficha e inventario", "doc.text.magnifyingglass", ["ver ficha", "ficha", "inventario", "conte", "kardex", "movimientos"]),
        make(.productWhoOrdered, "¿Quién lo encargó?", "person.2", ["quien lo encargo", "quien lo pidio", "quien lo quiere", "encargos"]),
        make(.productPricing, "Costo y ganancia", "dollarsign.circle", ["a cuanto lo compre", "cuanto le gano", "costo", "precio", "margen"]),
        make(.productSalesMonth, "Ventas del mes", "chart.bar", ["cuantos vendi", "ventas del mes", "cuanto vendi"]),
        make(.productOffer, "¿Tiene oferta?", "tag", ["tiene oferta", "oferta", "puntos", "cuantos puntos"]),
        make(.productAddToDraft, "Al pedido Natura", "cart.badge.plus", ["al pedido natura", "pidelo a natura", "pedirlo", "reponer"], changes: true),
        make(.productShare, "Compartir", "square.and.arrow.up", ["compartir", "mandalo", "enviar"]),

        make(.customerPending, "Encargos pendientes", "list.bullet", ["que me encargo", "encargos", "que pidio", "pendientes"]),
        make(.customerLastOrder, "Último pedido", "doc.text", ["ultimo pedido", "trae el ultimo pedido", "su pedido", "abre su pedido"]),
        make(.customerPurchases, "¿Cuánto me ha comprado?", "clock.arrow.circlepath", ["cuanto me ha comprado", "compras", "historial"]),
        make(.customerSendMagazine, "Enviar revista", "book", ["enviale la revista", "mandale la revista", "revista"], network: true),
        make(.customerWhatsApp, "WhatsApp", "message", ["whatsapp", "escribele", "mensaje"]),
        make(.customerCall, "Llamar", "phone", ["llamala", "llamalo", "llamar"]),
        make(.customerNewOrder, "Nuevo pedido", "plus", ["nuevo pedido", "pedido nuevo"], changes: true),
        make(.customerDetail, "Ver ficha", "person.text.rectangle", ["ver ficha", "ficha", "datos"]),

        make(.cycleInfo, "¿Cuándo cierra?", "calendar", ["cuando cierra", "que ciclo", "cuantos dias"]),
        make(.cycleWhatToOrder, "¿Qué tengo que pedir?", "checklist", ["que tengo que pedir", "que pido", "que me falta"]),
        make(.cycleOrderDraft, "Armar pedido", "cart", ["arma el pedido", "armar pedido", "pedido del ciclo", "puntos"]),
        make(.cycleOffers, "Ofertas", "tag", ["ofertas", "que ofertas hay"]),
        make(.cycleMagazine, "Revista", "book", ["revista"]),

        make(.accountCredit, "Crédito", "creditcard", ["credito", "cuanto credito", "cupo"]),
        make(.accountPayments, "Pagos", "calendar.badge.exclamationmark", ["cuando vence", "pagos", "debo", "atrasos", "deuda"]),
        make(.accountOpen, "Ver cuenta", "person.text.rectangle", ["ver cuenta", "abre la cuenta", "cuenta"]),

        make(.magazineOpen, "Abrir revista", "book", ["abrir", "abre", "ver"], network: true),
        make(.magazineShare, "Compartir revista", "square.and.arrow.up", ["compartir", "enviar", "mandar"], network: true),
    ]

    public static func action(_ id: AssistantActionID) -> AssistantAction {
        registry.first { $0.id == id }!
    }

    /// Acciones que aplican a la entidad, en orden. Las 4 primeras son las principales.
    public static func available(for entity: AssistantEntity, context: AssistantContext) -> [AssistantAction] {
        let ids: [AssistantActionID]
        switch entity {
        case .product:
            var list: [AssistantActionID] = [.productStock]
            if context.isSellable && context.stock > 0 { list.append(.productAddToSale) }
            if context.hasOpenReceivingLine { list.append(.productReceive) }
            list += [.productDetail, .productWhoOrdered, .productPricing, .productSalesMonth]
            if context.hasOffer { list.insert(.productOffer, at: min(2, list.count)) }
            if context.hasCycle { list.append(.productAddToDraft) }
            list.append(.productShare)
            ids = list
        case .customer:
            var list: [AssistantActionID] = [.customerPending, .customerLastOrder]
            if context.hasPhone { list += [.customerSendMagazine, .customerWhatsApp, .customerCall] }
            list += [.customerPurchases, .customerNewOrder, .customerDetail]
            if !context.hasCustomerOrders { list.removeAll { $0 == .customerLastOrder } }
            if !context.hasCycle { list.removeAll { $0 == .customerSendMagazine } }
            ids = list
        case .cycle:
            ids = [.cycleInfo, .cycleWhatToOrder, .cycleOrderDraft, .cycleOffers, .cycleMagazine]
        case .account:
            ids = [.accountCredit, .accountPayments, .accountOpen]
        case .magazine:
            ids = context.hasCycle ? [.magazineOpen, .magazineShare] : []
        }
        return ids.map(action)
    }

    /// La acción que nombra la frase (la coincidencia más larga entre las disponibles), si hay.
    public static func match(_ utterance: String, in actions: [AssistantAction]) -> AssistantAction? {
        let text = " " + VoiceText.fold(utterance).filter { $0.isLetter || $0.isNumber || $0 == " " }
            .split(separator: " ").joined(separator: " ") + " "
        var best: (action: AssistantAction, length: Int)?
        for action in actions {
            for phrase in action.phrases where text.contains(" " + phrase + " ") {
                if phrase.count > (best?.length ?? 0) { best = (action, phrase.count) }
            }
        }
        return best?.action
    }
}

public enum AssistantResolution: Equatable, Sendable {
    case entity(AssistantEntity)
    case candidates([AssistantEntity])
    case none
}

/// Entrada (código escaneado, texto o voz) → entidad (§3).
public enum AssistantResolver {
    public static func resolve(_ input: String, products: [VoiceCandidate], customers: [VoiceCandidate],
                               barcodes: [String: String]) -> AssistantResolution {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .none }
        let digits = trimmed.filter(\.isASCIIDigit)
        if !digits.isEmpty, digits.count == trimmed.filter({ !$0.isWhitespace && $0 != "#" }).count {
            if let id = barcodes[digits] { return .entity(.product(id)) }
            if (5...7).contains(digits.count),
               let match = products.first(where: { Normalize.naturaSku($0.code ?? "") == digits }) {
                return .entity(.product(match.id))
            }
            return .none
        }
        let folded = " " + VoiceText.fold(trimmed) + " "
        if folded.contains(" revista ") { return .entity(.magazine) }
        if ["credito", "cuenta", "pagos", "vence", "debo", "deuda", "atrasos"].contains(where: { folded.contains(" " + $0 + " ") }) {
            return .entity(.account)
        }
        if folded.contains(" ciclo ") || folded.contains(" pedido natura ") || folded.contains(" que tengo que pedir ") {
            return .entity(.cycle)
        }
        let productScores = ProductMatcher.rank(.text(trimmed), in: products)
        let customerScores = CustomerMatcher.rank(name: trimmed, in: customers)
        let product = VoiceMatching.resolve(productScores)
        let customer = VoiceMatching.resolve(customerScores)
        let productTop = productScores.first?.score ?? 0
        let customerTop = customerScores.first?.score ?? 0
        switch (product, customer) {
        case (.notFound, .notFound):
            return .none
        case (_, .notFound):
            return entities(product, as: AssistantEntity.product)
        case (.notFound, _):
            return entities(customer, as: AssistantEntity.customer)
        default:
            if abs(productTop - customerTop) < VoiceMatching.ambiguityMargin {
                let all = entityList(product, as: AssistantEntity.product) + entityList(customer, as: AssistantEntity.customer)
                return .candidates(all)
            }
            return productTop > customerTop ? entities(product, as: AssistantEntity.product)
                                            : entities(customer, as: AssistantEntity.customer)
        }
    }

    static func entityList(_ match: VoiceMatch, as make: (String) -> AssistantEntity) -> [AssistantEntity] {
        switch match {
        case .found(let id): [make(id)]
        case .ambiguous(let ids): ids.map(make)
        case .notFound: []
        }
    }

    static func entities(_ match: VoiceMatch, as make: (String) -> AssistantEntity) -> AssistantResolution {
        switch match {
        case .found(let id): .entity(make(id))
        case .ambiguous(let ids): .candidates(ids.map(make))
        case .notFound: .none
        }
    }
}
