import Core
import Features
import Persistence
import Store
import SwiftData
import SwiftUI

/// Navegación raíz: 5 pestañas (§3). Ajustes muestra un badge cuando toca respaldar (M5).
struct RootTabView: View {
    @Environment(AppRouter.self) private var router
    @Environment(LocalStore.self) private var store
    @Query private var settings: [SellerSettings]
    @State private var voiceLaunch: VoiceLaunch?
    let sellerId: String

    init(sellerId: String) {
        self.sellerId = sellerId
        _settings = Query(filter: #Predicate<SellerSettings> { $0.sellerId == sellerId })
    }

    var body: some View {
        @Bindable var router = router
        let backupDue = BackupReminder.isDue(lastBackupAt: settings.first?.lastBackupAt,
                                             hasData: store.hasBackupableData(sellerId: sellerId), now: .now)
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
                .badge(backupDue ? 1 : 0)
                .tag(AppTab.settings)
        }
        // Atajos de Siri (V7): abren la acción de voz pedida, ya con sesión iniciada.
        .onAppear {
            consumePendingVoice()
            // M7: descarta la cola del backend que haya quedado de versiones anteriores.
            store.finishLocalMigrationIfNeeded(sellerId: sellerId)
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
