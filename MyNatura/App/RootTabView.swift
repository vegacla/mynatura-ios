import Core
import Features
import Persistence
import Sync
import SwiftData
import SwiftUI

/// Navegación raíz: 5 pestañas (§3). Ajustes muestra badge con mutaciones fallidas y cuando toca respaldar (M5).
struct RootTabView: View {
    @Environment(AppRouter.self) private var router
    @Environment(SyncEngine.self) private var sync
    @Query private var mutations: [PendingMutation]
    @Query private var settings: [SellerSettings]
    @State private var voiceLaunch: VoiceLaunch?
    let sellerId: String

    init(sellerId: String) {
        self.sellerId = sellerId
        _mutations = Query(filter: #Predicate<PendingMutation> { $0.sellerId == sellerId })
        _settings = Query(filter: #Predicate<SellerSettings> { $0.sellerId == sellerId })
    }

    var body: some View {
        @Bindable var router = router
        let failed = mutations.filter { $0.statusRaw == "failed" }.count
        let backupDue = BackupReminder.isDue(lastBackupAt: settings.first?.lastBackupAt,
                                             hasData: sync.hasBackupableData(sellerId: sellerId), now: .now)
        TabView(selection: $router.tab) {
            SellScreen(sellerId: sellerId)
                .tabItem { Label("Vender", systemImage: "cart") }
                .tag(AppTab.sell)

            ProductsScreen(sellerId: sellerId)
                .tabItem { Label("Productos", systemImage: "shippingbox") }
                .tag(AppTab.products)

            ReceivingScreen(sellerId: sellerId)
                .tabItem { Label("Recepción", systemImage: "tray.and.arrow.down") }
                .tag(AppTab.receiving)

            CustomersHomeScreen(sellerId: sellerId)
                .tabItem { Label("Clientes", systemImage: "person.2") }
                .tag(AppTab.customers)

            SettingsScreen(sellerId: sellerId)
                .tabItem { Label("Ajustes", systemImage: "gearshape") }
                .badge(failed + (backupDue ? 1 : 0))
                .tag(AppTab.settings)
        }
        // Atajos de Siri (V7): abren la acción de voz pedida, ya con sesión iniciada.
        .onAppear {
            consumePendingVoice()
            // Inventario local (M2): si el stock ya se bajó alguna vez, pasa a lotes locales.
            sync.adoptLocalInventoryIfNeeded(sellerId: sellerId)
        }
        .onChange(of: router.pendingVoice) { _, _ in consumePendingVoice() }
        .sheet(item: $voiceLaunch) { launch in
            VoiceLaunchSheet(launch: launch, sellerId: sellerId)
                .presentationDetents([.newCustomerOrder, .productPhoto].contains(launch) ? [.large] : [.medium, .large])
        }
    }

    private func consumePendingVoice() {
        guard let pending = router.pendingVoice else { return }
        router.pendingVoice = nil
        voiceLaunch = pending
    }
}
