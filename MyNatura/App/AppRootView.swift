import Features
import SwiftUI

/// La app abre directo en las pestañas con el perfil local (M7: sin login).
struct AppRootView: View {
    @Environment(AppProfile.self) private var profile

    var body: some View {
        RootTabView(sellerId: profile.sellerId)
            .id(profile.sellerId)
    }
}
