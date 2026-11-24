import SwiftUI
import VisionKit

/// Escáner VisionKit (EAN‑13/EAN‑8/UPC‑E/Code128) para EAN y SKU (§2).
struct BarcodeScannerView: UIViewControllerRepresentable {
    let onCode: (String) -> Void

    static var isAvailable: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let controller = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.ean13, .ean8, .upce, .code128])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true)
        controller.delegate = context.coordinator
        try? controller.startScanning()
        return controller
    }

    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {
        context.coordinator.onCode = onCode
    }

    static func dismantleUIViewController(_ controller: DataScannerViewController, coordinator: Coordinator) {
        controller.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode) }

    @MainActor
    final class Coordinator: NSObject {
        var onCode: (String) -> Void
        private var lastCode: String?
        private var lastDate = Date.distantPast

        init(onCode: @escaping (String) -> Void) {
            self.onCode = onCode
        }

        fileprivate func emit(_ code: String) {
            // Evita lecturas repetidas del mismo código en menos de 1,5 s (escaneo continuo).
            if code == lastCode, Date().timeIntervalSince(lastDate) < 1.5 { return }
            lastCode = code
            lastDate = Date()
            onCode(code)
        }
    }
}

extension BarcodeScannerView.Coordinator: @preconcurrency DataScannerViewControllerDelegate {
    func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
        for item in addedItems {
            if case .barcode(let barcode) = item, let value = barcode.payloadStringValue {
                emit(value)
            }
        }
    }

    func dataScanner(_ dataScanner: DataScannerViewController, didTapOn item: RecognizedItem) {
        if case .barcode(let barcode) = item, let value = barcode.payloadStringValue {
            emit(value)
        }
    }
}

/// Hoja con el escáner. `continuous` = sigue abierta tras cada lectura (recepción por código).
struct ScannerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let continuous: Bool
    let onCode: (String) -> Void
    @State private var lastRead: String?

    var body: some View {
        NavigationStack {
            Group {
                if BarcodeScannerView.isAvailable {
                    BarcodeScannerView { code in
                        lastRead = code
                        onCode(code)
                        if !continuous { dismiss() }
                    }
                    .ignoresSafeArea(edges: .bottom)
                } else {
                    ContentUnavailableView("Escáner no disponible", systemImage: "camera.metering.unknown",
                                           description: Text("Revisa el permiso de cámara en Ajustes del iPhone."))
                }
            }
            .safeAreaInset(edge: .bottom) {
                if continuous, let lastRead {
                    Text("Último: \(lastRead)")
                        .font(.footnote.monospacedDigit())
                        .padding(8)
                        .background(.thinMaterial, in: Capsule())
                        .padding()
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Listo") { dismiss() }
                }
            }
        }
    }
}

/// Botón con ícono de escáner (§10 ScannerButton).
struct ScannerButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "barcode.viewfinder")
        }
        .accessibilityLabel("Escanear código")
    }
}
