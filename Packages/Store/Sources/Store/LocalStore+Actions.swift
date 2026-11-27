import Core
import Foundation
import Persistence
import SwiftData

/// Error de una acción local, con mensaje listo para la UI.
public struct ActionError: Error, Equatable, Sendable {
    public let message: String
    /// Natura rechazó las credenciales: la contraseña guardada ya no sirve.
    public let isCredentialError: Bool

    public init(_ message: String, isCredentialError: Bool = false) {
        self.message = message
        self.isCredentialError = isCredentialError
    }
}

/// Línea del carro al registrar una venta.
public struct SaleDraftLine: Sendable, Equatable {
    public let productId: String
    public let quantity: Int
    public let finalPrice: Money
    public let reasonCode: String?
    public let reasonNote: String?

    public init(productId: String, quantity: Int, finalPrice: Money, reasonCode: String?, reasonNote: String?) {
        self.productId = productId
        self.quantity = quantity
        self.finalPrice = finalPrice
        self.reasonCode = reasonCode
        self.reasonNote = reasonNote
    }
}

public enum ScanOutcome: Equatable, Sendable {
    case matched(productName: String, received: Int, ordered: Int)
    case failed(String)
}

private func trimmedOrNil(_ text: String?) -> String? {
    guard let value = text?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
    return value
}

