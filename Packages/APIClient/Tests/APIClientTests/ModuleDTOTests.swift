import Foundation
import Testing
@testable import APIClient

@Suite("Module DTOs")
struct ModuleDTOTests {
    @Test func naturaOrderDetailFlattensOrderFields() throws {
        let json = #"""
        {"order":{"id":"o1","externalOrderId":"e1","orderNumber":"123","cycle":202606,"subCycle":null,
        "orderedAt":"2026-03-01T10:00:00.000Z","deliveredAt":null,"statusName":"Entregado","itemsQuantity":3,
        "totalValueCents":29990,"receiptOcrStatus":null,"receiptOcrProcessedAt":null,"receivingClosedAt":null,
        "receivingReviewStatus":"draft","receivedUnitsQuantity":0,"pendingUnitsQuantity":3,"receivingStatus":"pending",
        "lines":[{"id":"l1","naturaSku":"70983","productName":"Kaiak","quantity":3,"purchaseUnitPriceCents":9990,
        "suggestedSaleUnitPriceCents":null,"proposedSuggestedSaleUnitPriceCents":12990,"receivedConfirmationQuantity":0,
        "proposedReceivedConfirmationQuantity":null,"receivedConfirmedAt":null,"barcodes":[]}]}}
        """#
        let response = try JSONCoding.decoder.decode(NaturaOrderDetailResponseDTO.self, from: Data(json.utf8))
        #expect(response.order.order.orderNumber == "123")
        #expect(response.order.lines.first?.proposedSuggestedSaleUnitPriceCents == 12990)
    }

    @Test func lineUpdateEncodesNullPrice() throws {
        let data = try JSONCoding.encoder.encode(UpdateNaturaOrderLineInputDTO(suggestedSaleUnitPriceCents: nil, receivedConfirmationQuantity: 2))
        #expect(String(data: data, encoding: .utf8) == #"{"receivedConfirmationQuantity":2,"suggestedSaleUnitPriceCents":null}"#)
    }

    @Test func customerInputEncodesNulls() throws {
        let data = try JSONCoding.encoder.encode(CustomerInputDTO(displayName: "Ana", rut: nil, phone: "+569", notes: nil))
        #expect(String(data: data, encoding: .utf8) == #"{"displayName":"Ana","notes":null,"phone":"+569","rut":null}"#)
    }

    @Test func customerOrderDetailDecodes() throws {
        let json = #"""
        {"order":{"id":"co1","customerId":"c1","customerDisplayName":"Ana","cycle":202606,"status":"draft","note":null,
        "orderedAt":"2026-03-01T10:00:00Z","createdAt":"2026-03-01T10:00:00Z","updatedAt":"2026-03-01T10:00:00Z","lineCount":1,
        "lines":[{"id":"x","sellerProductId":"p1","productName":"Kaiak","naturaSku":"70983","quantity":2,
        "suggestedUnitPriceCents":12990,"finalUnitPriceCents":null,"note":null}]}}
        """#
        let response = try JSONCoding.decoder.decode(CustomerOrderDetailResponseDTO.self, from: Data(json.utf8))
        #expect(response.order.order.customerDisplayName == "Ana")
        #expect(response.order.lines.count == 1)
    }

    @Test func salesDecodeAndDuplicateDetection() throws {
        let json = #"{"sales":[{"id":"s1","clientMutationId":"m1","occurredAt":"2026-03-01T10:00:00.000Z","note":null,"customerDisplayName":null,"lines":[{"id":"l","sellerProductId":"p","productName":"A","naturaSku":"1","quantity":1,"suggestedUnitPriceCents":null,"finalUnitPriceCents":0,"pricingReasonCode":"gift_manual","costUnitPriceCents":500}]}]}"#
        let response = try JSONCoding.decoder.decode(SaleListResponseDTO.self, from: Data(json.utf8))
        #expect(response.sales.first?.lines.first?.costUnitPriceCents == 500)
        #expect(APIError.validation(message: "La venta ya fue registrada previamente.").isDuplicateSale)
        #expect(!APIError.validation(message: "Stock insuficiente").isDuplicateSale)
    }

    @Test func endpointsPaths() {
        let base = URL(string: "http://h")!
        #expect(Endpoint<CatalogProductResponseDTO>.addBarcode(sellerProductId: "p 1", ean: "123").url(relativeTo: base)?.absoluteString
                == "http://h/api/catalog/products/p%201/barcodes")
        #expect(Endpoint<NaturaOrderDetailResponseDTO>.receivingReview(orderId: "o1", close: true).method == .patch)
        #expect(Endpoint<MasterProductLookupDTO>.masterProductLookup(sku: "70983").url(relativeTo: base)?.absoluteString
                == "http://h/api/catalog/master-products/lookup?sku=70983")
    }

    @Test func multipartBody() {
        let file = MultipartFile(fieldName: "file", fileName: "b.jpg", mimeType: "image/jpeg", data: Data([1, 2]), boundary: "XX")
        #expect(file.contentType == "multipart/form-data; boundary=XX")
        let text = String(decoding: file.body, as: UTF8.self)
        #expect(text.hasPrefix("--XX\r\nContent-Disposition: form-data; name=\"file\"; filename=\"b.jpg\"\r\n"))
        #expect(text.hasSuffix("\r\n--XX--\r\n"))
    }

    @Test func idempotencyKeyAndTimeoutAreSent() async throws {
        let transport = FakeTransport([json(201, #"{"customer":{"id":"c1","displayName":"Ana","rut":null,"phone":null,"notes":null,"createdAt":"2026-03-01T10:00:00Z","updatedAt":"2026-03-01T10:00:00Z"}}"#)])
        let client = LiveAPIClient(baseURL: { baseURL }, transport: transport, credentials: InMemoryCredentialStore())
        _ = try await client.send(Endpoint<CustomerResponseDTO>
            .createCustomer(CustomerInputDTO(displayName: "Ana", rut: nil, phone: nil, notes: nil))
            .idempotent("m-1"))
        #expect(transport.requests[0].headers["Idempotency-Key"] == "m-1")
        #expect(transport.requests[0].timeout == nil)
        #expect(Endpoint<StartImportResponseDTO>.importDeliveredOrders(customerCode: "1", password: "x").timeout == 600)
        #expect(Endpoint<ReceiptOcrResponseDTO>.receiptOcr(orderId: "o", jpeg: Data()).timeout == 180)
    }

    @Test func multipartContentTypeIsSent() async throws {
        let transport = FakeTransport([json(200, #"{"order":{"id":"o1","externalOrderId":"e1","orderNumber":"1","cycle":1,"subCycle":null,"orderedAt":"2026-03-01T10:00:00Z","deliveredAt":null,"statusName":"Entregado","itemsQuantity":0,"totalValueCents":0,"receiptOcrStatus":"succeeded","receiptOcrProcessedAt":null,"receivingClosedAt":null,"receivingReviewStatus":"draft","receivedUnitsQuantity":0,"pendingUnitsQuantity":0,"receivingStatus":"pending"},"ocr":{"status":"succeeded","processedAt":"2026-03-01T10:00:00Z","matchedLineCount":0,"unmatchedSkus":[],"extractedRows":[]}}"#)])
        let client = LiveAPIClient(baseURL: { baseURL }, transport: transport, credentials: InMemoryCredentialStore())
        let response = try await client.send(.receiptOcr(orderId: "o1", jpeg: Data([0xFF])))
        #expect(response.ocr.status == "succeeded")
        #expect(transport.requests[0].headers["Content-Type"]?.hasPrefix("multipart/form-data; boundary=") == true)
    }
}
