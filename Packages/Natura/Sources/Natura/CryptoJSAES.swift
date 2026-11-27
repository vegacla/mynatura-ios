import CommonCrypto
import CryptoKit
import Foundation

/// Equivalente a `CryptoJS.AES.encrypt(texto, frase)` (docs/natura-integration.md §1.2):
/// salt de 8 bytes, EVP_BytesToKey con MD5 (key 32 + IV 16), AES-256-CBC con PKCS7,
/// salida base64("Salted__" ‖ salt ‖ cifrado).
public enum CryptoJSAES {
    public static func encrypt(_ plaintext: String, passphrase: String, salt: [UInt8]? = nil) -> String? {
        let saltBytes = salt ?? (0..<8).map { _ in UInt8.random(in: 0...255) }
        guard saltBytes.count == 8 else { return nil }
        var derived: [UInt8] = []
        var block: [UInt8] = []
        while derived.count < 48 {
            block = Array(Insecure.MD5.hash(data: block + Array(passphrase.utf8) + saltBytes))
            derived += block
        }
        let key = Array(derived[0..<32])
        let iv = Array(derived[32..<48])
        let input = Array(plaintext.utf8)
        var output = [UInt8](repeating: 0, count: input.count + kCCBlockSizeAES128)
        var written = 0
        let status = CCCrypt(CCOperation(kCCEncrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionPKCS7Padding),
                             key, key.count, iv, input, input.count, &output, output.count, &written)
        guard status == kCCSuccess else { return nil }
        return Data(Array("Salted__".utf8) + saltBytes + Array(output.prefix(written))).base64EncodedString()
    }
}
