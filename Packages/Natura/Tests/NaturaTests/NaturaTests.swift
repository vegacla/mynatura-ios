import Foundation
import Testing
@testable import Natura

@Suite("Natura · cifrado y ZIP")
struct NaturaTests {
    /// Vectores generados con el mismo algoritmo del backend (Node crypto) y salt fijo 01…08.
    @Test func cryptoJSCompatible() {
        let salt: [UInt8] = [1, 2, 3, 4, 5, 6, 7, 8]
        #expect(CryptoJSAES.encrypt("secret123", passphrase: "12345678", salt: salt)
            == "U2FsdGVkX18BAgMEBQYHCPv2/fp7ywSRfFEnY3h6KKc=")
        #expect(CryptoJSAES.encrypt("Contraseña-Ñandú 2026!", passphrase: "consultora@example.com", salt: salt)
            == "U2FsdGVkX18BAgMEBQYHCOsNkOrABPI2Bl27cU+uFU4iCi/XuMHUvnzxE50hi2Yy")
        // Sin salt dado: aleatorio, pero con el prefijo "Salted__".
        let random = CryptoJSAES.encrypt("x", passphrase: "y")
        #expect(random?.hasPrefix("U2FsdGVkX1") == true)
    }

    /// ZIP con una entrada deflate y otra sin comprimir, ambos con CRC inválido (como el Excel de Natura).
    static let zip = "UEsDBBQAAAAIAAAAAADvvq3eSwAAAGAAAAAYAAAAeGwvd29ya3NoZWV0cy9zaGVldDEueG1ssynPL8ouzkhNLbGzAVMuiSWJdjZF+eUKRbZKhkp2NskghqOhkkKJrVJxSZGSnU2ZnUd+TqKNfpmdjX6ynY1+UX65nY0+km59hKEAUEsDBBQAAAAAAAAAAADvvq3eCAAAAAgAAAATAAAAW0NvbnRlbnRfVHlwZXNdLnhtbDxUeXBlcy8+UEsBAhQAFAAAAAgAAAAAAO++rd5LAAAAYAAAABgAAAAAAAAAAAAAAAAAAAAAAHhsL3dvcmtzaGVldHMvc2hlZXQxLnhtbFBLAQIUABQAAAAAAAAAAADvvq3eCAAAAAgAAAATAAAAAAAAAAAAAAAAAIEAAABbQ29udGVudF9UeXBlc10ueG1sUEsFBgAAAAACAAIAhwAAALoAAAAAAA=="

    @Test func zipIgnoresCRC() throws {
        let data = Data(base64Encoded: Self.zip)!
        let sheet = try ZipReader.entry(named: "xl/worksheets/sheet1.xml", in: data)
        #expect(String(decoding: sheet, as: UTF8.self).contains("<v>Hola</v>"))
        let types = try ZipReader.entry(named: "[Content_Types].xml", in: data)
        #expect(String(decoding: types, as: UTF8.self) == "<Types/>")
        #expect(throws: ZipReader.ZipError.entryNotFound("nada")) { try ZipReader.entry(named: "nada", in: data) }
        #expect(throws: ZipReader.ZipError.notZip) { try ZipReader.entry(named: "x", in: Data("hola".utf8)) }
    }

    @Test func prices() {
        #expect(NaturaClient.price(["from": 31198, "to": 23512]) == 23512)
        #expect(NaturaClient.price(["from": 9990]) == 9990)
        #expect(NaturaClient.code(59313) == "59313")
        #expect(NaturaClient.code("#59313") == "59313")
    }
}
