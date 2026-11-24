import Testing
@testable import Core

@Suite("Normalize")
struct NormalizeTests {
    @Test func naturaSku() {
        #expect(Normalize.naturaSku("# 70983") == "70983")
        #expect(Normalize.naturaSku("  70983 ") == "70983")
    }

    @Test func ean() {
        #expect(Normalize.ean("7908-1322 97387") == "7908132297387")
    }

    @Test func rut() {
        #expect(Normalize.rut("12.345.678-k") == "12345678K")
    }

    @Test func customerName() {
        #expect(Normalize.customerName("  María   José  PÉREZ ") == "maria jose perez")
    }

    @Test func scanCode() {
        #expect(Normalize.scanCode(" 7908132297387 ") == "7908132297387")
        #expect(Normalize.scanCode("#70983") == "70983")
    }
}
