import Foundation

/// Documento de la cuenta con Natura (`GET /pedidos/ajax/mis-cuentas?order=0&state=`, docs/natura-integration.md §2.4).
public struct NaturaAccountDocument: Codable, Sendable, Equatable {
    public let number: String
    public let orderNumber: String
    public let isOpen: Bool
    public let isOverdue: Bool
    public let issueDate: Date?
    public let dueDate: Date?
    public let originalPesos: Int?
    public let balancePesos: Int?
    public let overdueDays: Int

    public init(number: String, orderNumber: String, isOpen: Bool, isOverdue: Bool, issueDate: Date?, dueDate: Date?,
                originalPesos: Int?, balancePesos: Int?, overdueDays: Int) {
        self.number = number
        self.orderNumber = orderNumber
        self.isOpen = isOpen
        self.isOverdue = isOverdue
        self.issueDate = issueDate
        self.dueDate = dueDate
        self.originalPesos = originalPesos
        self.balancePesos = balancePesos
        self.overdueDays = overdueDays
    }

    /// Abierto y con saldo: lo que falta pagar.
    public var isPending: Bool { isOpen && (balancePesos ?? 0) > 0 }
}

public enum NaturaAccounts {
    /// Lista de documentos. Los montos llegan como texto ("190.614") y las fechas en ISO 8601.
    public static func decode(_ data: Data) throws(NaturaParseError) -> [NaturaAccountDocument] {
        guard let list = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else {
            throw .invalidAccounts
        }
        return list.map { item in
            NaturaAccountDocument(
                number: text(item["number"]) ?? "", orderNumber: text(item["orderingNumber"]) ?? "",
                isOpen: item["isOpen"] as? Bool ?? false, isOverdue: item["isOverdue"] as? Bool ?? false,
                issueDate: text(item["issueDate"]).flatMap(NaturaDates.parse),
                dueDate: text(item["dueDate"]).flatMap(NaturaDates.parse),
                originalPesos: pesos(item["originalValue"]), balancePesos: pesos(item["currentBalance"]),
                overdueDays: (item["overdueDays"] as? Int) ?? 0)
        }
    }

    static func text(_ value: Any?) -> String? {
        switch value {
        case let string as String: string.isEmpty ? nil : string
        case let int as Int: String(int)
        case let double as Double: String(Int(double))
        default: nil
        }
    }

    static func pesos(_ value: Any?) -> Int? {
        switch value {
        case let string as String: NaturaNumbers.pesos(string)
        case let int as Int: int
        case let double as Double: Int(double.rounded())
        default: nil
        }
    }
}

/// Resumen para la tarjeta "Cuenta Natura": saldo pendiente, próximo vencimiento y atrasos.
public struct NaturaAccountSummary: Sendable, Equatable {
    public let pendingCount: Int
    public let pendingPesos: Int
    /// Documento pendiente no vencido con la fecha de vencimiento más próxima.
    public let nextDue: NaturaAccountDocument?
    public let overdueCount: Int
    public let overduePesos: Int
    public let maxOverdueDays: Int

    public init(documents: [NaturaAccountDocument]) {
        let pending = documents.filter(\.isPending)
        let overdue = pending.filter { $0.isOverdue || $0.overdueDays > 0 }
        pendingCount = pending.count
        pendingPesos = pending.reduce(0) { $0 + ($1.balancePesos ?? 0) }
        nextDue = pending.filter { !($0.isOverdue || $0.overdueDays > 0) && $0.dueDate != nil }
            .min { $0.dueDate! < $1.dueDate! }
        overdueCount = overdue.count
        overduePesos = overdue.reduce(0) { $0 + ($1.balancePesos ?? 0) }
        maxOverdueDays = overdue.map(\.overdueDays).max() ?? 0
    }
}

/// Crédito y bloqueo (GSP `authCommercialInfo`).
public struct NaturaCredit: Codable, Sendable, Equatable {
    public let availablePesos: Int?
    public let limitPesos: Int?
    public let additionalPesos: Int?
    public let isBlocked: Bool

    public init(availablePesos: Int?, limitPesos: Int?, additionalPesos: Int?, isBlocked: Bool) {
        self.availablePesos = availablePesos
        self.limitPesos = limitPesos
        self.additionalPesos = additionalPesos
        self.isBlocked = isBlocked
    }
}

/// Oferta del ciclo (GSP `cardSection`): descuento, promoción o regalo, en un texto corto para la lista.
public enum CycleOffer {
    public static func text(discountTags: [String], percentageDiscount: Int?, promotion: String?,
                            promotionLabels: [String], gifts: [String]) -> String? {
        var parts: [String] = []
        let tags = discountTags.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if !tags.isEmpty {
            parts.append(tags.joined(separator: " · "))
        } else if let percentageDiscount, percentageDiscount > 0 {
            parts.append("\(percentageDiscount)%")
        }
        let promotionText = ([promotion].compactMap { $0 } + promotionLabels)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if let first = promotionText.first { parts.append(first) }
        let giftNames = gifts.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if !giftNames.isEmpty { parts.append("Regalo: " + giftNames.joined(separator: ", ")) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Hay oferta si hay texto o si el precio vigente es menor al normal.
    public static func isOffer(text: String?, regularPesos: Int?, currentPesos: Int?) -> Bool {
        if text != nil { return true }
        guard let regularPesos, let currentPesos else { return false }
        return currentPesos < regularPesos
    }
}
