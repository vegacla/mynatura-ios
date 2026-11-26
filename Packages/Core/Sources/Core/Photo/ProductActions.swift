import Foundation

/// Línea de un pedido Natura abierto donde el producto está pendiente de recibir.
public struct ReceivingOpportunity: Equatable, Sendable {
    public let orderId: String
    public let orderNumber: String
    public let lineId: String
    public let pending: Int

    public init(orderId: String, orderNumber: String, lineId: String, pending: Int) {
        self.orderId = orderId
        self.orderNumber = orderNumber
        self.lineId = lineId
        self.pending = pending
    }
}

/// Botón de acción en la ficha del producto reconocido (docs/product-photo-proposal.md §3).
public enum ProductAction: Equatable, Sendable, Identifiable {
    case takeInventory
    case linkBarcode(String)
    case addToSale
    case addToCustomerOrder
    case receive(ReceivingOpportunity)
    case openDetail
    case createProduct(sku: String?, name: String?)

    public var id: String {
        switch self {
        case .takeInventory: "inventory"
        case .linkBarcode(let ean): "barcode-\(ean)"
        case .addToSale: "sale"
        case .addToCustomerOrder: "customer-order"
        case .receive(let opportunity): "receive-\(opportunity.lineId)"
        case .openDetail: "detail"
        case .createProduct: "create"
        }
    }
}

/// Qué se sabe del producto para decidir qué botones mostrar.
public struct ProductActionContext: Equatable, Sendable {
    public let isSellable: Bool
    public let available: Int
    /// EAN leídos en la foto que ningún producto tiene.
    public let unknownBarcodes: [String]
    public let receiving: [ReceivingOpportunity]

    public init(isSellable: Bool, available: Int, unknownBarcodes: [String], receiving: [ReceivingOpportunity]) {
        self.isSellable = isSellable
        self.available = available
        self.unknownBarcodes = unknownBarcodes
        self.receiving = receiving
    }
}

public enum ProductActions {
    /// Solo los botones que aplican, en orden de uso habitual.
    public static func available(for context: ProductActionContext) -> [ProductAction] {
        var actions: [ProductAction] = [.takeInventory]
        actions += context.unknownBarcodes.map { ProductAction.linkBarcode($0) }
        if context.isSellable, context.available > 0 { actions.append(.addToSale) }
        actions.append(.addToCustomerOrder)
        actions += context.receiving.filter { $0.pending > 0 }.map { ProductAction.receive($0) }
        actions.append(.openDetail)
        return actions
    }

    /// Sin producto reconocido: crear con lo leído (código y nombre, editables).
    public static func whenNotFound(_ result: RecognitionResult) -> [ProductAction] {
        [.createProduct(sku: result.readCodes.first, name: result.labelName)]
    }
}
