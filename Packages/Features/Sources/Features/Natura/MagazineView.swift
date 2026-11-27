import Core
import DesignSystem
import Persistence
import SwiftData
import SwiftUI
import Store

/// Revista del ciclo (M8 etapa 1): abrir y compartir el link oficial (con el código de la consultora) y enviarla
/// por WhatsApp a cada cliente con teléfono.
struct MagazineView: View {
    @Environment(LocalStore.self) private var store
    @Environment(AppProfile.self) private var profile
    @Query private var customers: [Customer]
    let sellerId: String

    init(sellerId: String) {
        self.sellerId = sellerId
        _customers = Query(filter: #Predicate<Customer> { $0.sellerId == sellerId }, sort: \.normalizedName)
    }

    var body: some View {
        if let cycle = store.draftCycle(sellerId: sellerId),
           let url = NaturaMagazine.viewerURL(cycleCode: cycle, customerCode: profile.customerCode) {
            List {
                Section {
                    Link(destination: url) { Label("Abrir revista", systemImage: "book") }
                    ShareLink(item: url, message: Text(NaturaMagazine.shareMessage(cycleCode: cycle, url: url))) {
                        Label("Compartir revista", systemImage: "square.and.arrow.up")
                    }
                    if let pdf = NaturaMagazine.pdfURL(cycleCode: cycle) {
                        Link(destination: pdf) { Label("Revista completa en PDF (~46 MB)", systemImage: "doc.richtext") }
                    }
                } header: {
                    Text("Revista · \(CycleCode.label(cycle))")
                } footer: {
                    if profile.customerCode.isEmpty {
                        Text("Trae tus pedidos desde Ajustes › Natura para que el link lleve tu código de consultora.")
                    } else {
                        Text("El link lleva tu código de consultora: lo que tu cliente elija en la revista te llega a ti.")
                    }
                }
                let reachable = customers.filter { ($0.phone ?? "").filter(\.isNumber).count >= 8 }
                Section {
                    if reachable.isEmpty {
                        Text("Agrega el teléfono de tus clientes para enviarles la revista por WhatsApp.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    ForEach(reachable) { customer in
                        let firstName = customer.displayName.split(separator: " ").first.map(String.init)
                        if let link = NaturaMagazine.whatsAppURL(
                            phone: customer.phone ?? "",
                            text: NaturaMagazine.shareMessage(cycleCode: cycle, url: url, customerName: firstName)) {
                            Link(destination: link) {
                                Label(customer.displayName, systemImage: "paperplane")
                            }
                        }
                    }
                } header: {
                    Text("Enviar por WhatsApp")
                }
            }
        } else {
            ContentUnavailableView("Sin ciclo", systemImage: "book.closed",
                                   description: Text("Trae tus pedidos desde Ajustes › Natura para saber el ciclo vigente."))
        }
    }
}
