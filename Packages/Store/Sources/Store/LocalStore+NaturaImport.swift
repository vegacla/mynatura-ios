import Core
import Foundation
import Natura
import Persistence
import SwiftData

/// Línea de un pedido Natura lista para guardar (del Excel del pedido o, de respaldo, del HTML).
struct ImportedLine {
    let sku: String
    let name: String
    let brand: String?
    let quantity: Int
    /// nil = costo desconocido · 0 = gratis de Natura.
    let unitCostPesos: Int?
    let suggestedUnitPesos: Int?

    init(report line: OrderReportLine) {
        sku = line.sku
        name = line.name
        brand = line.brand.isEmpty ? nil : line.brand
        quantity = line.quantity
        unitCostPesos = line.unitCostPesos
        suggestedUnitPesos = line.suggestedUnitPesos
    }

    init(item: NaturaOrderItem) {
        sku = item.sku
        name = item.name
        brand = nil
        quantity = item.quantity
        let raw = item.rawUnitValue.trimmingCharacters(in: .whitespaces)
        unitCostPesos = raw == "-" ? 0 : item.unitCostPesos
        suggestedUnitPesos = nil
    }

    var classification: LotClassifier.Classification {
        guard let unitCostPesos else { return LotClassifier.Classification(source: .unknown, unitCost: nil) }
        return unitCostPesos > 0
            ? LotClassifier.Classification(source: .purchased, unitCost: Money(pesos: unitCostPesos))
            : LotClassifier.Classification(source: .free, unitCost: .zero)
    }
}

/// Importación directa desde Natura (M3 de docs/local-first-migration.md): sin backend.
extension LocalStore {
    static let materialPattern = "revista|catalog|cat[aá]logo|carta"

