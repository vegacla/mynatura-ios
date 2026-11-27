import APIClient
import Core
import Foundation
import Persistence
import SwiftData

extension SyncEngine {
    /// Descarga todos los datasets (§7.4) y los aplica sin pisar entidades con cambios pendientes.
    public func pullAll(sellerId: String) async {
        guard !isPulling else { return }
        if isLocalInventory(sellerId: sellerId) {
            await pullNaturaOnly(sellerId: sellerId)
            return
        }
        isPulling = true
        defer {
            isPulling = false
            adoptLocalInventoryIfNeeded(sellerId: sellerId)
        }

        for dataset in Dataset.allCases { syncState(sellerId: sellerId, dataset: dataset).status = .syncing }

        async let catalog = fetch(.catalogProducts)
        async let stock = fetch(.stockSummary)
        async let activity = fetch(.inventoryActivity)
        async let settings = fetch(.settings)
        async let reasons = fetch(.pricingReasons)
        async let sales = fetch(.sales)
        async let orders = fetch(.naturaOrders)
        async let customers = fetch(.customers)
        async let customerOrders = fetch(.customerOrders)

        let catalogResult = await catalog
        let stockResult = await stock
        let activityResult = await activity
        apply(catalogResult, .catalog, sellerId) { self.applyCatalog($0.products, sellerId: sellerId) }
        apply(stockResult, .stock, sellerId) { self.applyStock($0.items, sellerId: sellerId) }
        if case .success(let value) = activityResult { applyActivity(value.events, sellerId: sellerId) }
        apply(await settings, .settings, sellerId) { self.applySettings($0.settings, sellerId: sellerId) }
        apply(await reasons, .pricingReasons, sellerId) { self.applyPricingReasons($0.reasons) }
        apply(await sales, .sales, sellerId) { self.applySales($0.sales, sellerId: sellerId) }
        apply(await customers, .customers, sellerId) { self.applyCustomers($0.customers, sellerId: sellerId) }

        var naturaNeedingDetail: [String] = []
        apply(await orders, .naturaOrders, sellerId) { naturaNeedingDetail = self.applyNaturaOrders($0.orders, sellerId: sellerId) }
        var customerOrdersNeedingDetail: [String] = []
        apply(await customerOrders, .customerOrders, sellerId) {
            customerOrdersNeedingDetail = self.applyCustomerOrders($0.orders, sellerId: sellerId)
        }
        save()

        // Detalles para trabajar offline: líneas de pedidos Natura en borrador y de pedidos de clientes cambiados.
        for id in naturaNeedingDetail {
            guard case .success(let response) = await fetch(.naturaOrder(id: id)) else { continue }
            applyNaturaOrderDetail(response.order, sellerId: sellerId)
        }
        for id in customerOrdersNeedingDetail {
            guard case .success(let response) = await fetch(.customerOrder(id: id)) else { continue }
            applyCustomerOrderDetail(response.order, sellerId: sellerId)
        }
        save()
    }

    /// Modo local (M2): del backend solo llegan productos nuevos, motivos de precio y pedidos Natura (import y OCR
    /// siguen en el backend hasta M3–M4). Stock, ventas, clientes y pedidos de clientes ya no se bajan.
    func pullNaturaOnly(sellerId: String) async {
        isPulling = true
        defer { isPulling = false }
        async let catalog = fetch(.catalogProducts)
        async let reasons = fetch(.pricingReasons)
        async let orders = fetch(.naturaOrders)
        apply(await catalog, .catalog, sellerId) { self.mergeCatalog($0.products, sellerId: sellerId) }
        apply(await reasons, .pricingReasons, sellerId) { self.applyPricingReasons($0.reasons) }
        var naturaNeedingDetail: [String] = []
        apply(await orders, .naturaOrders, sellerId) { naturaNeedingDetail = self.applyNaturaOrders($0.orders, sellerId: sellerId) }
        save()
        for id in naturaNeedingDetail {
            guard case .success(let response) = await fetch(.naturaOrder(id: id)) else { continue }
            applyNaturaOrderDetail(response.order, sellerId: sellerId)
        }
        save()
    }

