import Foundation
import ImageIO
import UIKit
import Vision

/// Lo que se leyó en la foto: códigos de barras y líneas de texto (de arriba hacia abajo).
struct PhotoReading: Sendable, Equatable {
    let barcodes: [String]
    let textLines: [String]
}

/// Lee una foto en el iPhone con Vision (docs/product-photo-proposal.md §2): códigos de barras y texto (OCR).
/// Sin red: la foto no sale del equipo y se descarta después.
enum PhotoAnalyzer {
    @MainActor
    static func analyze(_ image: UIImage) async throws -> PhotoReading {
        guard let jpeg = ImageEncoding.jpeg(from: image, maxDimension: 2400) else {
            return PhotoReading(barcodes: [], textLines: [])
        }
        let orientation = CGImagePropertyOrientation(image.imageOrientation).rawValue
        return try await Task.detached(priority: .userInitiated) {
            try read(jpeg: jpeg, orientationRaw: orientation)
        }.value
    }

    private static func read(jpeg: Data, orientationRaw: UInt32) throws -> PhotoReading {
        let barcodeRequest = VNDetectBarcodesRequest()
        barcodeRequest.symbologies = [.ean13, .ean8, .upce, .code128]
        let textRequest = VNRecognizeTextRequest()
        textRequest.recognitionLevel = .accurate
        textRequest.usesLanguageCorrection = false
        textRequest.recognitionLanguages = ["es-ES", "pt-BR", "en-US"]

        let handler = VNImageRequestHandler(data: jpeg, orientation: CGImagePropertyOrientation(rawValue: orientationRaw) ?? .up)
        try handler.perform([barcodeRequest, textRequest])

        let barcodes = (barcodeRequest.results ?? []).compactMap { $0.payloadStringValue }
        // Vision usa origen abajo-izquierda: mayor minY = más arriba en la foto.
        let lines = (textRequest.results ?? [])
            .sorted { $0.boundingBox.minY > $1.boundingBox.minY }
            .compactMap { $0.topCandidates(1).first?.string }
        return PhotoReading(barcodes: barcodes, textLines: lines)
    }
}

extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .upMirrored: self = .upMirrored
        case .down: self = .down
        case .downMirrored: self = .downMirrored
        case .left: self = .left
        case .leftMirrored: self = .leftMirrored
        case .right: self = .right
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
