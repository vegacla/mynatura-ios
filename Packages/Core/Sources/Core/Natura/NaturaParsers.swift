import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

// Lectura de las respuestas de Natura (docs/natura-integration.md). Puro: sin red, probado en Linux.

public enum NaturaParseError: Error, Equatable, Sendable {
    case missingBundle
    case bundleFormatChanged
    case missingItemsTable
    case invalidOrders
    case invalidReport
    case invalidAccounts

    public var message: String {
        switch self {
        case .missingBundle: "No se encontró la configuración pública de Natura."
        case .bundleFormatChanged: "Natura cambió el formato de su configuración."
        case .missingItemsTable: "No se encontró la tabla de productos del pedido."
        case .invalidOrders: "Natura respondió una lista de pedidos inesperada."
        case .invalidAccounts: "Natura respondió una cuenta (mis-cuentas) inesperada."
        case .invalidReport: "No se pudo leer el Excel del pedido."
        }
    }
}

// MARK: - Login

public enum NaturaUsername {
    /// Email → trim; código o documento → sin puntos, guiones ni espacios.
    public static func normalize(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.contains("@"), trimmed.contains(".") { return trimmed }
        return trimmed.filter { $0 != "." && $0 != "-" && !$0.isWhitespace }
    }

    /// Mensajes de Natura que significan credenciales rechazadas: no se reintenta (evita bloquear la cuenta).
    public static func isCredentialError(status: Int, message: String) -> Bool {
        if status == 401 { return true }
        let pattern = #"password|contrase|senha|incorrect|not ?authorized|unauthori[sz]ed|user.*(not|no).*(found|exist)|usuario|usu[aá]rio|attempt|intento|tentativa|bloque|locked|disabled"#
        return message.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }
}

/// Configuración pública de GSP (leída en vivo de su bundle).
public struct GspPublicConfig: Equatable, Sendable {
    public let clientId: String
    public let apiKey: String
    public let serviceApiUrl: String
    public let redirectUri: String
    public let graphqlUrl: String
}

public enum NaturaBundle {
    /// `src="/static/js/static/js/index.<hash>.js"` del HTML de gsp.natura.com.
    public static func gspBundlePath(fromHTML html: String) -> String? {
        firstMatch(#"src="(/static/js/[^"]*index\.[a-f0-9]+\.js)""#, in: html)
    }

    public static func gspConfig(fromBundle bundle: String) throws(NaturaParseError) -> GspPublicConfig {
        func read(_ key: String) -> String? { firstMatch(key + #":"([^"]+)""#, in: bundle) }
        guard let clientId = read("COGNITO_CLIENT_ID"), let apiKey = read("COGNITO_X_API_KEY"),
              let serviceApiUrl = read("COGNITO_SERVICE_API_URL"), let graphqlUrl = read("GSP_GRAPHQL_URL") else {
            throw .bundleFormatChanged
        }
        return GspPublicConfig(clientId: clientId, apiKey: apiKey, serviceApiUrl: serviceApiUrl,
                               redirectUri: read("COGNITO_REDIRECT_URI") ?? "https://gsp.natura.com", graphqlUrl: graphqlUrl)
    }

    /// Primer grupo de captura de `pattern` (para otros paquetes).
    public static func firstMatchPublic(_ pattern: String, in text: String) -> String? {
        firstMatch(pattern, in: text)
    }

    /// Primer grupo de captura de `pattern`.
    static func firstMatch(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 1, let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }
}

// MARK: - Pedidos

public struct NaturaOrderSummary: Decodable, Equatable, Sendable {
    public struct Status: Decodable, Equatable, Sendable {
        public let id: Int
        public let name: String
    }

    public let id: String
    public let orderNumber: String
    public let cycle: Int
    public let subCycle: String?
    public let orderingDate: String
    public let deliveryDate: String?
    public let totalValue: String?
    public let itemsQuantity: Int?
    public let status: Status

    public var isDelivered: Bool { status.name.lowercased() == "entregado" }

    /// Ciclo AAAACC: si viene corto, el año sale de la fecha.
    public var cycleCode: Int {
        if cycle >= 10_000 { return cycle }
        let year = NaturaDates.parse(deliveryDate ?? orderingDate).map { Calendar(identifier: .gregorian).component(.year, from: $0) }
        return (year ?? 2000) * 100 + cycle
    }

    public var orderedAt: Date? { NaturaDates.parse(orderingDate) }
    public var deliveredAt: Date? { deliveryDate.flatMap(NaturaDates.parse) }
    public var totalPesos: Int? { totalValue.flatMap(NaturaNumbers.pesos) }
}

public enum NaturaOrders {
    public static let pageSize = 25

    public static func decodePage(_ data: Data) throws(NaturaParseError) -> [NaturaOrderSummary] {
        do {
            return try JSONDecoder().decode([NaturaOrderSummary].self, from: data)
        } catch {
            throw .invalidOrders
        }
    }

    /// Última página cuando trae menos que el tamaño pedido.
    public static func isLastPage(_ page: [NaturaOrderSummary]) -> Bool { page.count < pageSize }
}

public enum NaturaDates {
    public static func parse(_ text: String) -> Date? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let iso = ISO8601DateFormatter()
        if let date = iso.date(from: trimmed) { return date }
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: trimmed) { return date }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "America/Santiago")
        for format in ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd", "dd-MM-yyyy", "dd/MM/yyyy"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: trimmed) { return date }
        }
        return nil
    }
}

