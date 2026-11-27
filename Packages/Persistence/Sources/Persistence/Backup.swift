import Core
import Foundation
import SwiftData

/// Respaldo JSON versionado de todos los datos de la consultora (docs/local-first-migration.md §6).
/// No incluye credenciales, la sesión de la app, la cola de sincronización ni el carro en curso.
public struct BackupFile: Codable, Sendable, Equatable {
    public static let formatName = "mynatura-backup"
    public static let currentVersion = 1

    public var format: String
    public var version: Int
    public var exportedAt: Date
    public var appVersion: String?
    public var settings: Settings?
    public var products: [Product]
    public var stock: [Stock]
    public var lots: [Lot]
    public var events: [Event]
    public var sales: [Sale]
    public var customers: [Customer]
    public var customerOrders: [CustomerOrder]
    public var naturaOrders: [NaturaOrder]
    public var naturaLines: [NaturaLine]
    public var pricingReasons: [PricingReason]

    public var counts: BackupCounts {
        BackupCounts(products: products.count, lots: lots.count, sales: sales.count, customers: customers.count,
                     customerOrders: customerOrders.count, naturaOrders: naturaOrders.count,
                     naturaLines: naturaLines.count, events: events.count)
    }
}

public struct BackupCounts: Sendable, Equatable {
    public let products: Int
    public let lots: Int
    public let sales: Int
    public let customers: Int
    public let customerOrders: Int
    public let naturaOrders: Int
    public let naturaLines: Int
    public let events: Int

    /// Filas para la vista previa (es-CL).
    public var summaryLines: [(label: String, value: Int)] {
        [("Productos", products), ("Lotes de inventario", lots), ("Ventas y obsequios", sales),
         ("Clientes", customers), ("Pedidos de clientes", customerOrders), ("Pedidos Natura", naturaOrders),
         ("Líneas de pedidos Natura", naturaLines), ("Movimientos (kardex)", events)]
    }

    public var isEmpty: Bool {
        products + lots + sales + customers + customerOrders + naturaOrders + naturaLines + events == 0
    }
}

public enum BackupError: Error, Equatable, Sendable {
    case notABackup
    case newerVersion(Int)
    case unreadable(String)

    public var message: String {
        switch self {
        case .notABackup: "El archivo no es un respaldo de MyNatura."
        case .newerVersion(let version):
            "El respaldo es de una versión más nueva de la app (formato \(version)). Actualiza la app e inténtalo de nuevo."
        case .unreadable(let detail): "No se pudo leer el respaldo: \(detail)"
        }
    }
}

// MARK: - Registros

extension BackupFile {
    public struct Settings: Codable, Sendable, Equatable {
        var issueStrategyRaw: String
        var costingMethodRaw: String?
        var localInventoryAdoptedAt: Date?
        var naturaDirectSince: Date?
        var initialInventoryAt: Date?
        var lastNaturaImportAt: Date?
        var lastNaturaImportSummary: String?
        var currentCycleCode: Int?
        var currentCycleStart: Date?
        var currentCycleEnd: Date?
    }

    public struct Product: Codable, Sendable, Equatable {
        var id: String
        var naturaSku: String
        var name: String
        var sourceRaw: String
        var isSellable: Bool
        var lastPurchasePesos: Int
        var lastSuggestedSalePesos: Int?
        var barcodes: [String]
        var category: String?
        var brand: String?
        var imageURL: String?
        var cycleCode: Int?
        var cyclePurchasePesos: Int?
        var cycleResalePesos: Int?
        var cyclePoints: Int?
        var cycleRegularPurchasePesos: Int?
        var cycleRegularResalePesos: Int?
        var cycleDiscountPercent: Int?
        var cycleOfferText: String?
    }

    public struct Stock: Codable, Sendable, Equatable {
        var sellerProductId: String
        var naturaSku: String
        var name: String
        var isSellable: Bool
        var theoreticalQuantity: Int
        var operationalQuantity: Int
        var lastReconciledAt: Date?
    }

    public struct Lot: Codable, Sendable, Equatable {
        var id: String
        var productId: String
        var receivedAt: Date
        var quantity: Int
        var remaining: Int
        var unitCostPesos: Int?
        var sourceRaw: String
        var originRaw: String
        var naturaOrderLineId: String?
        var note: String?
        var suggestedPesos: Int?
    }

    public struct Event: Codable, Sendable, Equatable {
        var id: String
        var sellerProductId: String
        var kindRaw: String
        var quantity: Int
        var note: String?
        var occurredAt: Date
    }

