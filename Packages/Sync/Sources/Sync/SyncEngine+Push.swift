import APIClient
import Core
import Foundation
import Persistence
import SwiftData

extension SyncEngine {
    /// Envía la cola en orden determinista (§7.3). Errores de red/5xx ⇒ sigue pendiente con backoff;
    /// errores 4xx de negocio ⇒ `failed` (requiere revisión).
    public func pushPending(sellerId: String) async {
        guard !isPushing, connectivity.isOnline else { return }
        isPushing = true
        defer { isPushing = false }

        var events: [SyncEventInputDTO] = []
        var succeeded = 0
        let now = Date()

        let queue = SyncQueue.sorted(
            pendingMutations(sellerId: sellerId).filter { $0.status != .failed && $0.type != nil },
            type: { $0.type ?? .saleCreate },
            createdAt: \.createdAt)

        for mutation in queue {
            if mutation.isDeleted { continue }
            if let next = mutation.nextAttemptAt, next > now { continue }
            if isBlocked(mutation, sellerId: sellerId) { continue }
            guard let type = mutation.type else { continue }

            mutation.status = .syncing
            save()
            let result = await execute(mutation, type: type, sellerId: sellerId)

            switch result {
            case .success:
                AppLog.sync.info("OK \(type.rawValue, privacy: .public) \(mutation.entityKey, privacy: .public)")
                events.append(SyncEventInputDTO(entityType: type.rawValue, localReference: mutation.entityKey,
                                                status: "succeeded", errorSummary: nil))
                removeLocalEvents(mutationId: mutation.id)
                context.delete(mutation)
                succeeded += 1
                save()

            case .failure(let error):
                AppLog.sync.error("Falló \(type.rawValue, privacy: .public): \(error.userMessage, privacy: .public)")
                mutation.retryCount += 1
                mutation.lastErrorMessage = error.userMessage
                if case .unauthorized = error {
                    mutation.status = .pending
                    save()
                    handle(error)
                    return
                }
                if error.isUnreachable {
                    mutation.status = .pending
                    mutation.nextAttemptAt = Date().addingTimeInterval(SyncQueue.backoff(retryCount: mutation.retryCount))
                    save()
                    lastErrorMessage = error.userMessage
                    scheduleRetry(sellerId: sellerId, after: SyncQueue.backoff(retryCount: mutation.retryCount))
                    break
                }
                mutation.status = .failed
                markFailed(mutation, type: type, message: error.userMessage)
                events.append(SyncEventInputDTO(entityType: type.rawValue, localReference: mutation.entityKey,
                                                status: "failed", errorSummary: error.userMessage))
                save()
                continue
            }
            if case .failure = result { break }
        }

        if !events.isEmpty {
            _ = await fetch(.recordSyncEvents(events))
        }
        lastPushAt = .now
        if succeeded > 0 {
            lastErrorMessage = nil
            await pullAll(sellerId: sellerId)
        }
    }

