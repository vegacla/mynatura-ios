import Foundation
import Testing
@testable import Core

@Suite("Natura · lectura de respuestas")
struct NaturaParsersTests {
    @Test func usernameAndCredentialErrors() {
        #expect(NaturaUsername.normalize(" 12.345.678-9 ") == "123456789")
        #expect(NaturaUsername.normalize(" ana@example.com ") == "ana@example.com")
        #expect(NaturaUsername.isCredentialError(status: 401, message: ""))
        #expect(NaturaUsername.isCredentialError(status: 400, message: "Usuario o contraseña incorrectos"))
        #expect(!NaturaUsername.isCredentialError(status: 400, message: "Bad request"))
    }

    @Test func gspBundle() throws {
        let html = #"<script src="/static/js/static/js/lib-react.1.js"></script><script src="/static/js/static/js/index.2fae32d7.js"></script>"#
        #expect(NaturaBundle.gspBundlePath(fromHTML: html) == "/static/js/static/js/index.2fae32d7.js")
        let bundle = #"x={COGNITO_SERVICE_URL:"https://auth.example",COGNITO_SERVICE_API_URL:"https://api.example",COGNITO_CLIENT_ID:"abc123",COGNITO_X_API_KEY:"key-1",COGNITO_REDIRECT_URI:"https://gsp.example",GSP_GRAPHQL_URL:"https://gql.example/graphql"}"#
        let config = try NaturaBundle.gspConfig(fromBundle: bundle)
        #expect(config == GspPublicConfig(clientId: "abc123", apiKey: "key-1", serviceApiUrl: "https://api.example",
                                          redirectUri: "https://gsp.example", graphqlUrl: "https://gql.example/graphql"))
        #expect(throws: NaturaParseError.bundleFormatChanged) { try NaturaBundle.gspConfig(fromBundle: "nada") }
    }

    @Test func ordersPage() throws {
        let json = #"""
        [{"id":"8d0c1f9e-0000-4000-8000-000000000001","orderNumber":"811111100","cycle":202618,"subCycle":null,
          "orderingDate":"2026-11-22T10:15:00-03:00","deliveryDate":null,"totalValue":"190.614","totalPoints":250,
          "itemsQuantity":17,"status":{"id":5,"name":"Entregado"}},
         {"id":"8d0c1f9e-0000-4000-8000-000000000002","orderNumber":"811111200","cycle":19,"subCycle":null,
          "orderingDate":"2026-11-26T09:00:00-03:00","deliveryDate":null,"totalValue":"55.025",
          "itemsQuantity":3,"status":{"id":3,"name":"En transporte"}}]
        """#
        let orders = try NaturaOrders.decodePage(Data(json.utf8))
        #expect(orders.count == 2)
        #expect(orders[0].isDelivered)
        #expect(!orders[1].isDelivered)
        #expect(orders[0].cycleCode == 202618)
        #expect(orders[1].cycleCode == 202619)
        #expect(orders[0].totalPesos == 190614)
        #expect(orders[0].orderedAt != nil)
        #expect(NaturaOrders.isLastPage(orders))
        #expect(throws: NaturaParseError.invalidOrders) { try NaturaOrders.decodePage(Data("{}".utf8)) }
    }

    @Test func itemsHTML() throws {
        let html = """
        <table><tbody id="order-items-list">
        <tr><td>Código: #59313</td><td>Puntos: 12</td><td><b>BLUR UNA 30 ML</b></td><td>Cantidad: 1</td>
            <td>Tipo: Venta</td><td>Valor unitario: $6.824</td><td>Total Puntos: 12</td><td>Total Neto: $6.824</td></tr>
        <tr><td>Código: 77777</td><td>Puntos: -</td><td>BOLSA&nbsp;NATURA</td><td>Cantidad: 2</td>
            <td>Tipo: Regalo</td><td>Valor unitario: -</td><td>Total Puntos: -</td><td>Total Neto: -</td></tr>
        </tbody></table>
        """
        let items = try NaturaItemsHTML.parse(html)
        #expect(items.count == 2)
        #expect(items[0] == NaturaOrderItem(position: 1, sku: "59313", name: "BLUR UNA 30 ML", quantity: 1, itemType: "Venta",
                                            points: 12, unitCostPesos: 6824, rawUnitValue: "$6.824"))
        #expect(items[1].name == "BOLSA NATURA")
        #expect(items[1].unitCostPesos == nil)
        #expect(items[1].rawUnitValue == "-")
        #expect(throws: NaturaParseError.missingItemsTable) { try NaturaItemsHTML.parse("<html></html>") }
    }

    /// Estructura del Excel real (valores inventados).
    func sheet() -> Data {
        func row(_ number: Int, _ cells: [(String, String)]) -> String {
            "<row r=\"\(number)\">" + cells.map { "<c r=\"\($0.0)\(number)\" t=\"str\"><v>\($0.1)</v></c>" }.joined() + "</row>"
        }
        let rows = [
            row(2, [("A", "CONSULTOR/A"), ("B", "NOMBRE (000)"), ("F", "PEDIDO"), ("G", "811111100"), ("H", "CICLO"), ("I", "18/2026"),
                    ("J", "FECHA"), ("K", "22-11-2026")]),
            row(6, [("A", "Cant."), ("B", "Código"), ("C", "Descriptions"), ("F", "Marca"), ("G", "Precio revista (uni.)"),
                    ("H", "Precio revista (total)"), ("I", "Precio CB (total)"), ("J", "Ganancia (total)")]),
            row(7, [("A", "3"), ("B", "150225"), ("C", "DESODORANTE ROLL-ON HOMEM 75 ML"), ("F", "NATURA"), ("G", "5590"),
                    ("H", "16770"), ("I", "12591"), ("J", "4179")]),
            row(8, [("A", "1"), ("B", "280349"), ("C", "PROMO OPORTUNIDAD 250PTS"), ("F", "NATURA"), ("G", "14890"),
                    ("H", "14890"), ("I", "14890"), ("J", "0")]),
            row(9, [("A", "1"), ("B", "77777"), ("C", "MUESTRA KAIAK"), ("F", "NATURA"), ("G", "3990"), ("H", "3990"), ("I", "0"), ("J", "3990")]),
            row(10, [("A", "1"), ("B", "1"), ("C", "TASA DE SERVICIO"), ("G", "0"), ("H", "0"), ("I", "0"), ("J", "0")]),
            row(11, [("A", "Total por marca")]),
            row(12, [("A", "NATURA"), ("C", "190614"), ("D", "55025")]),
            row(13, [("A", "TOTALES"), ("C", "190614"), ("D", "55025")]),
        ]
        return Data(("<?xml version=\"1.0\"?><worksheet><sheetData>" + rows.joined() + "</sheetData></worksheet>").utf8)
    }

    @Test func orderReport() throws {
        let report = try OrderReportParser.parse(sheetXML: sheet())
        #expect(report.orderNumber == "811111100")
        #expect(report.cycleCode == 202618)
        #expect(report.lines.map(\.sku) == ["150225", "280349", "77777"])
        let deodorant = report.lines[0]
        #expect(deodorant.quantity == 3)
        #expect(deodorant.suggestedUnitPesos == 5590)
        #expect(deodorant.costTotalPesos == 12591)
        #expect(deodorant.unitCostPesos == 4197)
        #expect(report.lines[2].unitCostPesos == 0)
        #expect(report.lines[2].suggestedUnitPesos == 3990)
        #expect(OrderReportParser.columnIndex("A") == 0)
        #expect(OrderReportParser.columnIndex("AA") == 26)
    }

    @Test func homeCycle() {
        #expect(MinegocioHome.currentCycle(fromHTML: "<script> var query_cycle = [202619]; var x = 1;</script>") == 202619)
        #expect(MinegocioHome.currentCycle(fromHTML: "<html></html>") == nil)
    }
}