    /// Trae todos los pedidos entregados (Excel del pedido; HTML de respaldo), el ciclo vigente y el catálogo del ciclo.
    /// Antes de "Agregar inventario actual", lo importado entra como recibido; después, los pedidos nuevos quedan
    /// pendientes de recepción. La contraseña se usa solo durante la importación.
    public func importFromNatura(sellerId: String, customerCode: String, password: String,
                                 progress: @escaping @MainActor (String) -> Void) async -> Result<String, ActionError> {
        guard connectivity.isOnline else { return .failure(ActionError("Necesitas conexión para importar desde Natura.")) }
        let client = NaturaClient()
        do {
            progress("Conectando con Natura…")
            try await client.login(customerCode: customerCode, password: password)
            startNaturaDirectIfNeeded(sellerId: sellerId)

            progress("Leyendo tus pedidos…")
            let delivered = try await client.orders().filter(\.isDelivered)
            let known = Set(fetchAll(FetchDescriptor<NaturaOrder>(predicate: #Predicate { $0.sellerId == sellerId })).map(\.id))
            let pending = delivered.filter { !known.contains($0.id) }
            var importedLines = 0
            var fromHTML = 0
            for (index, order) in pending.enumerated() {
                progress("Pedido \(index + 1) de \(pending.count) · \(order.orderNumber)")
                let lines: [ImportedLine]
                if let report = try await client.orderReport(for: order) {
                    lines = report.lines.map(ImportedLine.init(report:))
                } else {
                    lines = try await client.orderItems(for: order).map(ImportedLine.init(item:))
                    fromHTML += 1
                }
                storeImportedOrder(order, lines: lines, sellerId: sellerId)
                importedLines += lines.count
                save()
            }

            var notes: [String] = []
            do {
                progress("Leyendo tu cuenta…")
                storeAccount(sellerId: sellerId, documents: try await client.accounts())
            } catch {
                let detail = (error as? NaturaError)?.message ?? error.localizedDescription
                notes.append("cuenta no disponible (\(detail))")
            }
            do {
                progress("Leyendo el ciclo y su catálogo…")
                try await client.openGsp()
                storeAccount(sellerId: sellerId, credit: await client.credit)
                let current = settings(sellerId: sellerId)
                if let cycle = try await client.currentCycle() {
                    current.currentCycleCode = cycle.code
                    current.currentCycleStart = cycle.start
                    current.currentCycleEnd = cycle.end
                } else if let code = try await client.homeCycle() {
                    current.currentCycleCode = code
                }
                if let code = current.currentCycleCode {
                    let items = try await client.cycleCatalog(cycle: code)
                    mergeCycleCatalog(items, cycle: code, sellerId: sellerId)
                    notes.append("\(items.count) productos en el catálogo del ciclo")
                }
            } catch {
                let detail = (error as? NaturaError)?.message ?? error.localizedDescription
                notes.append("catálogo del ciclo no disponible (\(detail))")
            }

            var summary = pending.isEmpty
                ? "Sin pedidos nuevos."
                : "Importados \(pending.count) pedido(s) y \(importedLines) línea(s)."
            if fromHTML > 0 { summary += " \(fromHTML) sin Excel (leídos de la página)." }
            if !notes.isEmpty { summary += " Además: " + notes.joined(separator: "; ") + "." }
            let current = settings(sellerId: sellerId)
            current.lastNaturaImportAt = .now
            current.lastNaturaImportSummary = summary
            save()
            return .success(summary)
        } catch let error as NaturaError {
            save()
            if case .credentials = error { return .failure(ActionError(error.message, isCredentialError: true)) }
            return .failure(ActionError(error.message))
        } catch {
            save()
            return .failure(ActionError("No se pudo importar desde Natura: \(error.localizedDescription)"))
        }
    }

    /// Solo cuenta, crédito y ciclo (M6), sin pedidos ni catálogo: más rápido que la importación completa.
    public func refreshNaturaAccount(sellerId: String, customerCode: String, password: String) async -> Result<String, ActionError> {
        guard connectivity.isOnline else { return .failure(ActionError("Necesitas conexión para leer tu cuenta Natura.")) }
        let client = NaturaClient()
        do {
            try await client.login(customerCode: customerCode, password: password)
            var notes: [String] = []
            do {
                storeAccount(sellerId: sellerId, documents: try await client.accounts())
            } catch {
                notes.append("pagos no disponibles (\((error as? NaturaError)?.message ?? error.localizedDescription))")
            }
            do {
                try await client.openGsp()
                storeAccount(sellerId: sellerId, credit: await client.credit)
                if let cycle = try await client.currentCycle() {
                    let current = settings(sellerId: sellerId)
                    current.currentCycleCode = cycle.code
                    current.currentCycleStart = cycle.start
                    current.currentCycleEnd = cycle.end
                }
            } catch {
                notes.append("crédito y ciclo no disponibles (\((error as? NaturaError)?.message ?? error.localizedDescription))")
            }
            save()
            return .success(notes.isEmpty ? "Cuenta actualizada." : "Cuenta actualizada, pero: " + notes.joined(separator: "; ") + ".")
        } catch let error as NaturaError {
            if case .credentials = error { return .failure(ActionError(error.message, isCredentialError: true)) }
            return .failure(ActionError(error.message))
        } catch {
            return .failure(ActionError("No se pudo leer la cuenta: \(error.localizedDescription)"))
        }
    }

    func storeAccount(sellerId: String, documents: [NaturaAccountDocument]? = nil, credit: NaturaCredit? = nil) {
        let snapshot: NaturaAccountSnapshot
        if let existing = fetchAll(FetchDescriptor<NaturaAccountSnapshot>(predicate: #Predicate { $0.sellerId == sellerId })).first {
            snapshot = existing
        } else {
            snapshot = NaturaAccountSnapshot(sellerId: sellerId)
            context.insert(snapshot)
        }
        snapshot.fetchedAt = .now
        if let documents { snapshot.documents = documents }
        if let credit { snapshot.credit = credit }
        save()
    }

    /// La primera vez que se importa directo: se borra lo bajado del backend (pedidos, líneas, lotes, stock, kardex,
    /// cola). Quedan productos (por SKU), clientes, pedidos de clientes y ventas registradas en el iPhone.
    func startNaturaDirectIfNeeded(sellerId: String) {
        let current = settings(sellerId: sellerId)
        guard current.naturaDirectSince == nil else { return }
        for order in fetchAll(FetchDescriptor<NaturaOrder>(predicate: #Predicate { $0.sellerId == sellerId })) { context.delete(order) }
        for line in fetchAll(FetchDescriptor<NaturaOrderLine>(predicate: #Predicate { $0.sellerId == sellerId })) { context.delete(line) }
        for lot in fetchAll(FetchDescriptor<InventoryLotRecord>(predicate: #Predicate { $0.sellerId == sellerId })) { context.delete(lot) }
        for item in fetchAll(FetchDescriptor<StockItem>(predicate: #Predicate { $0.sellerId == sellerId })) { context.delete(item) }
        for event in fetchAll(FetchDescriptor<InventoryEventRecord>(predicate: #Predicate { $0.sellerId == sellerId })) { context.delete(event) }
        clearLegacyQueue(sellerId: sellerId)
        current.naturaDirectSince = .now
        current.initialInventoryAt = nil
        if current.localInventoryAdoptedAt == nil { current.localInventoryAdoptedAt = .now }
        save()
    }

    func storeImportedOrder(_ summary: NaturaOrderSummary, lines: [ImportedLine], sellerId: String) {
        let historical = settings(sellerId: sellerId).initialInventoryAt == nil
        let orderedAt = summary.orderedAt ?? .now
        let order = NaturaOrder(id: summary.id, sellerId: sellerId, orderNumber: summary.orderNumber,
                                cycle: summary.cycleCode, orderedAt: orderedAt)
        order.subCycle = summary.subCycle
        order.deliveredAt = summary.deliveredAt
        order.statusName = summary.status.name
        order.itemsQuantity = lines.reduce(0) { $0 + $1.quantity }
        order.totalValuePesos = summary.totalPesos ?? 0
        order.linesLoaded = true
        order.reviewStatus = historical ? .closed : .draft
        order.receivingClosedAt = historical ? orderedAt : nil
        context.insert(order)

        let receivedAt = summary.deliveredAt ?? orderedAt
        for (index, imported) in lines.enumerated() {
            let product = productForImport(imported, sellerId: sellerId)
            let line = NaturaOrderLine(id: "\(summary.id)|\(index + 1)", orderId: summary.id, sellerId: sellerId, position: index,
                                       naturaSku: imported.sku, productName: imported.name, quantity: imported.quantity)
            line.purchasePesos = imported.unitCostPesos
            line.suggestedPesos = imported.suggestedUnitPesos
            context.insert(line)
            if let suggested = imported.suggestedUnitPesos, suggested > 0 { product.lastSuggestedSalePesos = suggested }
            guard historical, imported.quantity > 0 else { continue }
            line.receivedQuantity = imported.quantity
            line.receivedConfirmedAt = receivedAt
            let classification = imported.classification
            addLot(sellerId: sellerId, productId: product.id, quantity: imported.quantity, unitCost: classification.unitCost,
                   source: classification.source, origin: .naturaLine, naturaOrderLineId: line.id,
                   note: "Pedido \(summary.orderNumber)", receivedAt: receivedAt, suggestedPesos: imported.suggestedUnitPesos)
            addEvent(sellerId: sellerId, productId: product.id, kind: .receipt, quantity: imported.quantity,
                     note: "Pedido \(summary.orderNumber)", occurredAt: receivedAt)
        }
        recomputeTotals(order)
    }

    /// Producto por SKU (los pedidos mandan): si no existe, se crea desde la línea.
    func productForImport(_ line: ImportedLine, sellerId: String) -> CatalogProduct {
        if let existing = product(sku: line.sku, sellerId: sellerId) {
            if existing.source == .catalog { existing.sourceRaw = ProductSource.orderImport.rawValue }
            if existing.brand == nil { existing.brand = line.brand }
            return existing
        }
        let isMaterial = line.name.range(of: Self.materialPattern, options: [.regularExpression, .caseInsensitive]) != nil
        let created = CatalogProduct(
            id: "natura-\(Normalize.naturaSku(line.sku).lowercased())", sellerId: sellerId, naturaSku: line.sku, name: line.name,
            source: .orderImport, isSellable: !isMaterial && LotClassifier.isSellableByDefault(firstSource: line.classification.source),
            lastPurchasePesos: 0, lastSuggestedSalePesos: line.suggestedUnitPesos, barcodes: [])
        created.brand = line.brand
        context.insert(created)
        return created
    }

    /// Catálogo del ciclo (GSP): actualiza categoría y precios del ciclo; agrega lo que nunca se pidió (sin stock).
    func mergeCycleCatalog(_ items: [CycleCatalogItem], cycle: Int, sellerId: String) {
        for item in items {
            let product: CatalogProduct
            if let existing = self.product(sku: item.sku, sellerId: sellerId) {
                product = existing
            } else {
                product = CatalogProduct(
                    id: "natura-\(Normalize.naturaSku(item.sku).lowercased())", sellerId: sellerId, naturaSku: item.sku, name: item.name,
                    source: .catalog, isSellable: true, lastPurchasePesos: 0, lastSuggestedSalePesos: item.resalePesos, barcodes: [])
                context.insert(product)
            }
            product.category = item.category
            product.brand = product.brand ?? item.brand
            product.imageURL = item.imageURL ?? product.imageURL
            product.cycleCode = cycle
            product.cyclePurchasePesos = item.purchasePesos
            product.cycleResalePesos = item.resalePesos
            product.cyclePoints = item.points
            product.cycleRegularPurchasePesos = item.regularPurchasePesos
            product.cycleRegularResalePesos = item.regularResalePesos
            product.cycleDiscountPercent = item.discountPercent
            product.cycleOfferText = item.offerText
            if product.lastSuggestedSalePesos == nil { product.lastSuggestedSalePesos = item.resalePesos }
        }
        save()
    }

    // MARK: - Agregar inventario actual (una vez)

    public func needsInitialInventory(sellerId: String) -> Bool {
        let current = settings(sellerId: sellerId)
        return current.naturaDirectSince != nil && current.initialInventoryAt == nil
    }

    /// Lo contado pasa a ser el stock. La diferencia con lo comprado son **ventas previas**: salen con FIFO (siempre,
    /// esta primera vez) y su ingreso se estima con el precio sugerido de cada lote. Si se cuenta más de lo comprado,
    /// entra un lote al último costo conocido. Desde aquí, los pedidos nuevos quedan pendientes de recepción.
    public func setInitialInventory(sellerId: String, counts: [String: Int]) -> Result<String, ActionError> {
        let current = settings(sellerId: sellerId)
        guard current.initialInventoryAt == nil else { return .failure(ActionError("El inventario inicial ya se registró.")) }
        let lots = fetchAll(FetchDescriptor<InventoryLotRecord>(predicate: #Predicate { $0.sellerId == sellerId }))
        let productIds = Set(lots.map(\.productId)).union(counts.filter { $0.value > 0 }.keys)
        var priorLines: [SaleLineSnapshot] = []
        var priorUnits = 0
        var added = 0

        for productId in productIds.sorted() {
            guard let product = product(id: productId) else { continue }
            let records = lotRecords(productId: productId)
            let available = records.reduce(0) { $0 + max($1.remaining, 0) }
            let counted = max(counts[productId] ?? 0, 0)
            if available > counted {
                let difference = available - counted
                let result = CostingEngine.consume(difference, from: records.map(\.lot), method: .fifo)
                let remaining = Dictionary(result.lots.map { ($0.id, $0.remaining) }, uniquingKeysWith: { first, _ in first })
                let suggestedByLot = Dictionary(records.map { ($0.id, $0.suggestedPesos ?? product.lastSuggestedSalePesos ?? 0) },
                                                uniquingKeysWith: { first, _ in first })
                for record in records { if let value = remaining[record.id] { record.remaining = value } }
                let revenue = result.allocations.reduce(0) { $0 + (suggestedByLot[$1.lotId] ?? 0) * $1.quantity }
                priorLines.append(SaleLineSnapshot(
                    sellerProductId: product.id, productName: product.name, naturaSku: product.naturaSku, quantity: difference,
                    suggestedPesos: product.lastSuggestedSalePesos,
                    finalPesos: Int((Double(revenue) / Double(difference)).rounded()), reasonCode: nil, reasonNote: nil,
                    costUnitPesos: Self.unitCost(of: result.allocations, quantity: difference), costAllocations: result.allocations))
                priorUnits += difference
                addEvent(sellerId: sellerId, productId: product.id, kind: .sale, quantity: -difference, note: "Ventas previas")
            } else if counted > available {
                let cost = product.lastPurchasePesos > 0 ? product.lastPurchasePesos : (product.cyclePurchasePesos ?? 0)
                addLot(sellerId: sellerId, productId: product.id, quantity: counted - available,
                       unitCost: cost > 0 ? Money(pesos: cost) : nil, source: cost > 0 ? .manual : .unknown,
                       origin: .opening, note: "Inventario inicial", suggestedPesos: product.lastSuggestedSalePesos)
                added += counted - available
                addEvent(sellerId: sellerId, productId: product.id, kind: .reconciliation, quantity: counted - available,
                         note: "Inventario inicial")
            }
            refreshStock(productId: product.id, sellerId: sellerId)
            stockItem(productId: product.id)?.lastReconciledAt = .now
        }

        if !priorLines.isEmpty {
            context.insert(LocalSale(id: UUID().uuidString.lowercased(), sellerId: sellerId, occurredAt: .now,
                                     note: "Ventas previas al uso de la app (estimadas al precio sugerido)",
                                     customerId: nil, customerName: nil, lines: priorLines, syncState: .synced, kind: .priorSales))
        }
        current.initialInventoryAt = .now
        save()
        var summary = "Inventario registrado."
        if priorUnits > 0 { summary += " \(priorUnits) unidad(es) quedaron como ventas previas." }
        if added > 0 { summary += " \(added) unidad(es) agregadas sin pedido." }
        return .success(summary)
    }
}
