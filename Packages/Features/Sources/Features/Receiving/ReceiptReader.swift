import Core
import Foundation
import ImageIO
import UIKit
import Vision

/// Lee la boleta impresa del pedido en el iPhone con Vision (M4, reemplaza al OCR del backend).
/// Sin red: la foto no sale del equipo ni se guarda. La interpretación de filas y columnas está en `Core.ReceiptOcr`.
enum ReceiptReader {
    @MainActor
    static func read(_ image: UIImage) async throws -> [ReceiptOcrRow] {
        guard let jpeg = ImageEncoding.jpeg(from: image, maxDimension: 3000) else { return [] }
        let orientationRaw = CGImagePropertyOrientation(image.imageOrientation).rawValue
        return try await Task.detached(priority: .userInitiated) {
            try bestReading(jpeg: jpeg, orientation: CGImagePropertyOrientation(rawValue: orientationRaw) ?? .up)
        }.value
    }

    /// Primero la orientación de la foto; si no salen filas, prueba girada (como el backend con 0/±90/180°)
    /// y se queda con la que más se parece a una boleta.
    private static func bestReading(jpeg: Data, orientation: CGImagePropertyOrientation) throws -> [ReceiptOcrRow] {
        let first = try words(jpeg: jpeg, orientation: orientation)
        let firstRows = ReceiptOcr.extractRows(from: first)
        if !firstRows.isEmpty { return firstRows }

        var best = (score: ReceiptOcr.score(text: text(of: first)), rows: firstRows)
        for rotated in rotations(of: orientation) {
            let candidate = try words(jpeg: jpeg, orientation: rotated)
            let rows = ReceiptOcr.extractRows(from: candidate)
            let score = ReceiptOcr.score(text: text(of: candidate))
            if rows.count > best.rows.count || (rows.count == best.rows.count && score > best.score) {
                best = (score, rows)
            }
        }
        return best.rows
    }

    private static func rotations(of orientation: CGImagePropertyOrientation) -> [CGImagePropertyOrientation] {
        let cycle: [CGImagePropertyOrientation] = [.up, .right, .down, .left]
        guard let index = cycle.firstIndex(of: orientation) else { return [.right, .left, .down] }
        return (1...3).map { cycle[(index + $0) % 4] }
    }

    private static func text(of words: [OcrWord]) -> String {
        ReceiptOcr.lines(from: words).map(\.text).joined(separator: "\n")
    }

    /// Palabras con su caja (origen arriba a la izquierda), para separar columnas.
    private static func words(jpeg: Data, orientation: CGImagePropertyOrientation) throws -> [OcrWord] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.recognitionLanguages = ["es-ES", "en-US"]
        let handler = VNImageRequestHandler(data: jpeg, orientation: orientation)
        try handler.perform([request])

        var result: [OcrWord] = []
        for observation in request.results ?? [] {
            guard let candidate = observation.topCandidates(1).first else { continue }
            let string = candidate.string
            var index = string.startIndex
            while index < string.endIndex {
                guard let start = string[index...].firstIndex(where: { !$0.isWhitespace }) else { break }
                let end = string[start...].firstIndex(where: \.isWhitespace) ?? string.endIndex
                let range = start..<end
                // Vision usa origen abajo a la izquierda; si no da la caja de la palabra, se usa la de la observación.
                let box = (try? candidate.boundingBox(for: range))?.boundingBox ?? observation.boundingBox
                result.append(OcrWord(text: String(string[range]),
                                      minX: Double(box.minX), maxX: Double(box.maxX),
                                      minY: Double(1 - box.maxY), maxY: Double(1 - box.minY),
                                      confidence: Double(candidate.confidence)))
                index = end
            }
        }
        return result
    }
}
