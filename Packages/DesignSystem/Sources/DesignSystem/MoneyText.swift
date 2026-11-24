import Core
import SwiftUI

/// Monto en pesos CLP ("$12.990"), "—" si no hay valor.
public struct MoneyText: View {
    let money: Money?

    public init(_ money: Money?) {
        self.money = money
    }

    public var body: some View {
        Text(money?.formatted ?? "—").monospacedDigit()
    }
}
