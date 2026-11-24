import SwiftUI

/// Stepper de cantidad con valor visible y límites (≥ 44 pt de objetivo táctil).
public struct QuantityStepper: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>

    public init(_ title: String, value: Binding<Int>, in range: ClosedRange<Int>) {
        self.title = title
        _value = value
        self.range = range
    }

    public var body: some View {
        Stepper(value: $value, in: range) {
            HStack {
                Text(title)
                Spacer()
                Text("\(value)").font(.body.monospacedDigit().weight(.semibold))
            }
        }
        .accessibilityValue("\(value)")
    }
}