    public struct Sale: Codable, Sendable, Equatable {
        var id: String
        var occurredAt: Date
        var note: String?
        var customerId: String?
        var customerName: String?
        var kindRaw: String
        var lines: [SaleLineSnapshot]
    }

    public struct Customer: Codable, Sendable, Equatable {
        var id: String
        var displayName: String
        var rut: String?
        var phone: String?
        var notes: String?
        var updatedAt: Date
    }

    public struct CustomerOrder: Codable, Sendable, Equatable {
        var id: String
        var customerId: String
        var customerDisplayName: String
        var cycle: Int
        var statusRaw: String
        var note: String?
        var orderedAt: Date
        var updatedAt: Date
        var lineCount: Int
        var lines: [CustomerOrderLineSnapshot]?
    }

    public struct NaturaOrder: Codable, Sendable, Equatable {
        var id: String
        var orderNumber: String
        var cycle: Int
        var subCycle: String?
        var orderedAt: Date
        var deliveredAt: Date?
        var statusName: String
        var itemsQuantity: Int
        var totalValuePesos: Int
        var receivingClosedAt: Date?
        var reviewStatusRaw: String
        var receivedUnits: Int
        var pendingUnits: Int
        var linesLoaded: Bool
    }

    public struct NaturaLine: Codable, Sendable, Equatable {
        var id: String
        var orderId: String
        var position: Int
        var naturaSku: String
        var productName: String
        var quantity: Int
        var purchasePesos: Int?
        var suggestedPesos: Int?
        var receivedQuantity: Int
        var receivedConfirmedAt: Date?
        var barcodes: [String]
    }

    public struct PricingReason: Codable, Sendable, Equatable {
        var code: String
        var label: String
        var categoryRaw: String
    }
}

// MARK: - Exportar y restaurar

