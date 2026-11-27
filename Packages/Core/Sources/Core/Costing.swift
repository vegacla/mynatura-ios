import Foundation

// Costo de inventario, salidas y ganancia (docs/local-first-migration.md §4).
// Puro: no sabe de SwiftData ni de Natura; se prueba en Linux.

/// Método de costeo: decide qué lote sale primero y qué precio conocido valoriza una unidad gratis.
/// Reemplazará a `IssueStrategy` (que hoy se sincroniza con el backend y solo admite FIFO/LIFO) en M2.
public enum CostingMethod: String, Sendable, Codable, CaseIterable {
    case fifo
    case lifo
    case highestPrice

    public init(_ strategy: IssueStrategy) {
        switch strategy {
        case .fifo: self = .fifo
        case .lifo: self = .lifo
        }
    }

    public var label: String {
        switch self {
        case .fifo: "FIFO"
        case .lifo: "LIFO"
        case .highestPrice: "Mayor precio"
        }
    }

    public var detail: String {
        switch self {
        case .fifo: "Sale primero el lote más antiguo."
        case .lifo: "Sale primero el lote más reciente."
        case .highestPrice: "Sale primero el lote de mayor costo."
        }
    }
}

/// De dónde sale el costo de un lote.
public enum CostSource: String, Sendable, Codable, CaseIterable {
    /// Comprado: línea del pedido con valor unitario > 0.
    case purchased
    /// Gratis de Natura (muestras, bolsas, otra copia de la revista…): costo 0 conocido.
    case free
    /// Ingresado a mano.
    case manual
    /// Línea pagada cuyo valor no se pudo leer: se completa a mano.
    case unknown
}

public struct InventoryLot: Equatable, Sendable, Identifiable {
    public let id: String
    public let productId: String
    public let receivedAt: Date
    public let quantity: Int
    public var remaining: Int
    /// nil solo si `source == .unknown`.
    public var unitCost: Money?
    public var source: CostSource

    public init(id: String, productId: String, receivedAt: Date, quantity: Int, remaining: Int? = nil,
                unitCost: Money?, source: CostSource) {
        self.id = id
        self.productId = productId
        self.receivedAt = receivedAt
        self.quantity = quantity
        self.remaining = remaining ?? quantity
        self.unitCost = unitCost
        self.source = source
    }

    /// Costo de compra real que sirve de referencia (comprado o manual, > 0).
    var knownPurchaseCost: Money? {
        guard source == .purchased || source == .manual, let unitCost, unitCost.pesos > 0 else { return nil }
        return unitCost
    }
}

/// Clasifica una línea de pedido Natura por su **valor unitario** (no por el "Tipo": una muestra puede comprarse).
public enum LotClassifier {
    public struct Classification: Equatable, Sendable {
        public let source: CostSource
        public let unitCost: Money?

        public init(source: CostSource, unitCost: Money?) {
            self.source = source
            self.unitCost = unitCost
        }
    }

    /// "$12.990" → comprado · "-", "$0", "0" → gratis · vacío o ilegible → desconocido.
    public static func classify(rawUnitValue: String?) -> Classification {
        let text = (rawUnitValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if text == "-" || text == "—" {
            return Classification(source: .free, unitCost: .zero)
        }
        guard let money = Money.parse(text), money.pesos >= 0 else {
            return Classification(source: .unknown, unitCost: nil)
        }
        return money.pesos == 0
            ? Classification(source: .free, unitCost: .zero)
            : Classification(source: .purchased, unitCost: money)
    }

    /// Un producto nuevo cuya primera línea llega gratis queda no vendible (se puede regalar).
    public static func isSellableByDefault(firstSource: CostSource) -> Bool {
        firstSource != .free
    }

    /// Último costo de compra: solo lotes comprados o manuales. Una unidad gratis nunca lo pisa.
    public static func lastPurchaseCost(_ lots: [InventoryLot]) -> Money? {
        lots.filter { $0.knownPurchaseCost != nil }
            .max { lhs, rhs in lhs.receivedAt != rhs.receivedAt ? lhs.receivedAt < rhs.receivedAt : lhs.id < rhs.id }?
            .knownPurchaseCost
    }
}

/// Cómo se valorizó una porción de la salida.
public enum CostBasis: String, Equatable, Hashable, Sendable, Codable {
    /// Costo del propio lote (comprado o manual).
    case lot
    /// Unidad gratis de Natura valorizada con el precio conocido del método.
    case reference
    /// Unidad gratis de un producto nunca comprado: 0 y marcado.
    case freeWithoutReference
    /// Lote con costo desconocido: pendiente; la ganancia queda incompleta.
    case pending
}

public struct CostAllocation: Equatable, Hashable, Sendable, Codable {
    public let lotId: String
    public let quantity: Int
    /// nil = pendiente.
    public let unitCost: Money?
    public let basis: CostBasis

