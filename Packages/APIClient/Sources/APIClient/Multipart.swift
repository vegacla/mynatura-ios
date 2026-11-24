import Foundation

/// Cuerpo multipart/form-data con un solo archivo (OCR de boleta).
public struct MultipartFile: Sendable {
    public let body: Data
    public let contentType: String

    public init(fieldName: String, fileName: String, mimeType: String, data: Data, boundary: String = "Boundary-\(UUID().uuidString)") {
        var body = Data()
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"\(fieldName)\"; filename=\"\(fileName)\"\r\n".utf8))
        body.append(Data("Content-Type: \(mimeType)\r\n\r\n".utf8))
        body.append(data)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        self.body = body
        self.contentType = "multipart/form-data; boundary=\(boundary)"
    }
}
