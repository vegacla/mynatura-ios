import Core
import Foundation
import Persistence
import SwiftData

/// Operaciones sobre el carro persistido (§4.3).
@MainActor
enum Cart {
    static func draft(sellerId: String, context: ModelContext) -> CartDraft {
        let descriptor = FetchDescriptor<CartDraft>(predicate: #Predicate { $0.sellerId == sellerId })
        if let draft = try? context.fetch(descriptor).first { return draft }
        let draft = CartDraft(sellerId: sellerId)
        context.insert(draft)
        return draft
    }

    /// Agrega 1 unidad (máx. = stock operativo). Devuelve false si no hay stock disponible.
    @discardableResult
    static func add(_ product: CatalogProduct, available: Int, sellerId: String, context: ModelContext) -> Bool {
        let key = CartDraftLine.key(sellerId: sellerId, productId: product.id)
        let descriptor = FetchDescriptor<CartDraftLine>(predicate: #Predicate { $0.key == key })
        if let line = try? context.fetch(descriptor).first {
            guard line.quantity < available else { return false }
            line.quantity += 1
        } else {
            guard available > 0 else { return false }
            context.insert(CartDraftLine(sellerId: sellerId, productId: product.id, quantity: 1,
                                         finalPricePesos: product.lastSuggestedSalePesos ?? product.lastPurchasePesos))
        }
        try? context.save()
        return true
    }

    static func clear(sellerId: String, context: ModelContext) {
        let lines = (try? context.fetch(FetchDescriptor<CartDraftLine>(predicate: #Predicate { $0.sellerId == sellerId }))) ?? []
        for line in lines { context.delete(line) }
        let draft = draft(sellerId: sellerId, context: context)
        draft.note = ""
        draft.customerId = nil
        draft.customerName = nil
        draft.sourceOrderId = nil
        try? context.save()
    }

    /// Convierte un pedido de cliente en carro (etapa 10).
    static func load(order: CustomerOrder, sellerId: String, context: ModelContext) {
        clear(sellerId: sellerId, context: context)
        for line in order.lines ?? [] {
            let price = line.finalPesos ?? line.suggestedPesos ?? 0
            context.insert(CartDraftLine(sellerId: sellerId, productId: line.sellerProductId,
                                         quantity: max(line.quantity, 1), finalPricePesos: price))
        }
        let draft = draft(sellerId: sellerId, context: context)
        draft.customerId = order.customerId
        draft.customerName = order.customerDisplayName
        draft.sourceOrderId = order.id
        draft.note = "Pedido \(CycleCode.label(order.cycle))"
        try? context.save()
    }
}