public enum NaturaNumbers {
    /// "$12.990", "12.990", "9090" → 12990 / 9090. "-" o vacío → nil.
    public static func pesos(_ text: String) -> Int? {
        let digits = text.filter { $0.isASCIIDigit || $0 == "-" }
        guard !digits.isEmpty, digits != "-" else { return nil }
        return Int(digits)
    }
}

// MARK: - Líneas (HTML, respaldo)

public struct NaturaOrderItem: Equatable, Sendable {
    public let position: Int
    public let sku: String
    public let name: String
    public let quantity: Int
    public let itemType: String
    public let points: Int?
    /// nil = "-" (gratis) o ilegible.
    public let unitCostPesos: Int?
    public let rawUnitValue: String
}

public enum NaturaItemsHTML {
    public static func parse(_ html: String) throws(NaturaParseError) -> [NaturaOrderItem] {
        guard let tbody = NaturaBundle.firstMatch(#"(?is)<tbody id="order-items-list">(.*?)</tbody>"#, in: html) else {
            throw .missingItemsTable
        }
        let rows = matches(#"(?is)<tr[^>]*>(.*?)</tr>"#, in: tbody)
        return rows.enumerated().compactMap { index, row in
            let cells = matches(#"(?is)<td[^>]*>(.*?)</td>"#, in: row).map(clean)
            guard cells.count >= 6 else { return nil }
            func value(_ cell: Int, _ label: String) -> String {
                guard cell < cells.count else { return "" }
                return cells[cell].replacingOccurrences(of: label, with: "").trimmingCharacters(in: .whitespaces)
            }
            let sku = Normalize.naturaSku(value(0, "Código:"))
            let unitValue = value(5, "Valor unitario:")
            return NaturaOrderItem(
                position: index + 1, sku: sku, name: cells[2], quantity: NaturaNumbers.pesos(value(3, "Cantidad:")) ?? 0,
                itemType: value(4, "Tipo:"), points: NaturaNumbers.pesos(value(1, "Puntos:")),
                unitCostPesos: NaturaNumbers.pesos(unitValue.replacingOccurrences(of: "$", with: "")), rawUnitValue: unitValue)
        }
    }

    static func matches(_ pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap {
            Range($0.range(at: 1), in: text).map { String(text[$0]) }
        }
    }

    static func clean(_ fragment: String) -> String {
        fragment
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}

// MARK: - Excel del pedido (fuente principal)

public struct OrderReportLine: Equatable, Sendable {
    public let quantity: Int
    public let sku: String
    public let name: String
    public let brand: String
    /// Precio revista (uni.): precio sugerido de venta.
    public let suggestedUnitPesos: Int?
    /// Precio CB (total): costo de la línea.
    public let costTotalPesos: Int?

    /// Costo unitario redondeado; 0 si la línea es gratis.
    public var unitCostPesos: Int? {
        guard let costTotalPesos, quantity > 0 else { return nil }
        return Int((Double(costTotalPesos) / Double(quantity)).rounded())
    }
}

public struct OrderReport: Equatable, Sendable {
    public let orderNumber: String?
    /// AAAACC.
    public let cycleCode: Int?
    public let lines: [OrderReportLine]
}

public enum OrderReportParser {
    static let serviceFeeCodes: Set<String> = ["1"]

    /// Lee `xl/worksheets/sheet1.xml`. Excluye "TASA DE SERVICIO" y las filas de totales.
    public static func parse(sheetXML: Data) throws(NaturaParseError) -> OrderReport {
        let reader = SheetReader()
        let parser = XMLParser(data: sheetXML)
        parser.delegate = reader
        guard parser.parse() else { throw .invalidReport }
        return build(rows: reader.rows)
    }

    static func build(rows: [[String: String]]) -> OrderReport {
        var orderNumber: String?
        var cycleCode: Int?
        var columns: [String: String] = [:]
        var lines: [OrderReportLine] = []

        for row in rows {
            let ordered = row.sorted { columnIndex($0.key) < columnIndex($1.key) }
            let values = ordered.map(\.value)
            if let index = values.firstIndex(of: "PEDIDO"), index + 1 < values.count { orderNumber = values[index + 1] }
            if let index = values.firstIndex(of: "CICLO"), index + 1 < values.count {
                let parts = values[index + 1].split(separator: "/").compactMap { Int($0) }
                if parts.count == 2 { cycleCode = parts[1] * 100 + parts[0] }
            }
            if values.contains("Cant.") && values.contains("Código") {
                for (column, value) in ordered { columns[value] = column }
                continue
            }
            guard !columns.isEmpty,
                  let quantityText = columns["Cant."].flatMap({ row[$0] }), let quantity = Int(quantityText),
                  let sku = columns["Código"].flatMap({ row[$0] }).map(Normalize.naturaSku), !sku.isEmpty else { continue }
            let name = columns["Descriptions"].flatMap { row[$0] } ?? ""
            if serviceFeeCodes.contains(sku) || name.uppercased().contains("TASA DE SERVICIO") { continue }
            lines.append(OrderReportLine(
                quantity: quantity, sku: sku, name: name, brand: columns["Marca"].flatMap { row[$0] } ?? "",
                suggestedUnitPesos: columns["Precio revista (uni.)"].flatMap { row[$0] }.flatMap(NaturaNumbers.pesos),
                costTotalPesos: columns["Precio CB (total)"].flatMap { row[$0] }.flatMap(NaturaNumbers.pesos)))
        }
        return OrderReport(orderNumber: orderNumber, cycleCode: cycleCode, lines: lines)
    }

    /// "A" → 0, "J" → 9, "AA" → 26.
    static func columnIndex(_ column: String) -> Int {
        column.uppercased().unicodeScalars.reduce(0) { $0 * 26 + Int($1.value) - 64 } - 1
    }

    /// Filas como [columna: texto], a partir de `<row><c r="B6" t="str"><v>…</v></c></row>` (o `<is><t>`).
    final class SheetReader: NSObject, XMLParserDelegate {
        var rows: [[String: String]] = []
        private var current: [String: String] = [:]
        private var cellColumn: String?
        private var text = ""
        private var capturing = false

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                    qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
            switch elementName {
            case "row": current = [:]
            case "c":
                cellColumn = attributeDict["r"].map { String($0.prefix { $0.isLetter }) }
                text = ""
            case "v", "t":
                capturing = true
            default: break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            if capturing { text += string }
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
            switch elementName {
            case "v", "t": capturing = false
            case "c":
                let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if let cellColumn, !value.isEmpty { current[cellColumn] = value }
                cellColumn = nil
            case "row": rows.append(current)
            default: break
            }
        }
    }
}

// MARK: - minegocio home

public enum MinegocioHome {
    /// `var query_cycle = [202619];` → 202619.
    public static func currentCycle(fromHTML html: String) -> Int? {
        NaturaBundle.firstMatch(#"var query_cycle\s*=\s*\[(\d{6})\]"#, in: html).flatMap(Int.init)
    }
}
