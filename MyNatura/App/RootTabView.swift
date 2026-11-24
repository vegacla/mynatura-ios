import Features
import Persistence
import SwiftData
import SwiftUI

/// Navegación raíz: 5 pestañas (§3). Ajustes muestra badge con mutaciones fallidas.
struct RootTabView: View {
    @Environment(AppRouter.self) private var router
    @Query private var mutations: [PendingMutation]
    let sellerId: String

    init(sellerId: String) {
        self.sellerId = sellerId
        _mutations = Query(filter: #Predicate<PendingMutation> { $0.sellerId == sellerId })
    }

    var body: some View {
        @Bindable var router = router
        let failed = mutations.filter { $0.statusRaw == "failed" }.count
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
                .badge(failed)
                .tag(AppTab.settings)
        }
    }
}
