import Foundation
import SwiftData

public enum PersistenceController {
    /// Todos los modelos de la app. Agregar aquí cada @Model nuevo.
    public static var schema: Schema {
        Schema([
            SessionSummary.self,
            SellerSettings.self,
            CatalogProduct.self,
            StockItem.self,
            DatasetSyncState.self,
            PricingReasonRecord.self,
            CartDraft.self,
            CartDraftLine.self,
            LocalSale.self,
            PendingMutation.self,
            InventoryEventRecord.self,
            NaturaOrder.self,
            NaturaOrderLine.self,
            Customer.self,
            CustomerOrder.self,
        ])
    }

    /// Contenedor en Application Support/MyNatura con protección
    /// `completeUntilFirstUserAuthentication` (permite sync en background tras el primer desbloqueo).
    public static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        if inMemory {
            return try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        }
        let directory = URL.applicationSupportDirectory.appending(path: "MyNatura", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
        )
        let configuration = ModelConfiguration(schema: schema, url: directory.appending(path: "MyNatura.store"))
        return try ModelContainer(for: schema, configurations: configuration)
    }

    /// Borra todos los datos locales (logout). Una sola cuenta activa por dispositivo.
    @MainActor
    public static func deleteAllData(in context: ModelContext) throws {
        try context.delete(model: SessionSummary.self)
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
        try context.delete(model: NaturaOrder.self)
        try context.delete(model: NaturaOrderLine.self)
        try context.delete(model: Customer.self)
        try context.delete(model: CustomerOrder.self)
        try context.save()
    }
}