@MainActor
public enum BackupService {
    /// Arma el respaldo de la cuenta. Todo lo local queda "sincronizado": no hay servidor al que enviarlo.
    public static func makeBackup(context: ModelContext, sellerId: String, appVersion: String? = nil,
                                  now: Date = .now) throws -> BackupFile {
        func all<T: PersistentModel>(_ descriptor: FetchDescriptor<T>) throws -> [T] { try context.fetch(descriptor) }
        let settings = try all(FetchDescriptor<SellerSettings>(predicate: #Predicate { $0.sellerId == sellerId })).first
        return BackupFile(
            format: BackupFile.formatName, version: BackupFile.currentVersion, exportedAt: now, appVersion: appVersion,
            settings: settings.map {
                BackupFile.Settings(issueStrategyRaw: $0.issueStrategyRaw, costingMethodRaw: $0.costingMethodRaw,
                                    localInventoryAdoptedAt: $0.localInventoryAdoptedAt, naturaDirectSince: $0.naturaDirectSince,
                                    initialInventoryAt: $0.initialInventoryAt, lastNaturaImportAt: $0.lastNaturaImportAt,
                                    lastNaturaImportSummary: $0.lastNaturaImportSummary, currentCycleCode: $0.currentCycleCode,
                                    currentCycleStart: $0.currentCycleStart, currentCycleEnd: $0.currentCycleEnd)
            },
            products: try all(FetchDescriptor<CatalogProduct>(predicate: #Predicate { $0.sellerId == sellerId },
                                                              sortBy: [SortDescriptor(\.naturaSku)])).map {
                BackupFile.Product(id: $0.id, naturaSku: $0.naturaSku, name: $0.name, sourceRaw: $0.sourceRaw,
                                   isSellable: $0.isSellable, lastPurchasePesos: $0.lastPurchasePesos,
                                   lastSuggestedSalePesos: $0.lastSuggestedSalePesos, barcodes: $0.barcodes,
                                   category: $0.category, brand: $0.brand, imageURL: $0.imageURL, cycleCode: $0.cycleCode,
                                   cyclePurchasePesos: $0.cyclePurchasePesos, cycleResalePesos: $0.cycleResalePesos,
                                   cyclePoints: $0.cyclePoints, cycleRegularPurchasePesos: $0.cycleRegularPurchasePesos,
                                   cycleRegularResalePesos: $0.cycleRegularResalePesos,
                                   cycleDiscountPercent: $0.cycleDiscountPercent, cycleOfferText: $0.cycleOfferText)
            },
            stock: try all(FetchDescriptor<StockItem>(predicate: #Predicate { $0.sellerId == sellerId })).map {
                BackupFile.Stock(sellerProductId: $0.sellerProductId, naturaSku: $0.naturaSku, name: $0.name,
                                 isSellable: $0.isSellable, theoreticalQuantity: $0.theoreticalQuantity,
                                 operationalQuantity: $0.operationalQuantity, lastReconciledAt: $0.lastReconciledAt)
            },
            lots: try all(FetchDescriptor<InventoryLotRecord>(predicate: #Predicate { $0.sellerId == sellerId },
                                                              sortBy: [SortDescriptor(\.receivedAt)])).map {
                BackupFile.Lot(id: $0.id, productId: $0.productId, receivedAt: $0.receivedAt, quantity: $0.quantity,
                               remaining: $0.remaining, unitCostPesos: $0.unitCostPesos, sourceRaw: $0.sourceRaw,
                               originRaw: $0.originRaw, naturaOrderLineId: $0.naturaOrderLineId, note: $0.note,
                               suggestedPesos: $0.suggestedPesos)
            },
            events: try all(FetchDescriptor<InventoryEventRecord>(predicate: #Predicate { $0.sellerId == sellerId },
                                                                  sortBy: [SortDescriptor(\.occurredAt)])).map {
                BackupFile.Event(id: $0.id, sellerProductId: $0.sellerProductId, kindRaw: $0.kindRaw,
                                 quantity: $0.quantity, note: $0.note, occurredAt: $0.occurredAt)
            },
            sales: try all(FetchDescriptor<LocalSale>(predicate: #Predicate { $0.sellerId == sellerId },
                                                      sortBy: [SortDescriptor(\.occurredAt)])).map {
                BackupFile.Sale(id: $0.id, occurredAt: $0.occurredAt, note: $0.note, customerId: $0.customerId,
                                customerName: $0.customerName, kindRaw: $0.kindRaw, lines: $0.lines)
            },
            customers: try all(FetchDescriptor<Persistence.Customer>(predicate: #Predicate { $0.sellerId == sellerId },
                                                                     sortBy: [SortDescriptor(\.normalizedName)])).map {
                BackupFile.Customer(id: $0.id, displayName: $0.displayName, rut: $0.rut, phone: $0.phone,
                                    notes: $0.notes, updatedAt: $0.updatedAt)
            },
            customerOrders: try all(FetchDescriptor<Persistence.CustomerOrder>(predicate: #Predicate { $0.sellerId == sellerId },
                                                                               sortBy: [SortDescriptor(\.orderedAt)])).map {
                BackupFile.CustomerOrder(id: $0.id, customerId: $0.customerId, customerDisplayName: $0.customerDisplayName,
                                         cycle: $0.cycle, statusRaw: $0.statusRaw, note: $0.note, orderedAt: $0.orderedAt,
                                         updatedAt: $0.updatedAt, lineCount: $0.lineCount, lines: $0.lines)
            },
            naturaOrders: try all(FetchDescriptor<Persistence.NaturaOrder>(predicate: #Predicate { $0.sellerId == sellerId },
                                                                           sortBy: [SortDescriptor(\.orderedAt)])).map {
                BackupFile.NaturaOrder(id: $0.id, orderNumber: $0.orderNumber, cycle: $0.cycle, subCycle: $0.subCycle,
                                       orderedAt: $0.orderedAt, deliveredAt: $0.deliveredAt, statusName: $0.statusName,
                                       itemsQuantity: $0.itemsQuantity, totalValuePesos: $0.totalValuePesos,
                                       receivingClosedAt: $0.receivingClosedAt, reviewStatusRaw: $0.reviewStatusRaw,
                                       receivedUnits: $0.receivedUnits, pendingUnits: $0.pendingUnits,
                                       linesLoaded: $0.linesLoaded)
            },
            naturaLines: try all(FetchDescriptor<NaturaOrderLine>(predicate: #Predicate { $0.sellerId == sellerId },
                                                                  sortBy: [SortDescriptor(\.orderId), SortDescriptor(\.position)])).map {
                BackupFile.NaturaLine(id: $0.id, orderId: $0.orderId, position: $0.position, naturaSku: $0.naturaSku,
                                      productName: $0.productName, quantity: $0.quantity, purchasePesos: $0.purchasePesos,
                                      suggestedPesos: $0.suggestedPesos, receivedQuantity: $0.receivedQuantity,
                                      receivedConfirmedAt: $0.receivedConfirmedAt, barcodes: $0.barcodes)
            },
            pricingReasons: try all(FetchDescriptor<PricingReasonRecord>(sortBy: [SortDescriptor(\.code)])).map {
                BackupFile.PricingReason(code: $0.code, label: $0.label, categoryRaw: $0.categoryRaw)
            }
        )
    }

    public static func encode(_ backup: BackupFile) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(isoFormatter(fractional: true).string(from: date))
        }
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(backup)
    }

    public static func decode(_ data: Data) throws(BackupError) -> BackupFile {
        struct Header: Decodable { let format: String?; let version: Int? }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            guard let date = isoFormatter(fractional: true).date(from: text) ?? isoFormatter(fractional: false).date(from: text)
            else { throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Fecha inválida: \(text)")) }
            return date
        }
        guard let header = try? decoder.decode(Header.self, from: data), header.format == BackupFile.formatName,
              let version = header.version else { throw .notABackup }
        guard version <= BackupFile.currentVersion else { throw .newerVersion(version) }
        do {
            return try decoder.decode(BackupFile.self, from: data)
        } catch {
            throw .unreadable(String(describing: error).prefix(200).description)
        }
    }

    /// ISO 8601 con milisegundos (para no perder el orden fino de lotes y ventas); se aceptan también sin ellos.
    nonisolated static func isoFormatter(fractional: Bool) -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = fractional ? [.withInternetDateTime, .withFractionalSeconds] : [.withInternetDateTime]
        return formatter
    }

