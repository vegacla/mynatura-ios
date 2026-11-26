import Foundation

/// Pantalla desde la que se habla: define qué comandos valen y cómo se lee un número suelto.
public enum VoiceContext: String, Sendable, Equatable, CaseIterable {
    case customerOrder
    case naturaDraft
    case receiving
    case reconciliation
    case cart
    case global
}

/// Producto mencionado: por código Natura o por texto libre (se resuelve con `ProductMatcher`).
public enum ProductRef: Equatable, Sendable {
    case sku(String)
    case text(String)
}

public enum CycleRef: Equatable, Sendable {
    case current
    /// Como se dijo: "202619" o solo "19"; la pantalla completa el año.
    case number(Int)
}

/// Lo que la voz propone. La pantalla lo muestra como chip y solo se aplica con un toque.
public enum VoiceCommand: Equatable, Sendable {
    case setCustomer(name: String)
    case setCycle(CycleRef)
    case addLine(quantity: Int, product: ProductRef, price: ParsedPrice?)
    /// "otro más", "otros dos": suma a la última línea.
    case repeatLast(quantity: Int)
    case setQuantity(product: ProductRef, quantity: Int)
    case removeLine(ProductRef)
    case note(String)
    case undo
    case done
    /// Trozo que no se entendió; se muestra con "?" para corregirlo a mano.
    case unrecognized(String)
}
