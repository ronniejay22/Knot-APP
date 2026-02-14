//
//  MerchantHandoffTests.swift
//  KnotTests
//
//  Created on February 12, 2026.
//  Step 9.3: Tests for external merchant handoff service, DTOs, and handoff flow.
//

import XCTest
import SwiftUI
@testable import Knot

// MARK: - MerchantHandoffService Tests

@MainActor
final class MerchantHandoffServiceTests: XCTestCase {

    /// Verify handoff returns false for an empty URL string.
    func testEmptyURLReturnsFalse() async {
        let result = await MerchantHandoffService.openMerchantURL(
            urlString: "",
            recommendationId: "test-id"
        )
        XCTAssertFalse(result, "Empty URL string should return false")
    }

    /// Verify handoff returns false for a malformed URL.
    func testMalformedURLReturnsFalse() async {
        let result = await MerchantHandoffService.openMerchantURL(
            urlString: "not a url at all !!!",
            recommendationId: "test-id"
        )
        XCTAssertFalse(result, "Malformed URL should return false")
    }

    /// Verify handoff returns true for a valid HTTPS URL.
    func testValidHTTPSURLReturnsTrue() async {
        let result = await MerchantHandoffService.openMerchantURL(
            urlString: "https://www.amazon.com/dp/B09V3KXJPB",
            recommendationId: "test-id"
        )
        XCTAssertTrue(result, "Valid HTTPS URL should return true")
    }

    /// Verify handoff returns true for a valid HTTP URL.
    func testValidHTTPURLReturnsTrue() async {
        let result = await MerchantHandoffService.openMerchantURL(
            urlString: "http://example.com/product/123",
            recommendationId: "rec-123"
        )
        XCTAssertTrue(result, "Valid HTTP URL should return true")
    }
}

// MARK: - Handoff Feedback DTO Tests

final class HandoffFeedbackDTOTests: XCTestCase {

    /// Verify RecommendationFeedbackPayload encodes "handoff" action correctly.
    func testFeedbackPayloadEncodesHandoffAction() throws {
        let payload = RecommendationFeedbackPayload(
            recommendationId: "rec-handoff-123",
            action: "handoff"
        )

        let data = try JSONEncoder().encode(payload)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertEqual(json?["recommendation_id"] as? String, "rec-handoff-123")
        XCTAssertEqual(json?["action"] as? String, "handoff")
    }
}

// MARK: - ViewModel Handoff State Tests

@MainActor
final class ViewModelHandoffTests: XCTestCase {

    /// Verify confirmSelection clears state after execution.
    func testConfirmSelectionClearsState() async {
        let vm = RecommendationsViewModel()
        let item = makeTestRecommendation(id: "handoff-1", title: "Test Handoff")

        vm.selectRecommendation(item)
        XCTAssertTrue(vm.showConfirmationSheet)
        XCTAssertNotNil(vm.selectedRecommendation)

        await vm.confirmSelection()

        XCTAssertFalse(vm.showConfirmationSheet)
        XCTAssertNil(vm.selectedRecommendation)
    }

    /// Verify confirmSelection is a no-op when no recommendation is selected.
    func testConfirmSelectionNoOpWithoutSelection() async {
        let vm = RecommendationsViewModel()

        // No selection — should not crash
        await vm.confirmSelection()

        XCTAssertFalse(vm.showConfirmationSheet)
        XCTAssertNil(vm.selectedRecommendation)
    }

    // MARK: - Helpers

    private func makeTestRecommendation(
        id: String,
        title: String
    ) -> RecommendationItemResponse {
        let json = """
        {
            "id": "\(id)",
            "recommendation_type": "gift",
            "title": "\(title)",
            "description": "Test description",
            "price_cents": 5000,
            "currency": "USD",
            "external_url": "https://www.amazon.com/dp/B09V3KXJPB",
            "image_url": null,
            "merchant_name": "Amazon",
            "source": "amazon",
            "location": null,
            "interest_score": 0.8,
            "vibe_score": 0.7,
            "love_language_score": 0.6,
            "final_score": 0.7
        }
        """.data(using: .utf8)!
        return try! JSONDecoder().decode(RecommendationItemResponse.self, from: json)
    }
}

// MARK: - DeepLinkRecommendationView Handoff Tests

@MainActor
final class DeepLinkHandoffTests: XCTestCase {

    /// Verify the DeepLinkRecommendationView renders without crashing.
    func testDeepLinkViewRenders() {
        let view = DeepLinkRecommendationView(
            recommendationId: "deep-link-123",
            onDismiss: {}
        )
        let hostingController = UIHostingController(rootView: view)
        XCTAssertNotNil(hostingController.view,
                        "DeepLinkRecommendationView should render a valid view")
    }
}