    /// Reintento automático tras el backoff mientras la app esté abierta.
    private func scheduleRetry(sellerId: String, after delay: TimeInterval) {
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(delay, 1)))
            await self?.pushPending(sellerId: sellerId)
        }
    }

    /// Una mutación que referencia un ID local de otra entidad aún no creada en el backend espera.
    private func isBlocked(_ mutation: PendingMutation, sellerId: String) -> Bool {
        let references = LocalID.references(in: mutation.payloadText).subtracting([mutation.entityKey])
        guard !references.isEmpty else { return false }
        let unresolved = Set(pendingMutations(sellerId: sellerId).filter { $0.id != mutation.id }.map(\.entityKey))
        return !references.isDisjoint(with: unresolved)
    }

    // MARK: - Ejecución por tipo

    private func execute(_ mutation: PendingMutation, type: MutationType, sellerId: String) async -> Result<Void, APIError> {
        let data = mutation.payload
        // Idempotency-Key = id de la mutación (§9.2): un reintento tras perder la respuesta no duplica.
        let key = mutation.id.uuidString.lowercased()
        switch type {
        case .saleCreate:
            guard let input = PayloadCoding.decode(CreateSaleInputDTO.self, from: data) else { return .failure(.decoding("payload")) }
            switch await fetch(Endpoint<CreateSaleResponseDTO>.createSale(input).idempotent(key)) {
            case .success(let response):
                applySaleCreated(response.sale, sellerId: sellerId)
                return .success(())
            case .failure(let error) where error.isDuplicateSale:
                markSaleSynced(id: input.clientMutationId)
                return .success(())
            case .failure(let error):
                return .failure(error)
            }

        case .inventoryReconciliationCreate:
            guard let input = PayloadCoding.decode(CreateReconciliationInputDTO.self, from: data) else { return .failure(.decoding("payload")) }
            return await fetch(Endpoint<ReconciliationResponseDTO>.createReconciliation(input).idempotent(key)).map { _ in () }

        case .catalogBarcodeAdd:
            guard let payload = PayloadCoding.decode(BarcodePayload.self, from: data) else { return .failure(.decoding("payload")) }
            return await fetch(Endpoint<CatalogProductResponseDTO>.addBarcode(sellerProductId: payload.sellerProductId, ean: payload.ean).idempotent(key)).map { response in
                self.applyCatalogProduct(response.product, sellerId: sellerId, replacingLocalId: nil)
            }

        case .catalogProductQuick:
            guard let payload = PayloadCoding.decode(QuickProductPayload.self, from: data) else { return .failure(.decoding("payload")) }
            return await fetch(Endpoint<CatalogProductResponseDTO>.quickProduct(naturaSku: payload.naturaSku, name: payload.name).idempotent(key)).map { response in
                self.applyCatalogProduct(response.product, sellerId: sellerId, replacingLocalId: payload.localId)
            }

        case .receivingLineConfirm:
            guard let payload = PayloadCoding.decode(ReceivingLinePayload.self, from: data) else { return .failure(.decoding("payload")) }
            return await fetch(Endpoint<NaturaOrderDetailResponseDTO>.updateNaturaOrderLine(orderId: payload.orderId, lineId: payload.lineId, input: payload.input).idempotent(key)).map { response in
                if let line = self.naturaLine(id: payload.lineId) { line.syncState = .synced }
                self.applyNaturaOrderDetail(response.order, sellerId: sellerId)
            }

        case .customerCreate:
            guard let payload = PayloadCoding.decode(CustomerCreatePayload.self, from: data) else { return .failure(.decoding("payload")) }
            return await fetch(Endpoint<CustomerResponseDTO>.createCustomer(payload.input).idempotent(key)).map { response in
                self.remapLocalID(payload.localId, to: response.customer.id, sellerId: sellerId)
                self.applyCustomer(response.customer, sellerId: sellerId)
            }

        case .customerUpdate:
            guard let payload = PayloadCoding.decode(CustomerUpdatePayload.self, from: data) else { return .failure(.decoding("payload")) }
            return await fetch(Endpoint<CustomerResponseDTO>.updateCustomer(id: payload.customerId, payload.input).idempotent(key)).map { response in
                self.applyCustomer(response.customer, sellerId: sellerId)
            }

        case .customerOrderCreate:
            guard let payload = PayloadCoding.decode(CustomerOrderPayload.self, from: data) else { return .failure(.decoding("payload")) }
            return await fetch(Endpoint<CustomerOrderDetailResponseDTO>.createCustomerOrder(payload.input).idempotent(key)).map { response in
                self.remapLocalID(payload.orderId, to: response.order.order.id, sellerId: sellerId)
                self.applyCustomerOrderDetail(response.order, sellerId: sellerId)
            }

        case .customerOrderUpdate:
            guard let payload = PayloadCoding.decode(CustomerOrderPayload.self, from: data) else { return .failure(.decoding("payload")) }
            return await fetch(Endpoint<CustomerOrderDetailResponseDTO>.updateCustomerOrder(id: payload.orderId, payload.input).idempotent(key)).map { response in
                self.applyCustomerOrderDetail(response.order, sellerId: sellerId)
            }
        }
    }

    private func applySaleCreated(_ sale: CreatedSaleDTO, sellerId: String) {
        let id = sale.clientMutationId
        guard let local = fetchAll(FetchDescriptor<LocalSale>(predicate: #Predicate { $0.id == id })).first else { return }
        local.serverId = sale.id
        local.syncState = .synced
        local.errorMessage = nil
        var lines = local.lines
        for index in lines.indices {
            if let remote = sale.lines.first(where: { $0.sellerProductId == lines[index].sellerProductId }) {
                lines[index].costUnitPesos = remote.costUnitPriceCents
                lines[index].suggestedPesos = remote.suggestedUnitPriceCents ?? lines[index].suggestedPesos
            }
        }
        local.lines = lines
    }

    private func markSaleSynced(id: String) {
        fetchAll(FetchDescriptor<LocalSale>(predicate: #Predicate { $0.id == id })).first?.syncState = .synced
    }

    private func markFailed(_ mutation: PendingMutation, type: MutationType, message: String) {
        let key = mutation.entityKey
        switch type {
        case .saleCreate:
            if let sale = fetchAll(FetchDescriptor<LocalSale>(predicate: #Predicate { $0.id == key })).first {
                sale.syncState = .failed
                sale.errorMessage = message
            }
        case .receivingLineConfirm:
            naturaLine(id: key)?.syncState = .failed
        case .customerCreate, .customerUpdate:
            fetchAll(FetchDescriptor<Customer>(predicate: #Predicate { $0.id == key })).first?.syncState = .failed
        case .customerOrderCreate, .customerOrderUpdate:
            fetchAll(FetchDescriptor<CustomerOrder>(predicate: #Predicate { $0.id == key })).first?.syncState = .failed
        case .catalogBarcodeAdd, .catalogProductQuick:
            product(id: key)?.syncState = .failed
        case .inventoryReconciliationCreate:
            break
        }
    }

    func naturaLine(id: String) -> NaturaOrderLine? {
        fetchAll(FetchDescriptor<NaturaOrderLine>(predicate: #Predicate { $0.id == id })).first
    }

    // MARK: - Remapeo de IDs locales (§7.6)

    /// Reemplaza un ID local por el del servidor en entidades y mutaciones pendientes.
    func remapLocalID(_ localId: String, to serverId: String, sellerId: String) {
        guard localId != serverId else { return }
        let mapping = [localId: serverId]

        for mutation in pendingMutations(sellerId: sellerId) {
            if mutation.entityKey == localId { mutation.entityKey = serverId }
            if mutation.payloadText.contains(localId) {
                mutation.payload = Data(LocalID.rewrite(mutation.payloadText, mapping: mapping).utf8)
            }
            if mutation.relatedProductIds.contains(localId) {
                mutation.relatedProductIds = mutation.relatedProductIds.map { $0 == localId ? serverId : $0 }
            }
        }
        for customer in fetchAll(FetchDescriptor<Customer>(predicate: #Predicate { $0.id == localId })) {
            customer.id = serverId
        }
        for order in fetchAll(FetchDescriptor<CustomerOrder>(predicate: #Predicate { $0.sellerId == sellerId })) {
            if order.id == localId { order.id = serverId }
            if order.customerId == localId { order.customerId = serverId }
            if let data = order.linesData, let text = String(data: data, encoding: .utf8), text.contains(localId) {
                order.linesData = Data(LocalID.rewrite(text, mapping: mapping).utf8)
            }
        }
        for product in fetchAll(FetchDescriptor<CatalogProduct>(predicate: #Predicate { $0.id == localId })) {
            product.id = serverId
        }
        for item in fetchAll(FetchDescriptor<StockItem>(predicate: #Predicate { $0.sellerProductId == localId })) {
            item.sellerProductId = serverId
        }
        for line in fetchAll(FetchDescriptor<CartDraftLine>(predicate: #Predicate { $0.productId == localId })) {
            line.productId = serverId
            line.key = CartDraftLine.key(sellerId: line.sellerId, productId: serverId)
        }
        for draft in fetchAll(FetchDescriptor<CartDraft>(predicate: #Predicate { $0.sellerId == sellerId })) {
            if draft.customerId == localId { draft.customerId = serverId }
            if draft.sourceOrderId == localId { draft.sourceOrderId = serverId }
        }
        for sale in fetchAll(FetchDescriptor<LocalSale>(predicate: #Predicate { $0.sellerId == sellerId })) {
            if sale.customerId == localId { sale.customerId = serverId }
            if let text = String(data: sale.linesData, encoding: .utf8), text.contains(localId) {
                sale.linesData = Data(LocalID.rewrite(text, mapping: mapping).utf8)
            }
        }
        for event in fetchAll(FetchDescriptor<InventoryEventRecord>(predicate: #Predicate { $0.sellerProductId == localId })) {
            event.sellerProductId = serverId
        }
        save()
    }
}

