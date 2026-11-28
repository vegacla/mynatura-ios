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

/// Foto que se abre a pantalla completa al tocarla, con zoom (pellizcar o doble toque).
struct ZoomableProductPhoto: View {
    let urlString: String?
    let size: CGFloat
    @State private var showing = false

    init(_ urlString: String?, size: CGFloat) {
        self.urlString = urlString
        self.size = size
    }

    var body: some View {
        Button { showing = true } label: { ProductPhoto(urlString, size: size) }
            .buttonStyle(.plain)
            .accessibilityLabel("Ver foto ampliada")
            .fullScreenCover(isPresented: $showing) { ProductPhotoViewer(urlString: urlString) }
    }
}

/// Visor a pantalla completa: la foto en mayor resolución, pellizcar para acercar, doble toque para alternar.
struct ProductPhotoViewer: View {
    let urlString: String?
    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.white.ignoresSafeArea()
            if let image {
                ZoomableImage(image: image).ignoresSafeArea()
            } else if failed {
                ContentUnavailableView("Sin foto", systemImage: "photo",
                                       description: Text("No se pudo descargar la foto. Revisa tu conexión."))
            } else {
                ProgressView().tint(.gray)
            }
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 32))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .black.opacity(0.55))
            }
            .padding()
            .accessibilityLabel("Cerrar")
        }
        .environment(\.colorScheme, .light)
        .task {
            guard let url = ProductImageCache.url(urlString) else { failed = true; return }
            if let cached = ProductImageCache.shared.cached(url, pixels: Self.pixels) {
                image = cached
            } else {
                image = await ProductImageCache.shared.image(url, pixels: Self.pixels)
            }
            failed = image == nil
        }
    }

    /// Resolución del visor (no se agranda si la original es menor).
    private static let pixels = 2048
}

private struct ZoomableImage: UIViewRepresentable {
    let image: UIImage

    func makeUIView(context: Context) -> ZoomingImageView { ZoomingImageView(image: image) }
    func updateUIView(_ view: ZoomingImageView, context: Context) {}
}

/// UIScrollView con zoom nativo (pellizcar, arrastrar con inercia, doble toque).
final class ZoomingImageView: UIScrollView, UIScrollViewDelegate {
    private let imageView: UIImageView

    init(image: UIImage) {
        imageView = UIImageView(image: image)
        super.init(frame: .zero)
        imageView.contentMode = .scaleAspectFit
        addSubview(imageView)
        delegate = self
        minimumZoomScale = 1
        maximumZoomScale = 5
        bouncesZoom = true
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        contentInsetAdjustmentBehavior = .never
        backgroundColor = .white
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(toggleZoom(_:)))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) no se usa") }

    override func layoutSubviews() {
        super.layoutSubviews()
        if zoomScale == minimumZoomScale {
            imageView.frame = bounds
            contentSize = bounds.size
        }
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

    @objc private func toggleZoom(_ gesture: UITapGestureRecognizer) {
        if zoomScale > minimumZoomScale {
            setZoomScale(minimumZoomScale, animated: true)
        } else {
            let point = gesture.location(in: imageView)
            let scale: CGFloat = 2.5
            let size = CGSize(width: bounds.width / scale, height: bounds.height / scale)
            zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2,
                            width: size.width, height: size.height), animated: true)
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