extension LocalStore {
    func pricingReason(code: String?) -> PricingReason? {
        guard let code else { return nil }
        return fetchAll(FetchDescriptor<PricingReasonRecord>(predicate: #Predicate { $0.code == code })).first?.reason
    }

    // MARK: - Venta y obsequio (local, M2)

    /// Registra la venta en el iPhone: consume lotes según el método de costeo y guarda el costo de cada línea.
    /// Las líneas a precio 0 (motivo Regalo) se guardan aparte como **obsequio a terceros** (pérdida, sin ingreso).
    public func registerSale(sellerId: String, lines: [SaleDraftLine], note: String?,
                             customerId: String?, customerName: String?, onCredit: Bool = false) -> Result<String, ActionError> {
        guard !lines.isEmpty else { return .failure(ActionError("Agrega al menos un producto.")) }
        if onCredit, customerId == nil {
            return .failure(ActionError("Para dejar la venta por cobrar, elige el cliente."))
        }

        var requested: [String: Int] = [:]
        for line in lines { requested[line.productId, default: 0] += line.quantity }

        // Validar todo antes de tocar el inventario.
        for line in lines {
            guard let product = product(id: line.productId) else {
                return .failure(ActionError("Uno de los productos ya no existe en el catálogo."))
            }
            let available = availableStock(productId: line.productId)
            let reason = pricingReason(code: line.reasonCode)
            let isGift = OutflowRules.kind(forUnitPrice: line.finalPrice) == .gift
            do throws(SaleLineError) {
                try CartRules.validateLine(quantity: line.quantity, finalPrice: line.finalPrice,
                                           suggested: product.lastSuggestedSale, reason: reason,
                                           isSellable: product.isSellable || isGift, available: available)
                if let total = requested[line.productId], total > available {
                    throw .insufficientStock(available: available)
                }
            } catch {
                return .failure(ActionError("\(product.name): \(error.message)"))
            }
        }

        let occurredAt = Date()
        let cleanNote = trimmedOrNil(note)
        var saleLines: [SaleLineSnapshot] = []
        var giftLines: [SaleLineSnapshot] = []
        for line in lines {
            guard let product = product(id: line.productId) else { continue }
            let reason = pricingReason(code: line.reasonCode)
            let costing = consumeLots(sellerId: sellerId, productId: product.id, quantity: line.quantity)
            let snapshot = SaleLineSnapshot(
                sellerProductId: product.id, productName: product.name, naturaSku: product.naturaSku,
                quantity: line.quantity, suggestedPesos: product.lastSuggestedSalePesos, finalPesos: line.finalPrice.pesos,
                reasonCode: reason?.code, reasonNote: reason == nil ? nil : trimmedOrNil(line.reasonNote),
                costUnitPesos: Self.unitCost(of: costing.allocations, quantity: line.quantity),
                costAllocations: costing.allocations)
            let isGift = OutflowRules.kind(forUnitPrice: line.finalPrice) == .gift
            if isGift { giftLines.append(snapshot) } else { saleLines.append(snapshot) }
            addEvent(sellerId: sellerId, productId: product.id, kind: isGift ? .gift : .sale, quantity: -line.quantity,
                     note: cleanNote ?? (isGift ? "Obsequio" : "Venta"))
        }

        var firstId: String?
        for (kind, documentLines) in [(OutflowKind.sale, saleLines), (OutflowKind.gift, giftLines)] where !documentLines.isEmpty {
            let id = UUID().uuidString.lowercased()
            let sale = LocalSale(id: id, sellerId: sellerId, occurredAt: occurredAt, note: cleanNote,
                                 customerId: customerId, customerName: customerName, lines: documentLines,
                                 syncState: .synced, kind: kind)
            sale.onCredit = onCredit && kind == .sale
            context.insert(sale)
            if firstId == nil { firstId = id }
        }
        save()
        return .success(firstId ?? "")
    }


    // MARK: - Inventario (local, M2)

    /// Conciliación física: el conteo pasa a ser el stock. Si sobra, entra un lote (al último costo conocido);
    /// si falta, se sacan unidades según el método de costeo (merma).
    @discardableResult
    public func createReconciliation(sellerId: String, productId: String, counted: Int, note: String?) -> ActionError? {
        guard counted >= 0 else { return ActionError("El conteo no puede ser negativo.") }
        let current = availableStock(productId: productId)
        let delta = counted - current
        if delta > 0 {
            let lastCost = product(id: productId)?.lastPurchasePesos ?? 0
            addLot(sellerId: sellerId, productId: productId, quantity: delta,
                   unitCost: lastCost > 0 ? Money(pesos: lastCost) : nil, source: lastCost > 0 ? .manual : .unknown,
                   origin: .reconciliation, note: trimmedOrNil(note) ?? "Conteo físico: \(counted)")
        } else if delta < 0 {
            _ = consumeLots(sellerId: sellerId, productId: productId, quantity: -delta)
        } else {
            refreshStock(productId: productId, sellerId: sellerId)
        }
        stockItem(productId: productId)?.lastReconciledAt = .now
        addEvent(sellerId: sellerId, productId: productId, kind: .reconciliation, quantity: delta,
                 note: trimmedOrNil(note) ?? "Conteo físico: \(counted)")
        save()
        return nil
    }

    /// Asocia un EAN al producto. Error claro si ya pertenece a otro (§4.5).
    public func addBarcode(sellerId: String, productId: String, ean rawEAN: String) -> ActionError? {
        guard let ean = BarcodeRules.normalized(rawEAN) else {
            return ActionError("El EAN debe tener al menos \(BarcodeRules.minimumLength) dígitos.")
        }
        guard let product = product(id: productId) else { return ActionError("Producto no encontrado.") }
        if product.barcodes.contains(ean) { return ActionError("Ese EAN ya está asociado a este producto.") }
        let products = fetchAll(FetchDescriptor<CatalogProduct>(predicate: #Predicate { $0.sellerId == sellerId }))
        if let owner = products.first(where: { $0.id != productId && $0.barcodes.contains(ean) }) {
            return ActionError("El EAN \(ean) ya pertenece a \(owner.name).")
        }
        product.barcodes.append(ean)
        save()
        return nil
    }

    /// Creación rápida SKU + nombre; reutiliza el producto si el SKU ya existe (§4.7).
    public func quickCreateProduct(sellerId: String, sku rawSKU: String, name rawName: String) -> Result<String, ActionError> {
        let sku = Normalize.naturaSku(rawSKU)
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sku.isEmpty else { return .failure(ActionError("Ingresa el SKU.")) }
        if let existing = product(sku: sku, sellerId: sellerId) { return .success(existing.id) }
        guard !name.isEmpty else { return .failure(ActionError("Ingresa el nombre del producto.")) }
        let localId = LocalID.make()
        context.insert(CatalogProduct(id: localId, sellerId: sellerId, naturaSku: sku, name: name, source: .manual,
                                      isSellable: true, lastPurchasePesos: 0, lastSuggestedSalePesos: nil,
                                      barcodes: [], syncState: .synced))
        save()
        return .success(localId)
    }

    /// Autocompletado del nombre desde el catálogo local (pedidos y catálogo del ciclo).
    public func lookupMasterProductName(sku: String) async -> String? {
        let normalized = Normalize.naturaSku(sku).lowercased()
        guard !normalized.isEmpty else { return nil }
        return fetchAll(FetchDescriptor<CatalogProduct>()).first { Normalize.naturaSku($0.naturaSku).lowercased() == normalized }?.name
    }

    // MARK: - Recepción (etapa 6)

    /// Confirma la cantidad recibida (y precio de venta) de una línea. Lo recibido entra como lote de esa línea,
    /// clasificado por su valor unitario (sin valor o 0 ⇒ gratis de Natura, costo 0).
    @discardableResult
    public func confirmReceivingLine(sellerId: String, lineId: String, quantity: Int, suggestedPesos: Int?) -> ActionError? {
        guard let line = naturaLine(id: lineId) else { return ActionError("Línea no encontrada.") }
        let orderId = line.orderId
        guard let order = fetchAll(FetchDescriptor<NaturaOrder>(predicate: #Predicate { $0.id == orderId })).first else {
            return ActionError("Pedido no encontrado.")
        }
        guard !order.isClosed else { return ActionError("El pedido está cerrado. Reábrelo para editar la recepción.") }
        guard quantity >= 0, quantity <= line.quantity else {
            return ActionError("La cantidad debe estar entre 0 y \(line.quantity).")
        }
        let delta = quantity - line.receivedQuantity
        line.receivedQuantity = quantity
        line.suggestedPesos = suggestedPesos
        line.receivedConfirmedAt = .now
        line.syncState = .synced
        recomputeTotals(order)

        if let product = product(sku: line.naturaSku, sellerId: sellerId) {
            if let suggestedPesos, suggestedPesos > 0 { product.lastSuggestedSalePesos = suggestedPesos }
            if delta > 0 {
                let lineLot = lotRecords(productId: product.id).first { $0.naturaOrderLineId == lineId }
                if let lineLot {
                    lineLot.quantity += delta
                    lineLot.remaining += delta
                    refreshStock(productId: product.id, sellerId: sellerId)
                } else {
                    let classification = lotClassification(for: line)
                    addLot(sellerId: sellerId, productId: product.id, quantity: delta, unitCost: classification.unitCost,
                           source: classification.source, origin: .naturaLine, naturaOrderLineId: lineId,
                           note: "Pedido \(order.orderNumber)", receivedAt: order.deliveredAt ?? .now,
                           suggestedPesos: line.suggestedPesos ?? suggestedPesos)
                }
            } else if delta < 0 {
                // Primero se descuenta del lote de esta línea; lo que falte, según el método.
                var toRemove = -delta
                if let lineLot = lotRecords(productId: product.id).first(where: { $0.naturaOrderLineId == lineId }) {
                    let taken = min(lineLot.remaining, toRemove)
                    lineLot.remaining -= taken
                    lineLot.quantity = max(lineLot.quantity - taken, 0)
                    toRemove -= taken
                }
                if toRemove > 0 { _ = consumeLots(sellerId: sellerId, productId: product.id, quantity: toRemove) }
                refreshStock(productId: product.id, sellerId: sellerId)
            }
            if delta != 0 {
                addEvent(sellerId: sellerId, productId: product.id, kind: .receipt, quantity: delta,
                         note: "Pedido \(order.orderNumber)")
            }
        }
        save()
        return nil
    }

    /// Recepción por código: suma 1 a la línea cuyo SKU o EAN coincide (§5.5).
    public func scanReceiving(sellerId: String, orderId: String, code: String) -> ScanOutcome {
        let orderLines = lines(orderId: orderId)
        let match: ReceivingLineRef
        do throws(ReceivingScanError) {
            match = try ReceivingScan.match(code: code, lines: orderLines.map(\.scanRef))
        } catch {
            return .failed(error.message)
        }
        guard let line = orderLines.first(where: { $0.id == match.id }) else { return .failed("Línea no encontrada.") }
        guard line.receivedQuantity < line.quantity else {
            return .failed("Ya se recibió todo de \(line.productName) (\(line.quantity)).")
        }
        if let error = confirmReceivingLine(sellerId: sellerId, lineId: line.id, quantity: line.receivedQuantity + 1,
                                            suggestedPesos: line.suggestedPesos) {
            return .failed(error.message)
        }
        return .matched(productName: line.productName, received: line.receivedQuantity, ordered: line.quantity)
    }

    /// "Aplicar faltantes al stock": una conciliación por línea con faltante (§4.6).
    public func applyShortages(sellerId: String, orderId: String) -> Result<Int, ActionError> {
        guard let order = fetchAll(FetchDescriptor<NaturaOrder>(predicate: #Predicate { $0.id == orderId })).first else {
            return .failure(ActionError("Pedido no encontrado."))
        }
        var applied = 0
        for line in lines(orderId: orderId) where line.shortage > 0 {
            guard let product = product(sku: line.naturaSku, sellerId: sellerId) else { continue }
            let operational = stockItem(productId: product.id)?.operationalQuantity ?? 0
            let counted = ReceivingRules.suggestedCount(operationalStock: operational, shortage: line.shortage)
            createReconciliation(sellerId: sellerId, productId: product.id, counted: counted,
                                 note: ReceivingRules.shortageNote(orderNumber: order.orderNumber, units: line.shortage))
            applied += 1
        }
        return .success(applied)
    }

    /// Cerrar / reabrir la recepción de un pedido (local, sin conexión).
    public func setReceivingClosed(sellerId: String, orderId: String, closed: Bool) async -> ActionError? {
        guard let order = fetchAll(FetchDescriptor<NaturaOrder>(predicate: #Predicate { $0.id == orderId })).first else {
            return ActionError("Pedido no encontrado.")
        }
        order.reviewStatus = closed ? .closed : .draft
        order.receivingClosedAt = closed ? .now : nil
        save()
        return nil
    }


    // MARK: - Natura (directo, M3)

    /// Compatibilidad con la pantalla anterior: importa directo desde Natura.
    public func importNaturaOrders(sellerId: String, customerCode: String, password: String) async -> Result<String, ActionError> {
        await importFromNatura(sellerId: sellerId, customerCode: customerCode, password: password) { _ in }
    }

        // MARK: - Clientes (etapa 8)

    /// Crea o edita un cliente en el iPhone. Devuelve su id.
    public func saveCustomer(sellerId: String, customerId: String?, name: String, rut: String?, phone: String?,
                             notes: String?) -> Result<String, ActionError> {
        let displayName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard CustomerRules.isValidName(displayName) else { return .failure(ActionError("Ingresa el nombre del cliente.")) }

        if let customerId,
           let customer = fetchAll(FetchDescriptor<Customer>(predicate: #Predicate { $0.id == customerId })).first {
            customer.rename(displayName)
            customer.rut = trimmedOrNil(rut)
            customer.phone = trimmedOrNil(phone)
            customer.notes = trimmedOrNil(notes)
            customer.updatedAt = .now
            save()
            return .success(customerId)
        }

        let localId = LocalID.make()
        context.insert(Customer(id: localId, sellerId: sellerId, displayName: displayName, rut: trimmedOrNil(rut),
                                phone: trimmedOrNil(phone), notes: trimmedOrNil(notes), syncState: .synced))
        save()
        return .success(localId)
    }

    /// Crea o edita un pedido de cliente en el iPhone (§4.7). Un cliente nuevo se crea primero.
    public func saveCustomerOrder(sellerId: String, orderId: String?, customerId: String?, newCustomerName: String?,
                                  cycle: Int, status: CustomerOrderStatus, note: String?,
                                  lines: [CustomerOrderLineSnapshot]) -> Result<String, ActionError> {
        guard CycleCode.parse(String(cycle)) != nil else {
            return .failure(ActionError("El ciclo debe tener formato AAAACC, por ejemplo 202606."))
        }
        guard !lines.isEmpty else { return .failure(ActionError("Agrega al menos un producto.")) }
        guard lines.allSatisfy({ $0.quantity > 0 }) else { return .failure(ActionError("Las cantidades deben ser mayores a cero.")) }

        var resolvedCustomerId = customerId
        if resolvedCustomerId == nil {
            guard let name = trimmedOrNil(newCustomerName) else { return .failure(ActionError("Ingresa el nombre del cliente.")) }
            switch saveCustomer(sellerId: sellerId, customerId: nil, name: name, rut: nil, phone: nil, notes: nil) {
            case .success(let id): resolvedCustomerId = id
            case .failure(let error): return .failure(error)
            }
        }
        guard let customerKey = resolvedCustomerId,
              let customer = fetchAll(FetchDescriptor<Customer>(predicate: #Predicate { $0.id == customerKey })).first
        else { return .failure(ActionError("Cliente no encontrado.")) }

        let existing: CustomerOrder? = orderId.flatMap { id in
            fetchAll(FetchDescriptor<CustomerOrder>(predicate: #Predicate { $0.id == id })).first
        }
        let order = existing ?? {
            let created = CustomerOrder(id: LocalID.make(), sellerId: sellerId, customerId: customer.id,
                                        customerDisplayName: customer.displayName, cycle: cycle, status: status,
                                        note: trimmedOrNil(note), orderedAt: .now, syncState: .synced)
            context.insert(created)
            return created
        }()
        order.customerId = customer.id
        order.customerDisplayName = customer.displayName
        order.cycle = cycle
        order.status = status
        order.note = trimmedOrNil(note)
        order.lines = lines
        order.updatedAt = .now
        order.syncState = .synced
        save()
        return .success(order.id)
    }

    /// Cambia solo el estado de un pedido de cliente (p. ej. a Cumplido al convertirlo en venta).
    @discardableResult
    public func setCustomerOrderStatus(sellerId: String, orderId: String, status: CustomerOrderStatus) -> ActionError? {
        guard let order = fetchAll(FetchDescriptor<CustomerOrder>(predicate: #Predicate { $0.id == orderId })).first,
              let lines = order.lines
        else { return ActionError("Pedido no encontrado.") }
        switch saveCustomerOrder(sellerId: sellerId, orderId: orderId, customerId: order.customerId, newCustomerName: nil,
                                 cycle: order.cycle, status: status, note: order.note, lines: lines) {
        case .success: return nil
        case .failure(let error): return error
        }
    }
}