    public init(lotId: String, quantity: Int, unitCost: Money?, basis: CostBasis) {
        self.lotId = lotId
        self.quantity = quantity
        self.unitCost = unitCost
        self.basis = basis
    }

    public var totalCost: Money? { unitCost.map { $0 * quantity } }
}

public struct CostingResult: Equatable, Sendable {
    public let allocations: [CostAllocation]
    /// Lotes con `remaining` actualizado (mismo orden que la entrada).
    public let lots: [InventoryLot]
    /// Unidades pedidas que no alcanzaron a salir por falta de stock.
    public let shortage: Int

    /// Suma de lo conocido (las porciones pendientes no suman).
    public var knownCost: Money {
        allocations.reduce(Money.zero) { $0 + ($1.totalCost ?? .zero) }
    }

    public var isComplete: Bool { !allocations.contains { $0.basis == .pending } }
}

public enum CostingEngine {
    /// Orden de consumo de los lotes con stock.
    /// Mayor precio: por costo descendente; los gratis (0) quedan al final y los desconocidos después.
    public static func consumptionOrder(_ lots: [InventoryLot], method: CostingMethod) -> [InventoryLot] {
        let available = lots.filter { $0.remaining > 0 }
        switch method {
        case .fifo:
            return available.sorted { lhs, rhs in
                lhs.receivedAt != rhs.receivedAt ? lhs.receivedAt < rhs.receivedAt : lhs.id < rhs.id
            }
        case .lifo:
            return available.sorted { lhs, rhs in
                lhs.receivedAt != rhs.receivedAt ? lhs.receivedAt > rhs.receivedAt : lhs.id > rhs.id
            }
        case .highestPrice:
            return available.sorted { lhs, rhs in
                let left = lhs.unitCost?.pesos ?? -1
                let right = rhs.unitCost?.pesos ?? -1
                if left != right { return left > right }
                return lhs.receivedAt != rhs.receivedAt ? lhs.receivedAt < rhs.receivedAt : lhs.id < rhs.id
            }
        }
    }

    /// Precio conocido que reemplaza al 0 de una unidad gratis, según el método, sobre **todo** el historial
    /// de compras del producto (también lotes agotados): FIFO → el más antiguo, LIFO → el más reciente,
    /// Mayor precio → el mayor. nil si el producto nunca se compró.
    public static func referenceCost(history: [InventoryLot], method: CostingMethod) -> Money? {
        let purchases = history.filter { $0.knownPurchaseCost != nil }
        let chronological = purchases.sorted { lhs, rhs in
            lhs.receivedAt != rhs.receivedAt ? lhs.receivedAt < rhs.receivedAt : lhs.id < rhs.id
        }
        switch method {
        case .fifo: return chronological.first?.knownPurchaseCost
        case .lifo: return chronological.last?.knownPurchaseCost
        case .highestPrice: return purchases.compactMap(\.knownPurchaseCost).max()
        }
    }

    /// Saca `quantity` unidades de los lotes (de un mismo producto) según el método y valoriza cada porción.
    public static func consume(_ quantity: Int, from lots: [InventoryLot], method: CostingMethod) -> CostingResult {
        var updated = lots
        var allocations: [CostAllocation] = []
        var pending = max(quantity, 0)
        let reference = referenceCost(history: lots, method: method)

        for lot in consumptionOrder(lots, method: method) where pending > 0 {
            guard let index = updated.firstIndex(where: { $0.id == lot.id }) else { continue }
            let taken = min(updated[index].remaining, pending)
            guard taken > 0 else { continue }
            updated[index].remaining -= taken
            pending -= taken
            allocations.append(allocation(for: lot, quantity: taken, reference: reference))
        }
        return CostingResult(allocations: allocations, lots: updated, shortage: pending)
    }

    static func allocation(for lot: InventoryLot, quantity: Int, reference: Money?) -> CostAllocation {
        switch lot.source {
        case .purchased, .manual:
            if let unitCost = lot.unitCost {
                return CostAllocation(lotId: lot.id, quantity: quantity, unitCost: unitCost, basis: .lot)
            }
            return CostAllocation(lotId: lot.id, quantity: quantity, unitCost: nil, basis: .pending)
        case .free:
            if let reference {
                return CostAllocation(lotId: lot.id, quantity: quantity, unitCost: reference, basis: .reference)
            }
            return CostAllocation(lotId: lot.id, quantity: quantity, unitCost: .zero, basis: .freeWithoutReference)
        case .unknown:
            return CostAllocation(lotId: lot.id, quantity: quantity, unitCost: nil, basis: .pending)
        }
    }