    /// Reemplaza los datos locales por los del respaldo, con el `sellerId` de la sesión actual. Conserva la sesión.
    /// Si algo falla a mitad de camino, vuelve a dejar lo que había.
    public static func restore(_ backup: BackupFile, context: ModelContext, sellerId: String) throws {
        let previous = try makeBackup(context: context, sellerId: sellerId)
        let lastBackupAt = try context.fetch(FetchDescriptor<SellerSettings>(predicate: #Predicate { $0.sellerId == sellerId }))
            .first?.lastBackupAt
        do {
            try wipe(context)
            insert(backup, into: context, sellerId: sellerId, lastBackupAt: backup.exportedAt)
            try context.save()
        } catch {
            context.rollback()
            try? wipe(context)
            insert(previous, into: context, sellerId: sellerId, lastBackupAt: lastBackupAt)
            try? context.save()
            throw error
        }
    }

    /// Todo menos la sesión de la app.
    static func wipe(_ context: ModelContext) throws {
        try context.delete(model: SellerSettings.self)
        try context.delete(model: CatalogProduct.self)
        try context.delete(model: StockItem.self)
        try context.delete(model: DatasetSyncState.self)
        try context.delete(model: PricingReasonRecord.self)
        try context.delete(model: CartDraft.self)
        try context.delete(model: CartDraftLine.self)
        try context.delete(model: LocalSale.self)
        try context.delete(model: PendingMutation.self)
        try context.delete(model: InventoryEventRecord.self)
        try context.delete(model: Persistence.NaturaOrder.self)
        try context.delete(model: NaturaOrderLine.self)
        try context.delete(model: Persistence.Customer.self)
        try context.delete(model: Persistence.CustomerOrder.self)
        try context.delete(model: InventoryLotRecord.self)
        try context.save()
    }

    static func insert(_ backup: BackupFile, into context: ModelContext, sellerId: String, lastBackupAt: Date?) {
        let settings = SellerSettings(sellerId: sellerId, issueStrategy: .fifo)
        if let saved = backup.settings {
            settings.issueStrategyRaw = saved.issueStrategyRaw
            settings.costingMethodRaw = saved.costingMethodRaw
            settings.localInventoryAdoptedAt = saved.localInventoryAdoptedAt
            settings.naturaDirectSince = saved.naturaDirectSince
            settings.initialInventoryAt = saved.initialInventoryAt
            settings.lastNaturaImportAt = saved.lastNaturaImportAt
            settings.lastNaturaImportSummary = saved.lastNaturaImportSummary
            settings.currentCycleCode = saved.currentCycleCode
            settings.currentCycleStart = saved.currentCycleStart
            settings.currentCycleEnd = saved.currentCycleEnd
        }
        settings.lastBackupAt = lastBackupAt
        context.insert(settings)

        for item in backup.products {
            let product = CatalogProduct(id: item.id, sellerId: sellerId, naturaSku: item.naturaSku, name: item.name,
                                         source: ProductSource(rawValue: item.sourceRaw) ?? .manual, isSellable: item.isSellable,
                                         lastPurchasePesos: item.lastPurchasePesos,
                                         lastSuggestedSalePesos: item.lastSuggestedSalePesos, barcodes: item.barcodes)
            product.sourceRaw = item.sourceRaw
            product.category = item.category
            product.brand = item.brand
            product.imageURL = item.imageURL
            product.cycleCode = item.cycleCode
            product.cyclePurchasePesos = item.cyclePurchasePesos
            product.cycleResalePesos = item.cycleResalePesos
            product.cyclePoints = item.cyclePoints
            product.cycleRegularPurchasePesos = item.cycleRegularPurchasePesos
            product.cycleRegularResalePesos = item.cycleRegularResalePesos
            product.cycleDiscountPercent = item.cycleDiscountPercent
            product.cycleOfferText = item.cycleOfferText
            context.insert(product)
        }
        for item in backup.stock {
            context.insert(StockItem(sellerProductId: item.sellerProductId, sellerId: sellerId, naturaSku: item.naturaSku,
                                     name: item.name, isSellable: item.isSellable, theoreticalQuantity: item.theoreticalQuantity,
                                     operationalQuantity: item.operationalQuantity, lastReconciledAt: item.lastReconciledAt))
        }
        for item in backup.lots {
            let lot = InventoryLotRecord(id: item.id, sellerId: sellerId, productId: item.productId, receivedAt: item.receivedAt,
                                         quantity: item.quantity, unitCost: item.unitCostPesos.map { Money(pesos: $0) },
                                         source: CostSource(rawValue: item.sourceRaw) ?? .unknown,
                                         origin: LotOrigin(rawValue: item.originRaw) ?? .manual,
                                         naturaOrderLineId: item.naturaOrderLineId, note: item.note,
                                         suggestedPesos: item.suggestedPesos)
            lot.remaining = item.remaining
            lot.sourceRaw = item.sourceRaw
            lot.originRaw = item.originRaw
            context.insert(lot)
        }
        for item in backup.events {
            let event = InventoryEventRecord(id: item.id, sellerId: sellerId, sellerProductId: item.sellerProductId,
                                             kind: InventoryEventKind(rawValue: item.kindRaw) ?? .receipt,
                                             quantity: item.quantity, note: item.note, occurredAt: item.occurredAt,
                                             isLocal: false)
            event.kindRaw = item.kindRaw
            context.insert(event)
        }
        for item in backup.sales {
            let sale = LocalSale(id: item.id, sellerId: sellerId, occurredAt: item.occurredAt, note: item.note,
                                 customerId: item.customerId, customerName: item.customerName, lines: item.lines,
                                 syncState: .synced)
            sale.kindRaw = item.kindRaw
            context.insert(sale)
        }
        for item in backup.customers {
            context.insert(Persistence.Customer(id: item.id, sellerId: sellerId, displayName: item.displayName, rut: item.rut,
                                                phone: item.phone, notes: item.notes, updatedAt: item.updatedAt))
        }
        for item in backup.customerOrders {
            let order = Persistence.CustomerOrder(id: item.id, sellerId: sellerId, customerId: item.customerId,
                                                  customerDisplayName: item.customerDisplayName, cycle: item.cycle,
                                                  status: CustomerOrderStatus(rawValue: item.statusRaw) ?? .draft,
                                                  note: item.note, orderedAt: item.orderedAt, updatedAt: item.updatedAt)
            order.statusRaw = item.statusRaw
            order.lines = item.lines
            order.lineCount = item.lineCount
            context.insert(order)
        }
        for item in backup.naturaOrders {
            let order = Persistence.NaturaOrder(id: item.id, sellerId: sellerId, orderNumber: item.orderNumber,
                                                cycle: item.cycle, orderedAt: item.orderedAt)
            order.subCycle = item.subCycle
            order.deliveredAt = item.deliveredAt
            order.statusName = item.statusName
            order.itemsQuantity = item.itemsQuantity
            order.totalValuePesos = item.totalValuePesos
            order.receivingClosedAt = item.receivingClosedAt
            order.reviewStatusRaw = item.reviewStatusRaw
            order.receivedUnits = item.receivedUnits
            order.pendingUnits = item.pendingUnits
            order.linesLoaded = item.linesLoaded
            context.insert(order)
        }
        for item in backup.naturaLines {
            let line = NaturaOrderLine(id: item.id, orderId: item.orderId, sellerId: sellerId, position: item.position,
                                       naturaSku: item.naturaSku, productName: item.productName, quantity: item.quantity)
            line.purchasePesos = item.purchasePesos
            line.suggestedPesos = item.suggestedPesos
            line.receivedQuantity = item.receivedQuantity
            line.receivedConfirmedAt = item.receivedConfirmedAt
            line.barcodes = item.barcodes
            context.insert(line)
        }
        for item in backup.pricingReasons {
            guard let category = PricingReasonCategory(rawValue: item.categoryRaw) else { continue }
            context.insert(PricingReasonRecord(code: item.code, label: item.label, category: category))
        }
    }
}
