import Core
import SwiftUI

/// Campo de dinero CLP: muestra "$12.990" y edita solo dígitos.
public struct MoneyField: View {
    let title: String
    @Binding var money: Money
    @State private var text: String = ""
    @FocusState private var focused: Bool

    public init(_ title: String, money: Binding<Money>) {
        self.title = title
        _money = money
    }

    public var body: some View {
        TextField(title, text: $text)
            .keyboardType(.numberPad)
            .multilineTextAlignment(.trailing)
            .monospacedDigit()
            .focused($focused)
            .onAppear { text = money.formatted }
            .onChange(of: focused) { _, isFocused in
                text = isFocused ? (money.pesos == 0 ? "" : String(money.pesos)) : money.formatted
            }
            .onChange(of: text) { _, newValue in
                guard focused else { return }
                money = Money.parse(newValue) ?? .zero
            }
            .onChange(of: money) { _, newValue in
                if !focused { text = newValue.formatted }
            }
            .accessibilityLabel(title)
            .accessibilityValue(money.formatted)
    }
}