    /// Productos del backend en modo local: agrega los nuevos y suma EAN; nunca pisa precios, nombre ni "vendible".
    func mergeCatalog(_ remote: [CatalogProductDTO], sellerId: String) {
        let local = fetchAll(FetchDescriptor<CatalogProduct>(predicate: #Predicate { $0.sellerId == sellerId }))
        let byId = Dictionary(local.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let bySku = Dictionary(local.map { (Normalize.naturaSku($0.naturaSku).lowercased(), $0) }, uniquingKeysWith: { first, _ in first })
        for dto in remote {
            if let product = byId[dto.id] ?? bySku[Normalize.naturaSku(dto.naturaSku).lowercased()] {
                for ean in dto.barcodes where !product.barcodes.contains(ean) { product.barcodes.append(ean) }
                if product.lastSuggestedSalePesos == nil { product.lastSuggestedSalePesos = dto.lastSuggestedSaleUnitPriceCents }
                if product.lastPurchasePesos == 0, dto.lastPurchaseUnitPriceCents > 0 {
                    product.lastPurchasePesos = dto.lastPurchaseUnitPriceCents
                }
            } else {
                upsertProduct(dto, existing: nil, sellerId: sellerId)
            }
        }
    }

    private func apply<R>(_ result: Result<R, APIError>, _ dataset: Dataset, _ sellerId: String, _ body: (R) -> Void) {
        let state = syncState(sellerId: sellerId, dataset: dataset)
        switch result {
        case .success(let value):
            body(value)
            state.status = .synced
            state.lastSyncedAt = .now
            state.errorMessage = nil
        case .failure(let error):
            state.status = .failed
            state.errorMessage = error.userMessage
            handle(error)
        }
    }

    func syncState(sellerId: String, dataset: Dataset) -> DatasetSyncState {
        let key = DatasetSyncState.key(sellerId: sellerId, dataset: dataset)
        if let existing = fetchAll(FetchDescriptor<DatasetSyncState>(predicate: #Predicate { $0.key == key })).first {
            return existing
        }
        let state = DatasetSyncState(sellerId: sellerId, dataset: dataset)
        context.insert(state)
        return state
    }

    // MARK: - Catálogo y stock

    func applyCatalog(_ remote: [CatalogProductDTO], sellerId: String) {
        let local = fetchAll(FetchDescriptor<CatalogProduct>(predicate: #Predicate { $0.sellerId == sellerId }))
        let protected = protectedProductIds(sellerId: sellerId)
        let byId = Dictionary(local.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for id in SnapshotMerge.idsToDelete(localIds: local.map(\.id), remoteIds: Set(remote.map(\.id)), protectedIds: protected) {
            if let product = byId[id] { context.delete(product) }
        }
        for dto in remote where SnapshotMerge.shouldOverwrite(id: dto.id, protectedIds: protected) {
            upsertProduct(dto, existing: byId[dto.id], sellerId: sellerId)
        }
    }

    /// Aplica un producto devuelto por el backend (EAN agregado o creación rápida).
    func applyCatalogProduct(_ dto: CatalogProductDTO, sellerId: String, replacingLocalId localId: String?) {
        if let localId { remapLocalID(localId, to: dto.id, sellerId: sellerId) }
        let product = upsertProduct(dto, existing: product(id: dto.id), sellerId: sellerId)
        product.syncState = .synced
    }

    @discardableResult
    func upsertProduct(_ dto: CatalogProductDTO, existing: CatalogProduct?, sellerId: String) -> CatalogProduct {
        let source = ProductSource(rawValue: dto.source) ?? .manual
        if let product = existing {
            product.naturaSku = dto.naturaSku
            product.name = dto.name
            product.sourceRaw = source.rawValue
            product.isSellable = dto.isSellable
            product.lastPurchasePesos = dto.lastPurchaseUnitPriceCents
            product.lastSuggestedSalePesos = dto.lastSuggestedSaleUnitPriceCents
            product.barcodes = dto.barcodes
            product.syncState = .synced
            return product
        }
        let product = CatalogProduct(
            id: dto.id, sellerId: sellerId, naturaSku: dto.naturaSku, name: dto.name, source: source,
            isSellable: dto.isSellable, lastPurchasePesos: dto.lastPurchaseUnitPriceCents,
            lastSuggestedSalePesos: dto.lastSuggestedSaleUnitPriceCents, barcodes: dto.barcodes)
        context.insert(product)
        return product
    }

    func applyStock(_ remote: [StockSummaryItemDTO], sellerId: String) {
        let local = fetchAll(FetchDescriptor<StockItem>(predicate: #Predicate { $0.sellerId == sellerId }))
        let protected = protectedProductIds(sellerId: sellerId)
        let byId = Dictionary(local.map { ($0.sellerProductId, $0) }, uniquingKeysWith: { first, _ in first })
        for id in SnapshotMerge.idsToDelete(localIds: local.map(\.sellerProductId),
                                            remoteIds: Set(remote.map(\.sellerProductId)), protectedIds: protected) {
            if let item = byId[id] { context.delete(item) }
        }
        for dto in remote where SnapshotMerge.shouldOverwrite(id: dto.sellerProductId, protectedIds: protected) {
            if let item = byId[dto.sellerProductId] {
                item.naturaSku = dto.naturaSku
                item.name = dto.name
                item.isSellable = dto.isSellable
                item.theoreticalQuantity = dto.theoreticalQuantity
                item.operationalQuantity = dto.operationalQuantity
                item.lastReconciledAt = dto.lastReconciledAt
            } else {
                context.insert(StockItem(
                    sellerProductId: dto.sellerProductId, sellerId: sellerId, naturaSku: dto.naturaSku,
                    name: dto.name, isSellable: dto.isSellable, theoreticalQuantity: dto.theoreticalQuantity,
                    operationalQuantity: dto.operationalQuantity, lastReconciledAt: dto.lastReconciledAt))
            }
        }
    }

    func applyActivity(_ remote: [InventoryEventDTO], sellerId: String) {
        let local = fetchAll(FetchDescriptor<InventoryEventRecord>(predicate: #Predicate { $0.sellerId == sellerId && !$0.isLocal }))
        let byId = Dictionary(local.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let remoteIds = Set(remote.map(\.id))
        for event in local where !remoteIds.contains(event.id) { context.delete(event) }
        for dto in remote where byId[dto.id] == nil {
            context.insert(InventoryEventRecord(
                id: dto.id, sellerId: sellerId, sellerProductId: dto.sellerProductId,
                kind: InventoryEventKind(rawValue: dto.type) ?? .receipt, quantity: dto.quantity,
                note: dto.note, occurredAt: dto.occurredAt, isLocal: false))
        }
    }

    func applySettings(_ remote: SellerSettingsDTO, sellerId: String) {
        let strategy = IssueStrategy(rawValue: remote.inventoryIssueStrategy) ?? .fifo
        if let existing = fetchAll(FetchDescriptor<SellerSettings>(predicate: #Predicate { $0.sellerId == sellerId })).first {
            existing.issueStrategy = strategy
        } else {
            context.insert(SellerSettings(sellerId: sellerId, issueStrategy: strategy))
        }
    }

    func applyPricingReasons(_ remote: [PricingReasonDTO]) {
        let local = fetchAll(FetchDescriptor<PricingReasonRecord>())
        let byCode = Dictionary(local.map { ($0.code, $0) }, uniquingKeysWith: { first, _ in first })
        let codes = Set(remote.map(\.code))
        for record in local where !codes.contains(record.code) { context.delete(record) }
        for dto in remote {
            guard let category = PricingReasonCategory(rawValue: dto.category) else { continue }
            if let record = byCode[dto.code] {
                record.label = dto.label
                record.categoryRaw = category.rawValue
            } else {
                context.insert(PricingReasonRecord(code: dto.code, label: dto.label, category: category))
            }
        }
    }

    // MARK: - Ventas

    func applySales(_ remote: [SaleListItemDTO], sellerId: String) {
        let local = fetchAll(FetchDescriptor<LocalSale>(predicate: #Predicate { $0.sellerId == sellerId }))
        let byId = Dictionary(local.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let remoteIds = Set(remote.map(\.clientMutationId))
        for sale in local where sale.syncState == .synced && !remoteIds.contains(sale.id) { context.delete(sale) }
        for dto in remote {
            let lines = dto.lines.map {
                SaleLineSnapshot(sellerProductId: $0.sellerProductId, productName: $0.productName, naturaSku: $0.naturaSku,
                                 quantity: $0.quantity, suggestedPesos: $0.suggestedUnitPriceCents,
                                 finalPesos: $0.finalUnitPriceCents, reasonCode: $0.pricingReasonCode,
                                 reasonNote: nil, costUnitPesos: $0.costUnitPriceCents)
            }
            if let sale = byId[dto.clientMutationId] {
                sale.serverId = dto.id
                sale.occurredAt = dto.occurredAt
                sale.note = dto.note
                sale.customerName = dto.customerDisplayName ?? sale.customerName
                sale.lines = lines
                sale.syncState = .synced
                sale.errorMessage = nil
            } else {
                context.insert(LocalSale(id: dto.clientMutationId, sellerId: sellerId, serverId: dto.id,
                                         occurredAt: dto.occurredAt, note: dto.note, customerId: nil,
                                         customerName: dto.customerDisplayName, lines: lines, syncState: .synced))
            }
        }
    }

    // MARK: - Pedidos Natura

    /// Devuelve los ids de pedidos cuyo detalle conviene descargar.
    func applyNaturaOrders(_ remote: [NaturaOrderDTO], sellerId: String) -> [String] {
        let local = fetchAll(FetchDescriptor<NaturaOrder>(predicate: #Predicate { $0.sellerId == sellerId }))
        let byId = Dictionary(local.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let remoteIds = Set(remote.map(\.id))
        let pendingOrderIds = ordersWithPendingLines(sellerId: sellerId)
        let isLocal = isLocalInventory(sellerId: sellerId)
        for order in local where !isLocal && !remoteIds.contains(order.id) && !pendingOrderIds.contains(order.id) {
            deleteLines(orderId: order.id)
            context.delete(order)
        }
        var needingDetail: [String] = []
        for dto in remote {
            let order = byId[dto.id] ?? {
                let created = NaturaOrder(id: dto.id, sellerId: sellerId, orderNumber: dto.orderNumber, cycle: dto.cycle, orderedAt: dto.orderedAt)
                context.insert(created)
                return created
            }()
            applyOrderFields(dto, to: order, keepTotals: pendingOrderIds.contains(dto.id), keepReceiving: isLocal)
            if !order.linesLoaded || order.reviewStatus == .draft { needingDetail.append(dto.id) }
        }
        return needingDetail
    }

    /// `keepReceiving`: en modo local la recepción (cerrado, revisión y totales) es del iPhone y no se pisa.
    private func applyOrderFields(_ dto: NaturaOrderDTO, to order: NaturaOrder, keepTotals: Bool, keepReceiving: Bool = false) {
        order.orderNumber = dto.orderNumber
        order.cycle = dto.cycle
        order.subCycle = dto.subCycle
        order.orderedAt = dto.orderedAt
        order.deliveredAt = dto.deliveredAt
        order.statusName = dto.statusName
        order.itemsQuantity = dto.itemsQuantity
        order.totalValuePesos = dto.totalValueCents
        order.ocrStatusRaw = dto.receiptOcrStatus
        order.ocrProcessedAt = dto.receiptOcrProcessedAt
        if keepReceiving { return }
        order.receivingClosedAt = dto.receivingClosedAt
        order.reviewStatusRaw = dto.receivingReviewStatus
        if !keepTotals {
            order.receivedUnits = dto.receivedUnitsQuantity
            order.pendingUnits = dto.pendingUnitsQuantity
        }
    }

    func applyNaturaOrderDetail(_ detail: NaturaOrderDetailDTO, sellerId: String) {
        let orderId = detail.order.id
        let order = fetchAll(FetchDescriptor<NaturaOrder>(predicate: #Predicate { $0.id == orderId })).first ?? {
            let created = NaturaOrder(id: orderId, sellerId: sellerId, orderNumber: detail.order.orderNumber,
                                      cycle: detail.order.cycle, orderedAt: detail.order.orderedAt)
            context.insert(created)
            return created
        }()
        let isLocal = isLocalInventory(sellerId: sellerId)
        let local = lines(orderId: orderId)
        let byId = Dictionary(local.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let remoteIds = Set(detail.lines.map(\.id))
        for line in local where !isLocal && !remoteIds.contains(line.id) && line.syncState == .synced { context.delete(line) }
        for (index, dto) in detail.lines.enumerated() {
            let isNew = byId[dto.id] == nil
            let line = byId[dto.id] ?? {
                let created = NaturaOrderLine(id: dto.id, orderId: orderId, sellerId: sellerId, position: index,
                                              naturaSku: dto.naturaSku, productName: dto.productName, quantity: dto.quantity)
                context.insert(created)
                return created
            }()
            line.position = index
            line.naturaSku = dto.naturaSku
            line.productName = dto.productName
            line.quantity = dto.quantity
            line.purchasePesos = dto.purchaseUnitPriceCents
            line.proposedSuggestedPesos = dto.proposedSuggestedSaleUnitPriceCents
            line.proposedReceivedQuantity = dto.proposedReceivedConfirmationQuantity
            line.barcodes = dto.barcodes
            if line.syncState == .synced && (!isLocal || isNew) {
                line.suggestedPesos = dto.suggestedSaleUnitPriceCents
                line.receivedQuantity = dto.receivedConfirmationQuantity
                line.receivedConfirmedAt = dto.receivedConfirmedAt
            }
        }
        let hasPending = isLocal || lines(orderId: orderId).contains { $0.syncState != .synced }
        applyOrderFields(detail.order, to: order, keepTotals: hasPending, keepReceiving: isLocal)
        order.linesLoaded = true
        if hasPending { recomputeTotals(order) }
    }

    func lines(orderId: String) -> [NaturaOrderLine] {
        fetchAll(FetchDescriptor<NaturaOrderLine>(predicate: #Predicate { $0.orderId == orderId }, sortBy: [SortDescriptor(\.position)]))
    }

    func recomputeTotals(_ order: NaturaOrder) {
        let totals = ReceivingRules.totals(lines: lines(orderId: order.id).map { (ordered: $0.quantity, received: $0.receivedQuantity) })
        order.receivedUnits = totals.received
        order.pendingUnits = totals.pending
    }

    private func deleteLines(orderId: String) {
        for line in lines(orderId: orderId) { context.delete(line) }
    }

    private func ordersWithPendingLines(sellerId: String) -> Set<String> {
        let lines = fetchAll(FetchDescriptor<NaturaOrderLine>(predicate: #Predicate { $0.sellerId == sellerId }))
        return Set(lines.filter { $0.syncState != .synced }.map(\.orderId))
    }

    // MARK: - Clientes

    func applyCustomers(_ remote: [CustomerDTO], sellerId: String) {
        let local = fetchAll(FetchDescriptor<Customer>(predicate: #Predicate { $0.sellerId == sellerId }))
        let protected = Set(local.filter { $0.syncState != .synced }.map(\.id))
        let byId = Dictionary(local.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for id in SnapshotMerge.idsToDelete(localIds: local.map(\.id), remoteIds: Set(remote.map(\.id)), protectedIds: protected) {
            if let customer = byId[id] { context.delete(customer) }
        }
        for dto in remote where SnapshotMerge.shouldOverwrite(id: dto.id, protectedIds: protected) {
            applyCustomer(dto, sellerId: sellerId, existing: byId[dto.id])
        }
    }

    func applyCustomer(_ dto: CustomerDTO, sellerId: String, existing: Customer? = nil) {
        let id = dto.id
        if let customer = existing ?? fetchAll(FetchDescriptor<Customer>(predicate: #Predicate { $0.id == id })).first {
            customer.rename(dto.displayName)
            customer.rut = dto.rut
            customer.phone = dto.phone
            customer.notes = dto.notes
            customer.updatedAt = dto.updatedAt
            customer.syncState = .synced
        } else {
            context.insert(Customer(id: dto.id, sellerId: sellerId, displayName: dto.displayName, rut: dto.rut,
                                    phone: dto.phone, notes: dto.notes, updatedAt: dto.updatedAt))
        }
    }

    // MARK: - Pedidos de clientes

    func applyCustomerOrders(_ remote: [CustomerOrderDTO], sellerId: String) -> [String] {
        let local = fetchAll(FetchDescriptor<CustomerOrder>(predicate: #Predicate { $0.sellerId == sellerId }))
        let protected = Set(local.filter { $0.syncState != .synced }.map(\.id))
        let byId = Dictionary(local.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for id in SnapshotMerge.idsToDelete(localIds: local.map(\.id), remoteIds: Set(remote.map(\.id)), protectedIds: protected) {
            if let order = byId[id] { context.delete(order) }
        }
        var needingDetail: [String] = []
        for dto in remote where SnapshotMerge.shouldOverwrite(id: dto.id, protectedIds: protected) {
            let existing = byId[dto.id]
            if existing == nil || existing?.updatedAt != dto.updatedAt || existing?.linesData == nil {
                needingDetail.append(dto.id)
            }
            upsertCustomerOrder(dto, existing: existing, sellerId: sellerId)
        }
        return needingDetail
    }

    func applyCustomerOrderDetail(_ detail: CustomerOrderDetailDTO, sellerId: String) {
        let id = detail.order.id
        let existing = fetchAll(FetchDescriptor<CustomerOrder>(predicate: #Predicate { $0.id == id })).first
        if let existing, existing.syncState != .synced, existing.id == id,
           pendingMutations(sellerId: sellerId).contains(where: { $0.entityKey == id }) {
            return
        }
        let order = upsertCustomerOrder(detail.order, existing: existing, sellerId: sellerId)
        order.lines = detail.lines.map {
            CustomerOrderLineSnapshot(id: $0.id, sellerProductId: $0.sellerProductId, productName: $0.productName,
                                      naturaSku: $0.naturaSku, quantity: $0.quantity,
                                      suggestedPesos: $0.suggestedUnitPriceCents, finalPesos: $0.finalUnitPriceCents, note: $0.note)
        }
        order.syncState = .synced
    }

    @discardableResult
    private func upsertCustomerOrder(_ dto: CustomerOrderDTO, existing: CustomerOrder?, sellerId: String) -> CustomerOrder {
        let status = CustomerOrderStatus(rawValue: dto.status) ?? .draft
        if let order = existing {
            order.customerId = dto.customerId
            order.customerDisplayName = dto.customerDisplayName
            order.cycle = dto.cycle
            order.status = status
            order.note = dto.note
            order.orderedAt = dto.orderedAt
            order.updatedAt = dto.updatedAt
            order.lineCount = dto.lineCount
            return order
        }
        let order = CustomerOrder(id: dto.id, sellerId: sellerId, customerId: dto.customerId,
                                  customerDisplayName: dto.customerDisplayName, cycle: dto.cycle, status: status,
                                  note: dto.note, orderedAt: dto.orderedAt, updatedAt: dto.updatedAt)
        order.lineCount = dto.lineCount
        context.insert(order)
        return order
    }
}
