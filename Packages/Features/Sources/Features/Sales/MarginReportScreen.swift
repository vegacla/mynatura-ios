import Core
import DesignSystem
import Persistence
import SwiftData
import SwiftUI

/// Reporte de margen (etapa 10): venta − costo de lotes (FIFO/LIFO calculado por el backend).
struct MarginReportScreen: View {
    enum Period: String, CaseIterable, Identifiable {
        case today = "Hoy", week = "7 días", month = "Este mes", days30 = "30 días", all = "Todo"
        var id: String { rawValue }

        func start(now: Date = .now, calendar: Calendar = .current) -> Date? {
            switch self {
            case .today: calendar.startOfDay(for: now)
            case .week: calendar.date(byAdding: .day, value: -7, to: now)
            case .month: calendar.dateInterval(of: .month, for: now)?.start
            case .days30: calendar.date(byAdding: .day, value: -30, to: now)
            case .all: nil
            }
        }
    }

    @Query private var sales: [LocalSale]
    @State private var period: Period = .month
    let sellerId: String

    init(sellerId: String) {
        self.sellerId = sellerId
        _sales = Query(filter: #Predicate<LocalSale> { $0.sellerId == sellerId }, sort: \.occurredAt, order: .reverse)
    }

    var body: some View {
        let start = period.start()
        let inPeriod = sales.filter { sale in start.map { sale.occurredAt >= $0 } ?? true }
        let withCost = inPeriod.filter { $0.cost != nil }
        let summary = withCost.reduce(into: MarginSummary()) { result, sale in
            result.revenue = result.revenue + sale.total
            result.cost = result.cost + (sale.cost ?? .zero)
            result.units += sale.units
            result.salesCount += 1
        }
        let byProduct = productMargins(withCost)
        List {
            Picker("Periodo", selection: $period) {
                ForEach(Period.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            Section {
                HStack(spacing: 8) {
                    MiniStat("Venta", value: summary.revenue.formatted)
                    MiniStat("Costo", value: summary.cost.formatted)
                    MiniStat("Margen", value: summary.margin.formatted, tone: summary.margin.pesos >= 0 ? .success : .danger)
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                LabeledContent("Ventas", value: "\(summary.salesCount)")
                LabeledContent("Unidades", value: "\(summary.units)")
                if let rate = summary.marginRate {
                    LabeledContent("Margen sobre venta", value: rate.formatted(.percent.precision(.fractionLength(1))))
                }
            } footer: {
                if inPeriod.count > withCost.count {
                    Text("\(inPeriod.count - withCost.count) venta(s) sin costo aún (pendientes de sincronizar) no se incluyen.")
                }
            }
            Section("Por producto") {
                ForEach(byProduct, id: \.name) { item in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(item.name).font(.subheadline)
                            Text("\(item.units) u · venta \(item.revenue.formatted)").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        MoneyText(item.margin).font(.subheadline.weight(.semibold))
                    }
                }
            }
        }
        .navigationTitle("Margen")
    }

    private func productMargins(_ sales: [LocalSale]) -> [(name: String, units: Int, revenue: Money, margin: Money)] {
        var totals: [String: (units: Int, revenue: Int, cost: Int)] = [:]
        for sale in sales {
            for line in sale.lines {
                var entry = totals[line.productName] ?? (0, 0, 0)
                entry.units += line.quantity
                entry.revenue += line.finalPesos * line.quantity
                entry.cost += (line.costUnitPesos ?? 0) * line.quantity
                totals[line.productName] = entry
            }
        }
        return totals
            .map { (name: $0.key, units: $0.value.units, revenue: Money(pesos: $0.value.revenue), margin: Money(pesos: $0.value.revenue - $0.value.cost)) }
            .sorted { $0.margin > $1.margin }
    }
}
