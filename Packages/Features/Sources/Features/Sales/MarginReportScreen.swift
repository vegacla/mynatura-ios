import Core
import DesignSystem
import Persistence
import SwiftData
import SwiftUI

/// Reporte de ganancias (docs/local-first-migration.md §4.6): ventas − costo − obsequios, con costo de lotes local.
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
        let report = ProfitReport.build(inPeriod.flatMap(\.outflowLines))
        let salesCount = inPeriod.filter { $0.kind == .sale }.count
        let giftsCount = inPeriod.filter { $0.kind == .gift }.count
        let byProduct = productMargins(inPeriod.filter { $0.kind == .sale })
        List {
            Picker("Periodo", selection: $period) {
                ForEach(Period.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            Section {
                HStack(spacing: 8) {
                    MiniStat("Venta", value: report.revenue.formatted)
                    MiniStat("Costo", value: report.costOfSales.formatted)
                    MiniStat("Ganancia", value: report.profit.formatted, tone: report.profit.pesos >= 0 ? .success : .danger)
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                LabeledContent("Margen bruto de ventas") { MoneyText(report.grossMargin) }
                LabeledContent("Obsequios (pérdida)") { MoneyText(Money(pesos: -report.giftLoss.pesos)) }
                LabeledContent("Ganancia") { MoneyText(report.profit).fontWeight(.semibold) }
                LabeledContent("Ventas", value: "\(salesCount)")
                if giftsCount > 0 { LabeledContent("Obsequios", value: "\(giftsCount)") }
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    if report.unitsAtReferenceCost > 0 {
                        Text("\(report.unitsAtReferenceCost) unidad(es) gratis de Natura valorizadas a precio de referencia (\(report.referenceCostAmount.formatted)).")
                    }
                    if report.unitsWithoutKnownCost > 0 {
                        Text("\(report.unitsWithoutKnownCost) unidad(es) gratis sin costo conocido (nunca compradas): costo 0.")
                    }
                    if !report.isComplete {
                        Text("\(report.linesWithPendingCost) línea(s) con costo pendiente: la ganancia está incompleta. Completa el costo del lote en la ficha del producto.")
                    }
                }
            }
            Section("Por producto (ventas)") {
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
        .navigationTitle("Ganancias")
    }

    private func productMargins(_ sales: [LocalSale]) -> [(name: String, units: Int, revenue: Money, margin: Money)] {
        var totals: [String: (units: Int, revenue: Int, cost: Int)] = [:]
        for sale in sales {
            for line in sale.lines {
                var entry = totals[line.productName] ?? (0, 0, 0)
                entry.units += line.quantity
                entry.revenue += line.finalPesos * line.quantity
                entry.cost += line.effectiveAllocations.reduce(0) { $0 + ($1.totalCost?.pesos ?? 0) }
                totals[line.productName] = entry
            }
        }
        return totals
            .map { (name: $0.key, units: $0.value.units, revenue: Money(pesos: $0.value.revenue), margin: Money(pesos: $0.value.revenue - $0.value.cost)) }
            .sorted { $0.margin > $1.margin }
    }
}
