import Foundation
import Testing
@testable import Core

@Suite("Natura · cuenta y ofertas (M6)")
struct NaturaAccountTests {
    @Test func decodesAccountsAndSummarizes() throws {
        let json = #"""
        [{"number":1001,"orderingNumber":811111100,"isOpen":true,"isOverdue":false,"issueDate":"2026-11-20T03:00:00Z",
          "dueDate":"2026-12-10T03:00:00Z","originalValue":"190.614","currentBalance":"190.614","overdueDays":0,"orderStatus":null},
         {"number":1002,"orderingNumber":811111200,"isOpen":true,"isOverdue":false,"issueDate":"2026-11-22T03:00:00Z",
          "dueDate":"2026-12-05T03:00:00Z","originalValue":"55.025","currentBalance":"20.000","overdueDays":0,"orderStatus":null},
         {"number":1003,"orderingNumber":811111000,"isOpen":true,"isOverdue":true,"issueDate":"2026-10-20T03:00:00Z",
          "dueDate":"2026-11-10T03:00:00Z","originalValue":"30.000","currentBalance":"30.000","overdueDays":17,"orderStatus":null},
         {"number":1004,"orderingNumber":811110000,"isOpen":false,"isOverdue":false,"issueDate":"2026-09-20T03:00:00Z",
          "dueDate":"2026-10-10T03:00:00Z","originalValue":"80.000","currentBalance":"0","overdueDays":0,"orderStatus":null}]
        """#
        let documents = try NaturaAccounts.decode(Data(json.utf8))
        #expect(documents.count == 4)
        #expect(documents[0].number == "1001")
        #expect(documents[0].balancePesos == 190614)
        let summary = NaturaAccountSummary(documents: documents)
        #expect(summary.pendingCount == 3)
        #expect(summary.pendingPesos == 240614)
        #expect(summary.nextDue?.number == "1002")
        #expect(summary.overdueCount == 1)
        #expect(summary.overduePesos == 30000)
        #expect(summary.maxOverdueDays == 17)
        #expect(throws: NaturaParseError.invalidAccounts) { try NaturaAccounts.decode(Data("{}".utf8)) }
    }

    @Test func offerText() {
        #expect(CycleOffer.text(discountTags: ["37%"], percentageDiscount: 37, promotion: nil, promotionLabels: [],
                                gifts: []) == "37%")
        #expect(CycleOffer.text(discountTags: [], percentageDiscount: 20, promotion: nil, promotionLabels: ["Lleva 2 y paga 1"],
                                gifts: ["Bolsa"]) == "20% · Lleva 2 y paga 1 · Regalo: Bolsa")
        #expect(CycleOffer.text(discountTags: [" "], percentageDiscount: 0, promotion: nil, promotionLabels: [], gifts: []) == nil)
        #expect(CycleOffer.isOffer(text: nil, regularPesos: 31198, currentPesos: 23512))
        #expect(!CycleOffer.isOffer(text: nil, regularPesos: 9990, currentPesos: 9990))
    }
}
