import Foundation
import Network
import Observation

/// Conectividad real con NWPathMonitor (§2).
@MainActor
@Observable
public final class ConnectivityMonitor {
    public private(set) var isOnline = true
    /// Se llama al pasar de sin conexión a con conexión.
    public var onReconnect: (@MainActor () -> Void)?

    private let monitor = NWPathMonitor()

    public init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in self?.update(online) }
        }
        monitor.start(queue: DispatchQueue(label: "cl.mynatura.app.connectivity"))
    }

    private func update(_ online: Bool) {
        let wasOnline = isOnline
        isOnline = online
        AppLog.sync.info("Conectividad: \(online ? "en línea" : "sin conexión", privacy: .public)")
        if online, !wasOnline { onReconnect?() }
    }
}