    /// Recalcula una salida ya registrada cuando se completa el costo de un lote desconocido.
    public static func revalue(_ allocations: [CostAllocation], completing lotId: String, unitCost: Money) -> [CostAllocation] {
        allocations.map { allocation in
            guard allocation.lotId == lotId, allocation.basis == .pending else { return allocation }
            return CostAllocation(lotId: lotId, quantity: allocation.quantity, unitCost: unitCost, basis: .lot)
        }
    }
}

/// Venta u obsequio a terceros.
public enum OutflowKind: String, Sendable, Codable {
    case sale
    /// Obsequio a terceros: precio 0, su costo es pérdida.
    case gift
    /// Ventas previas al uso de la app (diferencia del inventario inicial): ingreso **estimado** al precio sugerido.
    case priorSales
}

public enum OutflowError: Error, Equatable, Sendable {
    case invalidQuantity
    case negativePrice
    case insufficientStock(available: Int)

    public var message: String {
        switch self {
        case .invalidQuantity: "La cantidad debe ser mayor a cero."
        case .negativePrice: "El precio no puede ser negativo."
        case .insufficientStock(let available): "Stock insuficiente. Disponible: \(available)."
        }
    }
}

public enum OutflowRules {
    /// El precio de venta nunca es 0: una línea a precio 0 es un obsequio, no una venta.
    public static func kind(forUnitPrice price: Money) -> OutflowKind {
        price.pesos == 0 ? .gift : .sale
    }

    public static func validate(quantity: Int, unitPrice: Money, available: Int) throws(OutflowError) {
        guard quantity > 0 else { throw .invalidQuantity }
        guard unitPrice.pesos >= 0 else { throw .negativePrice }
        guard quantity <= available else { throw .insufficientStock(available: available) }
    }
}

/// Línea de salida ya registrada, con su costo congelado al momento del registro.
public struct OutflowLine: Equatable, Sendable {
    public let kind: OutflowKind
    public let productId: String
    public let quantity: Int
    /// 0 en obsequios.
    public let unitPrice: Money
    public let allocations: [CostAllocation]

    public init(kind: OutflowKind, productId: String, quantity: Int, unitPrice: Money, allocations: [CostAllocation]) {
        self.kind = kind
        self.productId = productId
        self.quantity = quantity
        self.unitPrice = kind == .gift ? .zero : unitPrice
        self.allocations = allocations
    }

    public var revenue: Money { unitPrice * quantity }
    public var knownCost: Money { allocations.reduce(Money.zero) { $0 + ($1.totalCost ?? .zero) } }
    public var hasPendingCost: Bool { allocations.contains { $0.basis == .pending } }
}

/// Ventas − costo de lo vendido − obsequios = ganancia (§4.6), con el detalle informativo.
public struct ProfitReport: Equatable, Sendable {
    public var revenue = Money.zero
    public var costOfSales = Money.zero
    public var giftLoss = Money.zero
    /// Unidades valorizadas con el precio de referencia (gratis de Natura) y cuánto suman.
    public var unitsAtReferenceCost = 0
    public var referenceCostAmount = Money.zero
    /// Unidades gratis de productos nunca comprados que salieron (costo 0).
    public var unitsWithoutKnownCost = 0
    /// Líneas con costo pendiente (lote desconocido).
    public var linesWithPendingCost = 0
    /// Ventas previas al uso de la app: aparte, no suman a la ganancia.
    public var priorSalesEstimatedRevenue = Money.zero
    public var priorSalesCost = Money.zero
    public var priorSalesUnits = 0

    public var grossMargin: Money { revenue - costOfSales }
    public var profit: Money { grossMargin - giftLoss }
    /// false si hay costos pendientes: la ganancia real puede ser menor.
    public var isComplete: Bool { linesWithPendingCost == 0 }

    public static func build(_ lines: [OutflowLine]) -> ProfitReport {
        var report = ProfitReport()
        for line in lines {
            switch line.kind {
            case .sale:
                report.revenue = report.revenue + line.revenue
                report.costOfSales = report.costOfSales + line.knownCost
            case .gift:
                report.giftLoss = report.giftLoss + line.knownCost
            case .priorSales:
                report.priorSalesEstimatedRevenue = report.priorSalesEstimatedRevenue + line.revenue
                report.priorSalesCost = report.priorSalesCost + line.knownCost
                report.priorSalesUnits += line.quantity
                continue
            }
            for allocation in line.allocations {
                switch allocation.basis {
                case .reference:
                    report.unitsAtReferenceCost += allocation.quantity
                    report.referenceCostAmount = report.referenceCostAmount + (allocation.totalCost ?? .zero)
                case .freeWithoutReference:
                    report.unitsWithoutKnownCost += allocation.quantity
                case .lot, .pending:
                    break
                }
            }
            if line.hasPendingCost { report.linesWithPendingCost += 1 }
        }
        return report
    }
}
