import Compression
import Foundation

/// Lector mínimo de ZIP para el XLSX del pedido. **No valida CRC** (los de Natura vienen inválidos).
public enum ZipReader {
    public enum ZipError: Error, Equatable {
        case notZip
        case entryNotFound(String)
        case unsupportedMethod(Int)
        case corrupt
    }

    public static func entry(named name: String, in data: Data) throws -> Data {
        let bytes = [UInt8](data)
        guard let end = endOfCentralDirectory(bytes) else { throw ZipError.notZip }
        let entries = Int(read16(bytes, end + 10))
        var cursor = Int(read32(bytes, end + 16))
        for _ in 0..<entries {
            guard cursor + 46 <= bytes.count, read32(bytes, cursor) == 0x0201_4b50 else { throw ZipError.corrupt }
            let method = Int(read16(bytes, cursor + 10))
            let compressedSize = Int(read32(bytes, cursor + 20))
            let uncompressedSize = Int(read32(bytes, cursor + 24))
            let nameLength = Int(read16(bytes, cursor + 28))
            let extraLength = Int(read16(bytes, cursor + 30))
            let commentLength = Int(read16(bytes, cursor + 32))
            let localOffset = Int(read32(bytes, cursor + 42))
            guard cursor + 46 + nameLength <= bytes.count else { throw ZipError.corrupt }
            let entryName = String(decoding: bytes[(cursor + 46)..<(cursor + 46 + nameLength)], as: UTF8.self)
            cursor += 46 + nameLength + extraLength + commentLength
            guard entryName == name else { continue }

            guard localOffset + 30 <= bytes.count, read32(bytes, localOffset) == 0x0403_4b50 else { throw ZipError.corrupt }
            let start = localOffset + 30 + Int(read16(bytes, localOffset + 26)) + Int(read16(bytes, localOffset + 28))
            guard start + compressedSize <= bytes.count else { throw ZipError.corrupt }
            let compressed = Array(bytes[start..<(start + compressedSize)])
            switch method {
            case 0:
                return Data(compressed)
            case 8:
                return try inflate(compressed, expectedSize: uncompressedSize)
            default:
                throw ZipError.unsupportedMethod(method)
            }
        }
        throw ZipError.entryNotFound(name)
    }

    /// Deflate crudo (sin cabecera zlib), que es lo que usa ZIP.
    static func inflate(_ input: [UInt8], expectedSize: Int) throws -> Data {
        let capacity = max(expectedSize, input.count * 4, 64)
        var output = [UInt8](repeating: 0, count: capacity)
        let written = compression_decode_buffer(&output, capacity, input, input.count, nil, COMPRESSION_ZLIB)
        guard written > 0 else { throw ZipError.corrupt }
        return Data(output.prefix(written))
    }

    static func endOfCentralDirectory(_ bytes: [UInt8]) -> Int? {
        guard bytes.count >= 22 else { return nil }
        let lowest = max(0, bytes.count - 65_557)
        var index = bytes.count - 22
        while index >= lowest {
            if read32(bytes, index) == 0x0605_4b50 { return index }
            index -= 1
        }
        return nil
    }

    static func read16(_ bytes: [UInt8], _ offset: Int) -> UInt16 {
        UInt16(bytes[offset]) | UInt16(bytes[offset + 1]) << 8
    }

    static func read32(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
        UInt32(bytes[offset]) | UInt32(bytes[offset + 1]) << 8 | UInt32(bytes[offset + 2]) << 16 | UInt32(bytes[offset + 3]) << 24
    }
}
