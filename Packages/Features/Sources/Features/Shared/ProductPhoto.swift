import ImageIO
import SwiftUI
import UIKit

/// Foto de un producto (imagen del catálogo del ciclo de GSP). Cuadrada; sin URL o sin red muestra un ícono.
/// Las fotos se guardan en caché (memoria y disco), así que se ven sin conexión una vez descargadas.
struct ProductPhoto: View {
    private let url: URL?
    private let size: CGFloat
    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?

    init(_ urlString: String?, size: CGFloat) {
        self.url = ProductImageCache.url(urlString)
        self.size = size
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: max(6, size * 0.14), style: .continuous)
        ZStack {
            if let image {
                shape.fill(Color.white)
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(size * 0.04)
            } else {
                shape.fill(Color(.secondarySystemBackground))
                Image(systemName: "shippingbox")
                    .font(.system(size: size * 0.38))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        .accessibilityHidden(true)
        .task(id: url) {
            guard let url else { image = nil; return }
            let pixels = Int(size * displayScale)
            if let cached = ProductImageCache.shared.cached(url, pixels: pixels) {
                image = cached
            } else {
                image = nil
                image = await ProductImageCache.shared.image(url, pixels: pixels)
            }
        }
    }
}

/// Descarga y reduce las fotos de producto; caché en memoria (por tamaño) y en disco (URLCache).
@MainActor
final class ProductImageCache {
    static let shared = ProductImageCache()

    private let memory = NSCache<NSString, UIImage>()
    private let session: URLSession
    private var inFlight: [String: Task<UIImage?, Never>] = [:]

    private init() {
        memory.countLimit = 400
        let configuration = URLSessionConfiguration.default
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appending(path: "ProductImages")
        configuration.urlCache = URLCache(memoryCapacity: 8 << 20, diskCapacity: 300 << 20, directory: directory)
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        configuration.timeoutIntervalForRequest = 15
        session = URLSession(configuration: configuration)
    }

    /// URL https de la imagen (GSP puede entregar `//host/…` o http).
    nonisolated static func url(_ string: String?) -> URL? {
        guard var value = string?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        if value.hasPrefix("//") { value = "https:" + value }
        if value.hasPrefix("http://") { value = "https://" + value.dropFirst("http://".count) }
        guard value.hasPrefix("https://") else { return nil }
        return URL(string: value)
    }

    func cached(_ url: URL, pixels: Int) -> UIImage? {
        memory.object(forKey: Self.key(url, pixels))
    }

    func image(_ url: URL, pixels: Int) async -> UIImage? {
        let key = Self.key(url, pixels)
        if let image = memory.object(forKey: key) { return image }
        if let running = inFlight[key as String] { return await running.value }
        let session = session
        let task = Task<UIImage?, Never> {
            guard let (data, response) = try? await session.data(from: url) else { return nil }
            if let http = response as? HTTPURLResponse, http.statusCode != 200 { return nil }
            return await Task.detached(priority: .utility) { Self.downsample(data, maxPixels: pixels) }.value
        }
        inFlight[key as String] = task
        let image = await task.value
        inFlight[key as String] = nil
        if let image { memory.setObject(image, forKey: key) }
        return image
    }

    private static func key(_ url: URL, _ pixels: Int) -> NSString {
        "\(pixels)|\(url.absoluteString)" as NSString
    }

    /// Reduce la imagen al tamaño en pantalla (ImageIO lee JPEG, PNG y WebP).
    nonisolated static func downsample(_ data: Data, maxPixels: Int) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(maxPixels, 1),
        ] as [CFString: Any] as CFDictionary
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return UIImage(data: data) }
        return UIImage(cgImage: thumbnail)
    }
}
