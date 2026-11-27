import Core
import DesignSystem
import Persistence
import SwiftData
import SwiftUI
import UIKit

/// "Mi selección del ciclo" (docs/natura-order-placement.md §6.2, nivel 2): la consultora marca productos del ciclo
/// y la app arma un PDF con foto, nombre, código y su precio de venta para mandarlo por WhatsApp.
struct SelectionPDFScreen: View {
    @Environment(AppProfile.self) private var profile
    @Query private var products: [CatalogProduct]
    @State private var selected: Set<String> = []
    @State private var onlyOffers = false
    @State private var search = ""
    @State private var building = false
    @State private var exported: SelectionFile?
    let sellerId: String
    let cycle: Int

    init(sellerId: String, cycle: Int) {
        self.sellerId = sellerId
        self.cycle = cycle
        _products = Query(filter: #Predicate<CatalogProduct> { $0.sellerId == sellerId }, sort: \.name)
    }

    var body: some View {
        let query = Normalize.customerName(search)
        let inCycle = products.filter { $0.cycleCode == cycle }
        let visible = inCycle.filter {
            (!onlyOffers || $0.hasOffer(inCycle: cycle))
                && (query.isEmpty || Normalize.customerName($0.name).contains(query) || $0.naturaSku.contains(query))
        }
        List {
            Section {
                Toggle("Solo ofertas", isOn: $onlyOffers)
                Button(selected.count == visible.count && !visible.isEmpty ? "Quitar todos" : "Marcar todos los visibles") {
                    if selected.isSuperset(of: visible.map(\.id)) {
                        selected.subtract(visible.map(\.id))
                    } else {
                        selected.formUnion(visible.map(\.id))
                    }
                }
                .disabled(visible.isEmpty)
            } footer: {
                Text("\(selected.count) seleccionado(s). El PDF muestra tu precio de venta (o el sugerido del ciclo).")
            }
            ForEach(visible.prefix(300)) { product in
                Button {
                    if selected.contains(product.id) { selected.remove(product.id) } else { selected.insert(product.id) }
                } label: {
                    HStack {
                        Image(systemName: selected.contains(product.id) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(selected.contains(product.id) ? StatusTone.success.color : Color.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(product.name).font(.subheadline).foregroundStyle(.primary).lineLimit(2)
                            HStack(spacing: 8) {
                                Text("SKU \(product.naturaSku)")
                                if let price = SelectionPDF.price(of: product) { Text(Money(pesos: price).formatted) }
                                if let offer = product.cycleOfferText { Text(offer) }
                            }
                            .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .searchable(text: $search, prompt: "Nombre o código")
        .navigationTitle("Mi selección")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if building {
                    ProgressView()
                } else {
                    Button("Crear PDF") { build(inCycle.filter { selected.contains($0.id) }) }
                        .disabled(selected.isEmpty)
                }
            }
        }
        .overlay {
            if inCycle.isEmpty {
                ContentUnavailableView("Sin catálogo del ciclo", systemImage: "square.grid.2x2",
                                       description: Text("Trae tus pedidos desde Ajustes › Natura: así se guarda el catálogo del ciclo."))
            }
        }
        .sheet(item: $exported) { file in
            ActivityView(items: [file.url]) { _ in exported = nil }
                .ignoresSafeArea()
        }
    }

    private func build(_ chosen: [CatalogProduct]) {
        building = true
        let items = chosen.map {
            SelectionPDF.Item(name: $0.name, sku: $0.naturaSku, pricePesos: SelectionPDF.price(of: $0),
                              offer: $0.cycleOfferText, imageURL: $0.imageURL.flatMap(URL.init(string:)))
        }
        let code = profile.customerCode
        Task {
            defer { building = false }
            if let url = await SelectionPDF.make(items: items, cycle: cycle, customerCode: code) {
                exported = SelectionFile(url: url)
            }
        }
    }
}

private struct SelectionFile: Identifiable {
    let url: URL
    var id: URL { url }
}

enum SelectionPDF {
    struct Item: Sendable {
        let name: String
        let sku: String
        let pricePesos: Int?
        let offer: String?
        let imageURL: URL?
    }

    /// Precio de venta propio; si no hay, el sugerido del ciclo.
    static func price(of product: CatalogProduct) -> Int? {
        product.lastSuggestedSalePesos ?? product.cycleResalePesos
    }

    /// PDF tamaño A4 con 6 productos por página. Las fotos se bajan si hay conexión; si no, va sin foto.
    static func make(items: [Item], cycle: Int, customerCode: String) async -> URL? {
        let images = await loadImages(items)
        let page = CGRect(x: 0, y: 0, width: 595, height: 842)
        let renderer = UIGraphicsPDFRenderer(bounds: page)
        let title = "Selección Natura · ciclo \(cycle % 100) de \(cycle / 100)"
        let data = renderer.pdfData { context in
            let perPage = 6
            let rowHeight: CGFloat = 110
            for start in stride(from: 0, to: max(items.count, 1), by: perPage) {
                context.beginPage()
                draw(title, at: CGPoint(x: 40, y: 36), font: .boldSystemFont(ofSize: 20))
                if !customerCode.isEmpty {
                    draw("Consultora \(customerCode)", at: CGPoint(x: 40, y: 64), font: .systemFont(ofSize: 11), color: .gray)
                }
                for (offset, item) in items[start..<min(start + perPage, items.count)].enumerated() {
                    let top = 96 + CGFloat(offset) * rowHeight
                    let imageRect = CGRect(x: 40, y: top, width: 90, height: 90)
                    if let image = images[item.sku] {
                        image.draw(in: aspectFit(image.size, in: imageRect))
                    } else {
                        UIColor.systemGray6.setFill()
                        UIBezierPath(roundedRect: imageRect, cornerRadius: 8).fill()
                    }
                    let textX: CGFloat = 145
                    let width = page.width - textX - 40
                    drawWrapped(item.name, in: CGRect(x: textX, y: top, width: width, height: 40), font: .boldSystemFont(ofSize: 13))
                    draw("Código \(item.sku)", at: CGPoint(x: textX, y: top + 44), font: .systemFont(ofSize: 12), color: .darkGray)
                    if let price = item.pricePesos {
                        draw(Money(pesos: price).formatted, at: CGPoint(x: textX, y: top + 62), font: .boldSystemFont(ofSize: 15))
                    }
                    if let offer = item.offer {
                        drawWrapped(offer, in: CGRect(x: textX + 110, y: top + 62, width: width - 110, height: 30),
                                    font: .systemFont(ofSize: 11), color: .systemPink)
                    }
                }
                draw("Responde con los códigos que quieres y te los encargo.", at: CGPoint(x: 40, y: page.height - 40),
                     font: .italicSystemFont(ofSize: 11), color: .gray)
            }
        }
        let directory = FileManager.default.temporaryDirectory.appending(path: "Seleccion", directoryHint: .isDirectory)
        try? FileManager.default.removeItem(at: directory)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appending(path: "Natura-ciclo-\(cycle % 100).pdf")
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    private static func loadImages(_ items: [Item]) async -> [String: UIImage] {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 8
        let session = URLSession(configuration: configuration)
        return await withTaskGroup(of: (String, UIImage?).self) { group in
            for item in items {
                guard let url = item.imageURL else { continue }
                group.addTask {
                    guard let (data, _) = try? await session.data(from: url) else { return (item.sku, nil) }
                    return (item.sku, UIImage(data: data))
                }
            }
            var result: [String: UIImage] = [:]
            for await (sku, image) in group { if let image { result[sku] = image } }
            return result
        }
    }

    private static func aspectFit(_ size: CGSize, in rect: CGRect) -> CGRect {
        guard size.width > 0, size.height > 0 else { return rect }
        let scale = min(rect.width / size.width, rect.height / size.height)
        let fitted = CGSize(width: size.width * scale, height: size.height * scale)
        return CGRect(x: rect.midX - fitted.width / 2, y: rect.midY - fitted.height / 2, width: fitted.width, height: fitted.height)
    }

    private static func draw(_ text: String, at point: CGPoint, font: UIFont, color: UIColor = .black) {
        (text as NSString).draw(at: point, withAttributes: [.font: font, .foregroundColor: color])
    }

    private static func drawWrapped(_ text: String, in rect: CGRect, font: UIFont, color: UIColor = .black) {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingTail
        (text as NSString).draw(with: rect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                                attributes: [.font: font, .foregroundColor: color, .paragraphStyle: style], context: nil)
    }
}
