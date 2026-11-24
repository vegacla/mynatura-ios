import SwiftUI

/// Navegación raíz: 5 pestañas (ver docs/ios-app-design.md §3).
struct RootTabView: View {
    var body: some View {
        TabView {
            PlaceholderScreen(title: "Vender", systemImage: "cart",
                              message: "Venta rápida con carro y escáner EAN.")
                .tabItem { Label("Vender", systemImage: "cart") }

            PlaceholderScreen(title: "Productos", systemImage: "shippingbox",
                              message: "Catálogo visible, EAN, conciliación y kardex.")
                .tabItem { Label("Productos", systemImage: "shippingbox") }

            PlaceholderScreen(title: "Recepción", systemImage: "tray.and.arrow.down",
                              message: "Pedidos Natura entregados: por línea, por código y OCR.")
                .tabItem { Label("Recepción", systemImage: "tray.and.arrow.down") }

            PlaceholderScreen(title: "Clientes", systemImage: "person.2",
                              message: "Clientes y pedidos por ciclo.")
                .tabItem { Label("Clientes", systemImage: "person.2") }

            SettingsScreen()
                .tabItem { Label("Ajustes", systemImage: "gearshape") }
        }
    }
}

struct PlaceholderScreen: View {
    let title: String
    let systemImage: String
    let message: String

    var body: some View {
        NavigationStack {
            ContentUnavailableView(title, systemImage: systemImage, description: Text(message))
                .navigationTitle(title)
        }
    }
}
