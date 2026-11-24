import APIClient
import Core
import Foundation
import Persistence
import SwiftData

/// Error de una acción local, con mensaje listo para la UI.
public struct ActionError: Error, Equatable, Sendable {
    public let message: String

    public init(_ message: String) {
        self.message = message
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

extension SyncEngine {
    func pricingReason(code: String?) -> PricingReason? {
        guard let code else { return nil }
        return fetchAll(FetchDescriptor<PricingReasonRecord>(predicate: #Predicate { $0.code == code })).first?.reason
    }

    // MARK: - Venta (§4.3, etapa 3)

    /// Crea la venta localmente, descuenta stock, encola `sale.create` e intenta enviarla.
    public func registerSale(sellerId: String, lines: [SaleDraftLine], note: String?,
                             customerId: String?, customerName: String?) -> Result<String, ActionError> {
        guard !lines.isEmpty else { return .failure(ActionError("Agrega al menos un producto.")) }

        var requested: [String: Int] = [:]
        for line in lines { requested[line.productId, default: 0] += line.quantity }

        var snapshots: [SaleLineSnapshot] = []
        for line in lines {
            guard let product = product(id: line.productId) else {
                return .failure(ActionError("Uno de los productos ya no existe en el catálogo."))
            }
            let available = stockItem(productId: line.productId)?.operationalQuantity ?? 0
            let reason = pricingReason(code: line.reasonCode)
            do throws(SaleLineError) {
                try CartRules.validateLine(quantity: line.quantity, finalPrice: line.finalPrice,
                                           suggested: product.lastSuggestedSale, reason: reason,
                                           isSellable: product.isSellable, available: available)
                if let total = requested[line.productId], total > available {
                    throw .insufficientStock(available: available)
                }
            } catch {
                return .failure(ActionError("\(product.name): \(error.message)"))
            }
            snapshots.append(SaleLineSnapshot(
                sellerProductId: product.id, productName: product.name, naturaSku: product.naturaSku,
                quantity: line.quantity, suggestedPesos: product.lastSuggestedSalePesos, finalPesos: line.finalPrice.pesos,
                reasonCode: reason?.code, reasonNote: reason == nil ? nil : trimmedOrNil(line.reasonNote)))
        }

        let saleId = UUID().uuidString.lowercased()
        let occurredAt = Date()
        let cleanNote = trimmedOrNil(note)
        context.insert(LocalSale(id: saleId, sellerId: sellerId, occurredAt: occurredAt, note: cleanNote,
                                 customerId: customerId, customerName: customerName, lines: snapshots, syncState: .pending))

        let input = CreateSaleInputDTO(
            clientMutationId: saleId, occurredAt: occurredAt.ISO8601Format(), customerId: customerId, note: cleanNote,
            lines: snapshots.map {
                CreateSaleLineInputDTO(sellerProductId: $0.sellerProductId, quantity: $0.quantity,
                                       finalUnitPriceCents: $0.finalPesos, pricingReasonCode: $0.reasonCode,
                                       pricingReasonNote: $0.reasonNote)
            })
        let mutation = enqueue(.saleCreate, sellerId: sellerId, entityKey: saleId, payload: input,
                               relatedProductIds: Array(Set(snapshots.map(\.sellerProductId))))
        for line in snapshots {
            adjustStock(productId: line.sellerProductId, sellerId: sellerId, delta: -line.quantity)
            addLocalEvent(mutationId: mutation.id, sellerId: sellerId, productId: line.sellerProductId,
                          kind: .sale, quantity: -line.quantity, note: cleanNote ?? "Venta")
        }
        save()
        pushSoon(sellerId: sellerId)
        return .success(saleId)
    }

    /// Revisar venta fallida (§7.5): reemplaza las líneas y la reenvía con el mismo clientMutationId.
    public func resubmitSale(sellerId: String, saleId: String, lines: [SaleLineSnapshot]) -> ActionError? {
        guard let sale = fetchAll(FetchDescriptor<LocalSale>(predicate: #Predicate { $0.id == saleId })).first,
              let mutation = pendingMutations(sellerId: sellerId).first(where: { $0.type == .saleCreate && $0.entityKey == saleId })
        else { return ActionError("La venta ya no está pendiente.") }
        let kept = lines.filter { $0.quantity > 0 }
        guard !kept.isEmpty else { return discard(mutation, sellerId: sellerId) }

        for line in sale.lines { adjustStock(productId: line.sellerProductId, sellerId: sellerId, delta: line.quantity) }
        removeLocalEvents(mutationId: mutation.id)
        for line in kept {
            adjustStock(productId: line.sellerProductId, sellerId: sellerId, delta: -line.quantity)
            addLocalEvent(mutationId: mutation.id, sellerId: sellerId, productId: line.sellerProductId,
                          kind: .sale, quantity: -line.quantity, note: sale.note ?? "Venta")
        }
        sale.lines = kept
        sale.syncState = .pending
        sale.errorMessage = nil
        let input = CreateSaleInputDTO(
            clientMutationId: saleId, occurredAt: sale.occurredAt.ISO8601Format(), customerId: sale.customerId, note: sale.note,
            lines: kept.map {
                CreateSaleLineInputDTO(sellerProductId: $0.sellerProductId, quantity: $0.quantity,
                                       finalUnitPriceCents: $0.finalPesos, pricingReasonCode: $0.reasonCode,
                                       pricingReasonNote: $0.reasonNote)
            })
        mutation.payload = PayloadCoding.encode(input)
        mutation.relatedProductIds = Array(Set(kept.map(\.sellerProductId)))
        mutation.status = .pending
        mutation.retryCount = 0
        mutation.nextAttemptAt = nil
        mutation.lastErrorMessage = nil
        save()
        pushSoon(sellerId: sellerId)
        return nil
    }

    // MARK: - Inventario (etapa 5)

    /// Conciliación física: el conteo pasa a ser el stock operativo local.
    @discardableResult
    public func createReconciliation(sellerId: String, productId: String, counted: Int, note: String?) -> ActionError? {
        guard counted >= 0 else { return ActionError("El conteo no puede ser negativo.") }
        let current = stockItem(productId: productId)?.operationalQuantity ?? 0
        let input = CreateReconciliationInputDTO(sellerProductId: productId, countedQuantity: counted,
                                                 reasonNote: trimmedOrNil(note), reconciledAt: Date().ISO8601Format())
        let mutation = enqueue(.inventoryReconciliationCreate, sellerId: sellerId, entityKey: productId,
                               payload: input, relatedProductIds: [productId])
        if let item = stockItem(productId: productId) {
            item.operationalQuantity = counted
            item.lastReconciledAt = .now
        } else {
            adjustStock(productId: productId, sellerId: sellerId, delta: counted)
        }
        addLocalEvent(mutationId: mutation.id, sellerId: sellerId, productId: productId, kind: .reconciliation,
                      quantity: counted - current, note: trimmedOrNil(note) ?? "Conteo físico: \(counted)")
        save()
        pushSoon(sellerId: sellerId)
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
        product.syncState = .pending
        enqueue(.catalogBarcodeAdd, sellerId: sellerId, entityKey: productId,
                payload: BarcodePayload(sellerProductId: productId, ean: ean), relatedProductIds: [productId])
        save()
        pushSoon(sellerId: sellerId)
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
                                      barcodes: [], syncState: .pending))
        enqueue(.catalogProductQuick, sellerId: sellerId, entityKey: localId,
                payload: QuickProductPayload(localId: localId, naturaSku: sku, name: name), relatedProductIds: [localId])
        save()
        pushSoon(sellerId: sellerId)
        return .success(localId)
    }

    /// Autocompletado del nombre desde el maestro Natura (solo online).
    public func lookupMasterProductName(sku: String) async -> String? {
        let normalized = Normalize.naturaSku(sku)
        guard !normalized.isEmpty, connectivity.isOnline,
              case .success(let response) = await fetch(.masterProductLookup(sku: normalized)), response.found
        else { return nil }
        return response.product?.name
    }

    // MARK: - Recepción (etapa 6)

    /// Confirma la cantidad recibida (y precio de venta) de una línea. Offline: LWW sobre la misma línea.
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
        line.syncState = .pending
        recomputeTotals(order)

        let productId = product(sku: line.naturaSku, sellerId: sellerId)?.id
        let payload = ReceivingLinePayload(orderId: orderId, lineId: lineId, suggestedSaleUnitPriceCents: suggestedPesos,
                                           receivedConfirmationQuantity: quantity)
        let mutation: PendingMutation
        if let existing = coalescible(.receivingLineConfirm, entityKey: lineId, sellerId: sellerId) {
            existing.payload = PayloadCoding.encode(payload)
            existing.status = .pending
            existing.nextAttemptAt = nil
            mutation = existing
        } else {
            mutation = enqueue(.receivingLineConfirm, sellerId: sellerId, entityKey: lineId, payload: payload,
                               relatedProductIds: productId.map { [$0] } ?? [])
        }
        if let productId, delta != 0 {
            adjustStock(productId: productId, sellerId: sellerId, delta: delta)
            addLocalEvent(mutationId: mutation.id, sellerId: sellerId, productId: productId,
                          kind: .receipt, quantity: delta, note: "Pedido \(order.orderNumber)")
        }
        save()
        pushSoon(sellerId: sellerId)
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

    /// Acepta las propuestas del OCR (cantidad y precio) en todas las líneas que las tengan.
    public func acceptOcrProposals(sellerId: String, orderId: String) -> Int {
        var count = 0
        for line in lines(orderId: orderId)
        where line.proposedReceivedQuantity != nil || line.proposedSuggestedPesos != nil {
            let quantity = min(line.proposedReceivedQuantity ?? line.receivedQuantity, line.quantity)
            if confirmReceivingLine(sellerId: sellerId, lineId: line.id, quantity: quantity,
                                    suggestedPesos: line.proposedSuggestedPesos ?? line.suggestedPesos) == nil {
                count += 1
            }
        }
        return count
    }

    /// Cerrar / reabrir pedido (solo online). Primero envía las recepciones pendientes.
    public func setReceivingClosed(sellerId: String, orderId: String, closed: Bool) async -> ActionError? {
        guard connectivity.isOnline else { return ActionError("Necesitas conexión para cerrar o reabrir el pedido.") }
        await pushPending(sellerId: sellerId)
        let lineIds = Set(lines(orderId: orderId).map(\.id))
        if pendingMutations(sellerId: sellerId).contains(where: { lineIds.contains($0.entityKey) }) {
            return ActionError("Hay recepciones sin sincronizar en este pedido. Revísalas en Ajustes.")
        }
        switch await fetch(.receivingReview(orderId: orderId, close: closed)) {
        case .success(let response):
            applyNaturaOrderDetail(response.order, sellerId: sellerId)
            save()
            return nil
        case .failure(let error):
            handle(error)
            return ActionError(error.userMessage)
        }
    }

    /// Vuelve a descargar el detalle de un pedido Natura.
    public func refreshNaturaOrder(sellerId: String, orderId: String) async {
        guard connectivity.isOnline, case .success(let response) = await fetch(.naturaOrder(id: orderId)) else { return }
        applyNaturaOrderDetail(response.order, sellerId: sellerId)
        save()
    }

    /// Sube la foto de la boleta al OCR del backend (solo online) y descarga las propuestas.
    public func uploadReceipt(sellerId: String, orderId: String, jpeg: Data) async -> Result<String, ActionError> {
        guard connectivity.isOnline else { return .failure(ActionError("El OCR necesita conexión.")) }
        switch await fetch(.receiptOcr(orderId: orderId, jpeg: jpeg)) {
        case .success(let response):
            await refreshNaturaOrder(sellerId: sellerId, orderId: orderId)
            let ocr = response.ocr
            if ocr.status != "succeeded" {
                return .failure(ActionError("No se pudo leer la boleta. Intenta con otra foto, más nítida y derecha."))
            }
            var summary = "Leídas \(ocr.matchedLineCount) línea(s) del pedido."
            if !ocr.unmatchedSkus.isEmpty {
                summary += " SKU sin coincidencia: \(ocr.unmatchedSkus.joined(separator: ", "))."
            }
            return .success(summary)
        case .failure(let error):
            handle(error)
            return .failure(ActionError(error.userMessage))
        }
    }

    // MARK: - Natura (etapa 7, solo online)

    /// Importa pedidos entregados. Las credenciales Natura no se guardan.
    public func importNaturaOrders(sellerId: String, customerCode: String, password: String) async -> Result<String, ActionError> {
        guard connectivity.isOnline else { return .failure(ActionError("Necesitas conexión para importar desde Natura.")) }
        switch await fetch(.importDeliveredOrders(customerCode: customerCode.trimmingCharacters(in: .whitespaces), password: password)) {
        case .success(let response):
            await pullAll(sellerId: sellerId)
            return .success("Importados \(response.run.importedOrderCount) pedido(s) y \(response.run.importedLineCount) línea(s).")
        case .failure(let error):
            handle(error)
            return .failure(ActionError(error.userMessage))
        }
    }

    public func importRuns() async -> Result<[NaturaImportRunDTO], ActionError> {
        switch await fetch(.naturaImportRuns) {
        case .success(let response): return .success(response.runs)
        case .failure(let error):
            handle(error)
            return .failure(ActionError(error.userMessage))
        }
    }

    // MARK: - Clientes (etapa 8)

    /// Crea o edita un cliente localmente y encola la mutación. Devuelve el id (local o real).
    public func saveCustomer(sellerId: String, customerId: String?, name: String, rut: String?, phone: String?,
                             notes: String?) -> Result<String, ActionError> {
        let displayName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard CustomerRules.isValidName(displayName) else { return .failure(ActionError("Ingresa el nombre del cliente.")) }
        let input = CustomerInputDTO(displayName: displayName, rut: trimmedOrNil(rut), phone: trimmedOrNil(phone),
                                     notes: trimmedOrNil(notes))

        if let customerId,
           let customer = fetchAll(FetchDescriptor<Customer>(predicate: #Predicate { $0.id == customerId })).first {
            customer.rename(displayName)
            customer.rut = input.rut
            customer.phone = input.phone
            customer.notes = input.notes
            customer.updatedAt = .now
            customer.syncState = .pending
            if let create = coalescible(.customerCreate, entityKey: customerId, sellerId: sellerId),
               var payload = PayloadCoding.decode(CustomerCreatePayload.self, from: create.payload) {
                payload.input = input
                create.payload = PayloadCoding.encode(payload)
                create.status = .pending
            } else if let update = coalescible(.customerUpdate, entityKey: customerId, sellerId: sellerId) {
                update.payload = PayloadCoding.encode(CustomerUpdatePayload(customerId: customerId, input: input))
                update.status = .pending
            } else {
                enqueue(.customerUpdate, sellerId: sellerId, entityKey: customerId,
                        payload: CustomerUpdatePayload(customerId: customerId, input: input))
            }
            save()
            pushSoon(sellerId: sellerId)
            return .success(customerId)
        }

        let localId = LocalID.make()
        context.insert(Customer(id: localId, sellerId: sellerId, displayName: displayName, rut: input.rut,
                                phone: input.phone, notes: input.notes, syncState: .pending))
        enqueue(.customerCreate, sellerId: sellerId, entityKey: localId,
                payload: CustomerCreatePayload(localId: localId, input: input))
        save()
        pushSoon(sellerId: sellerId)
        return .success(localId)
    }

    /// Crea o edita un pedido de cliente (100 % offline, §4.7). Un cliente nuevo se crea primero en local.
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
                                        note: trimmedOrNil(note), orderedAt: .now, syncState: .pending)
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
        order.syncState = .pending

        let input = CustomerOrderInputDTO(
            customerId: customer.id, newCustomerName: nil, cycle: cycle, status: status.rawValue, note: order.note,
            orderedAt: order.orderedAt.ISO8601Format(),
            lines: lines.map {
                CustomerOrderLineInputDTO(sellerProductId: $0.sellerProductId, quantity: $0.quantity,
                                          suggestedUnitPriceCents: $0.suggestedPesos, finalUnitPriceCents: $0.finalPesos,
                                          note: $0.note)
            })
        let payload = CustomerOrderPayload(orderId: order.id, input: input)
        if let create = coalescible(.customerOrderCreate, entityKey: order.id, sellerId: sellerId) {
            create.payload = PayloadCoding.encode(payload)
            create.status = .pending
        } else if existing == nil {
            enqueue(.customerOrderCreate, sellerId: sellerId, entityKey: order.id, payload: payload)
        } else if let update = coalescible(.customerOrderUpdate, entityKey: order.id, sellerId: sellerId) {
            update.payload = PayloadCoding.encode(payload)
            update.status = .pending
        } else {
            enqueue(.customerOrderUpdate, sellerId: sellerId, entityKey: order.id, payload: payload)
        }
        save()
        pushSoon(sellerId: sellerId)
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

    public func refreshCustomerOrder(sellerId: String, orderId: String) async {
        guard connectivity.isOnline, !LocalID.isLocal(orderId),
              case .success(let response) = await fetch(.customerOrder(id: orderId)) else { return }
        applyCustomerOrderDetail(response.order, sellerId: sellerId)
        save()
    }

    // MARK: - Cola: reintentar / descartar (§4.8, etapa 9)

    public func retry(_ mutation: PendingMutation, sellerId: String) {
        mutation.status = .pending
        mutation.retryCount = 0
        mutation.nextAttemptAt = nil
        mutation.lastErrorMessage = nil
        let key = mutation.entityKey
        switch mutation.type {
        case .saleCreate?:
            if let sale = fetchAll(FetchDescriptor<LocalSale>(predicate: #Predicate { $0.id == key })).first {
                sale.syncState = .pending
                sale.errorMessage = nil
            }
        case .receivingLineConfirm?: naturaLine(id: key)?.syncState = .pending
        case .customerCreate?, .customerUpdate?:
            fetchAll(FetchDescriptor<Customer>(predicate: #Predicate { $0.id == key })).first?.syncState = .pending
        case .customerOrderCreate?, .customerOrderUpdate?:
            fetchAll(FetchDescriptor<CustomerOrder>(predicate: #Predicate { $0.id == key })).first?.syncState = .pending
        case .catalogBarcodeAdd?, .catalogProductQuick?: product(id: key)?.syncState = .pending
        default: break
        }
        save()
        pushSoon(sellerId: sellerId)
    }

    public func retryAllFailed(sellerId: String) {
        for mutation in pendingMutations(sellerId: sellerId) where mutation.status == .failed {
            retry(mutation, sellerId: sellerId)
        }
    }

    /// Descarta la mutación y revierte su efecto local; luego refresca desde el backend.
    @discardableResult
    public func discard(_ mutation: PendingMutation, sellerId: String) -> ActionError? {
        let key = mutation.entityKey
        let others = pendingMutations(sellerId: sellerId).filter { $0.id != mutation.id }
        switch mutation.type {
        case .saleCreate?:
            if let sale = fetchAll(FetchDescriptor<LocalSale>(predicate: #Predicate { $0.id == key })).first {
                for line in sale.lines { adjustStock(productId: line.sellerProductId, sellerId: sellerId, delta: line.quantity) }
                context.delete(sale)
            }
        case .catalogBarcodeAdd?:
            if let payload = PayloadCoding.decode(BarcodePayload.self, from: mutation.payload), let product = product(id: key) {
                product.barcodes.removeAll { $0 == payload.ean }
                product.syncState = .synced
            }
        case .catalogProductQuick?:
            if others.contains(where: { $0.payloadText.contains(key) }) {
                return ActionError("Este producto se usa en otros cambios pendientes. Descártalos primero.")
            }
            if let product = product(id: key) { context.delete(product) }
        case .receivingLineConfirm?:
            naturaLine(id: key)?.syncState = .synced
        case .customerCreate?:
            if others.contains(where: { $0.payloadText.contains(key) }) {
                return ActionError("Este cliente se usa en pedidos o ventas pendientes. Descártalos primero.")
            }
            for customer in fetchAll(FetchDescriptor<Customer>(predicate: #Predicate { $0.id == key })) { context.delete(customer) }
        case .customerUpdate?:
            fetchAll(FetchDescriptor<Customer>(predicate: #Predicate { $0.id == key })).first?.syncState = .synced
        case .customerOrderCreate?:
            for order in fetchAll(FetchDescriptor<CustomerOrder>(predicate: #Predicate { $0.id == key })) { context.delete(order) }
        case .customerOrderUpdate?:
            fetchAll(FetchDescriptor<CustomerOrder>(predicate: #Predicate { $0.id == key })).first?.syncState = .synced
        case .inventoryReconciliationCreate?, nil:
            break
        }
        removeLocalEvents(mutationId: mutation.id)
        context.delete(mutation)
        save()
        if connectivity.isOnline {
            Task { await self.pullAll(sellerId: sellerId) }
        }
        return nil
    }

    // MARK: - Ajustes (solo online)

    /// Cambia FIFO/LIFO en el backend. Devuelve un mensaje de error o nil.
    public func updateIssueStrategy(_ strategy: IssueStrategy, sellerId: String) async -> String? {
        switch await fetch(.updateSettings(inventoryIssueStrategy: strategy.rawValue)) {
        case .success(let response):
            applySettings(response.settings, sellerId: sellerId)
            save()
            return nil
        case .failure(let error):
            handle(error)
            return error.userMessage
        }
    }
}
