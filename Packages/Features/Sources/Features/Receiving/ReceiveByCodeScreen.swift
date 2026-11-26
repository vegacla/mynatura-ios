import Core
import DesignSystem
import Persistence
import SwiftData
import SwiftUI
import Sync

/// Recibir por código (§4.6): campo + escáner continuo; cada lectura suma 1 a la línea.
struct ReceiveByCodeScreen: View {
    @Environment(SyncEngine.self) private var sync
    @Query private var orders: [NaturaOrder]
    @Query private var lines: [NaturaOrderLine]
    @State private var code = ""
    @State private var scanning = false
    @State private var dictating = false
    @State private var feedback: (text: String, isError: Bool)?
    @FocusState private var focused: Bool
    let orderId: String
    let sellerId: String

    init(orderId: String, sellerId: String) {
        self.orderId = orderId
        self.sellerId = sellerId
        _orders = Query(filter: #Predicate<NaturaOrder> { $0.id == orderId })
        _lines = Query(filter: #Predicate<NaturaOrderLine> { $0.orderId == orderId }, sort: \.position)
    }

    var body: some View {
        let isClosed = orders.first?.isClosed ?? true
        List {
            Section {
                HStack {
                    TextField("EAN o SKU", text: $code)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focused)
                        .submitLabel(.done)
                        .onSubmit { submit(code) }
                    ScannerButton { scanning = true }
                }
                .disabled(isClosed)
                if let feedback {
                    AlertBanner(feedback.text, tone: feedback.isError ? .danger : .success,
                                systemImage: feedback.isError ? "xmark.octagon.fill" : "checkmark.circle.fill")
                }
            } footer: {
                Text(isClosed ? "Pedido cerrado." : "Mínimo \(Normalize.minimumScanCodeLength) caracteres. Cada lectura suma 1 unidad.")
            }
            Section("Líneas") {
                ForEach(lines) { line in
                    ReceivingLineRow(line: line, stock: nil, isClosed: isClosed, sellerId: sellerId, editable: false)
                }
            }
        }
        .navigationTitle("Recibir por código")
        .navigationBarTitleDisplayMode(.inline)
        .syncStatusToolbar(sellerId: sellerId)
        .onAppear { focused = true }
        .sheet(isPresented: $scanning) {
            ScannerSheet(title: "Escaneo continuo", continuous: true) { value in submit(value) }
        }
        .toolbar {
            ToolbarItem(placement: .bottomBar) {
                Button { dictating = true } label: { Label("Dictar", systemImage: "mic.fill").labelStyle(.titleAndIcon) }
                    .disabled(isClosed || lines.isEmpty)
            }
        }
        .sheet(isPresented: $dictating) {
            ReceivingVoiceSheet(lines: lines, sellerId: sellerId)
                .presentationDetents([.medium, .large])
        }
    }

    private func submit(_ value: String) {
        switch sync.scanReceiving(sellerId: sellerId, orderId: orderId, code: value) {
        case .matched(let name, let received, let ordered):
            feedback = ("\(name): \(received) / \(ordered)", false)
            Haptics.success()
        case .failed(let message):
            feedback = (message, true)
            Haptics.error()
        }
        code = ""
    }
}
