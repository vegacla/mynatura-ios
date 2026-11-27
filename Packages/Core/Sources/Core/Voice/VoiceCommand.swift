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

/// Cuánto llegó de una línea de pedido Natura.
public enum ReceiveAmount: Equatable, Sendable {
    /// "llegaron cuatro": queda en 4.
    case received(Int)
    /// "falta uno": queda en pedido − 1.
    case missing(Int)
    /// "llegó completo": queda en lo pedido.
    case complete
    /// "otro más", "llegó el Kaiak": suma, como un escaneo.
    case increment(Int)
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
    /// Recepción: `product` nil = la última línea mencionada ("llegaron dos, falta uno").
    case receive(product: ProductRef?, amount: ReceiveAmount)
    /// Conciliación: "conté siete".
    case physicalCount(Int)
    /// Consulta desde cualquier pantalla: "¿cuánto me queda de Kaiak?".
    case query(VoiceQuery)
    /// "Ir a recepción", "abre la revista", "abre el pedido de María".
    case navigate(VoiceDestination)
    case undo
    case done
    /// Trozo que no se entendió; se muestra con "?" para corregirlo a mano.
    case unrecognized(String)
}
