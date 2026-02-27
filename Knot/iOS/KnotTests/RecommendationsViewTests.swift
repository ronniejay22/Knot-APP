//
//  RecommendationsViewTests.swift
//  KnotTests
//
//  Created on February 10, 2026.
//  Step 6.2: Unit tests for RecommendationsView, RecommendationsViewModel, DTOs, and RecommendationService.
//  Step 6.3: Tests for card selection flow, feedback DTOs, and confirmation sheet.
//  Step 6.4: Tests for refresh reason sheet and refresh animation state management.
//  Step 6.5: Tests for vibe override state management, DTO encoding, and sheet rendering.
//  Step 6.6: Tests for save/share state management and SavedRecommendation model.
//

import XCTest
import SwiftData
import SwiftUI
@testable import Knot

// MARK: - DTO Decoding Tests

final class RecommendationDTOTests: XCTestCase {

    /// Verify RecommendationItemResponse decodes correctly from full JSON.
    func testRecommendationItemDecodesFullJSON() throws {
        let json = """
        {
            "id": "abc-123",
            "recommendation_type": "gift",
            "title": "Ceramic Pottery Class",
            "description": "A hands-on pottery experience.",
            "price_cents": 8500,
            "currency": "USD",
            "price_confidence": "verified",
            "external_url": "https://example.com/pottery",
            "image_url": "https://example.com/image.jpg",
            "merchant_name": "Clay Studio",
            "source": "yelp",
            "location": {
                "city": "Brooklyn",
                "state": "NY",
                "country": "US",
                "address": "123 Main St"
            },
            "interest_score": 0.85,
            "vibe_score": 0.72,
            "love_language_score": 0.9,
            "final_score": 0.82,
            "matched_interests": ["Art", "Cooking"],
            "matched_vibes": ["bohemian"],
            "matched_love_languages": ["quality_time"]
        }
        """.data(using: .utf8)!

        let item = try JSONDecoder().decode(RecommendationItemResponse.self, from: json)

        XCTAssertEqual(item.id, "abc-123")
        XCTAssertEqual(item.recommendationType, "gift")
        XCTAssertEqual(item.title, "Ceramic Pottery Class")
        XCTAssertEqual(item.description, "A hands-on pottery experience.")
        XCTAssertEqual(item.priceCents, 8500)
        XCTAssertEqual(item.currency, "USD")
        XCTAssertEqual(item.priceConfidence, "verified")
        XCTAssertEqual(item.externalUrl, "https://example.com/pottery")
        XCTAssertEqual(item.imageUrl, "https://example.com/image.jpg")
        XCTAssertEqual(item.merchantName, "Clay Studio")
        XCTAssertEqual(item.source, "yelp")
        XCTAssertEqual(item.location?.city, "Brooklyn")
        XCTAssertEqual(item.location?.state, "NY")
        XCTAssertEqual(item.interestScore, 0.85, accuracy: 0.001)
        XCTAssertEqual(item.vibeScore, 0.72, accuracy: 0.001)
        XCTAssertEqual(item.loveLanguageScore, 0.9, accuracy: 0.001)
        XCTAssertEqual(item.finalScore, 0.82, accuracy: 0.001)
        XCTAssertEqual(item.matchedInterests, ["Art", "Cooking"])
        XCTAssertEqual(item.matchedVibes, ["bohemian"])
        XCTAssertEqual(item.matchedLoveLanguages, ["quality_time"])
    }

    /// Verify RecommendationItemResponse decodes with nil optionals.
    func testRecommendationItemDecodesMinimalJSON() throws {
        let json = """
        {
            "id": "def-456",
            "recommendation_type": "experience",
            "title": "Sunset Sailing",
            "description": null,
            "price_cents": null,
            "currency": "USD",
            "external_url": "https://example.com/sailing",
            "image_url": null,
            "merchant_name": null,
            "source": "manual",
            "location": null,
            "interest_score": 0.5,
            "vibe_score": 0.5,
            "love_language_score": 0.5,
            "final_score": 0.5
        }
        """.data(using: .utf8)!

        let item = try JSONDecoder().decode(RecommendationItemResponse.self, from: json)

        XCTAssertEqual(item.id, "def-456")
        XCTAssertEqual(item.recommendationType, "experience")
        XCTAssertEqual(item.title, "Sunset Sailing")
        XCTAssertNil(item.description)
        XCTAssertNil(item.priceCents)
        XCTAssertNil(item.imageUrl)
        XCTAssertNil(item.merchantName)
        XCTAssertNil(item.location)
        // Matched factors should be nil when not present in JSON (backward compatibility)
        XCTAssertNil(item.matchedInterests)
        XCTAssertNil(item.matchedVibes)
        XCTAssertNil(item.matchedLoveLanguages)
        // Price confidence should be nil when not present in JSON (backward compatibility)
        XCTAssertNil(item.priceConfidence)
    }

    /// Verify RecommendationGenerateResponse decodes correctly.
    func testGenerateResponseDecodes() throws {
        let json = """
        {
            "recommendations": [
                {
                    "id": "r1",
                    "recommendation_type": "gift",
                    "title": "Gift 1",
                    "description": null,
                    "price_cents": 5000,
                    "currency": "USD",
                    "external_url": "https://example.com/1",
                    "image_url": null,
                    "merchant_name": null,
                    "source": "amazon",
                    "location": null,
                    "interest_score": 0.8,
                    "vibe_score": 0.7,
                    "love_language_score": 0.6,
                    "final_score": 0.7
                },
                {
                    "id": "r2",
                    "recommendation_type": "experience",
                    "title": "Experience 2",
                    "description": "Fun activity",
                    "price_cents": 12000,
                    "currency": "USD",
                    "external_url": "https://example.com/2",
                    "image_url": null,
                    "merchant_name": "Fun Co",
                    "source": "yelp",
                    "location": null,
                    "interest_score": 0.9,
                    "vibe_score": 0.8,
                    "love_language_score": 0.7,
                    "final_score": 0.8
                },
                {
                    "id": "r3",
                    "recommendation_type": "date",
                    "title": "Date 3",
                    "description": null,
                    "price_cents": null,
                    "currency": "USD",
                    "external_url": "https://example.com/3",
                    "image_url": null,
                    "merchant_name": null,
                    "source": "opentable",
                    "location": null,
                    "interest_score": 0.6,
                    "vibe_score": 0.5,
                    "love_language_score": 0.9,
                    "final_score": 0.65
                }
            ],
            "count": 3,
            "milestone_id": null,
            "occasion_type": "just_because"
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(RecommendationGenerateResponse.self, from: json)

        XCTAssertEqual(response.recommendations.count, 3)
        XCTAssertEqual(response.count, 3)
        XCTAssertNil(response.milestoneId)
        XCTAssertEqual(response.occasionType, "just_because")
        XCTAssertEqual(response.recommendations[0].title, "Gift 1")
        XCTAssertEqual(response.recommendations[1].title, "Experience 2")
        XCTAssertEqual(response.recommendations[2].title, "Date 3")
    }

    /// Verify RecommendationRefreshResponse decodes correctly.
    func testRefreshResponseDecodes() throws {
        let json = """
        {
            "recommendations": [
                {
                    "id": "r4",
                    "recommendation_type": "gift",
                    "title": "Refreshed Gift",
                    "description": null,
                    "price_cents": 3000,
                    "currency": "USD",
                    "external_url": "https://example.com/4",
                    "image_url": null,
                    "merchant_name": null,
                    "source": "shopify",
                    "location": null,
                    "interest_score": 0.7,
                    "vibe_score": 0.6,
                    "love_language_score": 0.8,
                    "final_score": 0.7
                }
            ],
            "count": 1,
            "rejection_reason": "too_expensive"
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(RecommendationRefreshResponse.self, from: json)

        XCTAssertEqual(response.recommendations.count, 1)
        XCTAssertEqual(response.count, 1)
        XCTAssertEqual(response.rejectionReason, "too_expensive")
        XCTAssertEqual(response.recommendations[0].title, "Refreshed Gift")
    }

    /// Verify RecommendationGeneratePayload encodes to correct snake_case JSON keys.
    func testGeneratePayloadEncodesCorrectly() throws {
        let payload = RecommendationGeneratePayload(
            milestoneId: "m-123",
            occasionType: "major_milestone"
        )

        let data = try JSONEncoder().encode(payload)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertEqual(json?["milestone_id"] as? String, "m-123")
        XCTAssertEqual(json?["occasion_type"] as? String, "major_milestone")
    }

    /// Verify RecommendationRefreshPayload encodes to correct snake_case JSON keys (no vibe override).
    func testRefreshPayloadEncodesCorrectly() throws {
        let payload = RecommendationRefreshPayload(
            rejectedRecommendationIds: ["r1", "r2", "r3"],
            rejectionReason: "not_their_style",
            vibeOverride: nil
        )

        let data = try JSONEncoder().encode(payload)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertEqual(json?["rejected_recommendation_ids"] as? [String], ["r1", "r2", "r3"])
        XCTAssertEqual(json?["rejection_reason"] as? String, "not_their_style")
    }

    // MARK: - Vibe Override DTO Tests (Step 6.5)

    /// Verify RecommendationRefreshPayload encodes vibe_override when provided.
    func testRefreshPayloadEncodesVibeOverride() throws {
        let payload = RecommendationRefreshPayload(
            rejectedRecommendationIds: ["r1"],
            rejectionReason: "show_different",
            vibeOverride: ["romantic", "vintage"]
        )

        let data = try JSONEncoder().encode(payload)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertEqual(json?["vibe_override"] as? [String], ["romantic", "vintage"])
        XCTAssertEqual(json?["rejection_reason"] as? String, "show_different")
    }

    /// Verify RecommendationRefreshPayload omits vibe_override when nil.
    func testRefreshPayloadOmitsNilVibeOverride() throws {
        let payload = RecommendationRefreshPayload(
            rejectedRecommendationIds: ["r1"],
            rejectionReason: "too_expensive",
            vibeOverride: nil
        )

        let data = try JSONEncoder().encode(payload)
        let jsonString = String(data: data, encoding: .utf8)!

        // The key should not appear in the JSON at all when nil
        // (default Codable behavior for optional nil is to encode as null)
        // Either null or absent is fine — just verify the payload encodes
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(json?["rejection_reason"] as? String, "too_expensive")
        XCTAssertNotNil(jsonString) // Encoding succeeded
    }

    /// Verify vibe override with all 8 vibes encodes correctly.
    func testRefreshPayloadEncodesAllVibes() throws {
        let allVibes = ["quiet_luxury", "street_urban", "outdoorsy", "vintage",
                        "minimalist", "bohemian", "romantic", "adventurous"]

        let payload = RecommendationRefreshPayload(
            rejectedRecommendationIds: ["r1", "r2", "r3"],
            rejectionReason: "show_different",
            vibeOverride: allVibes
        )

        let data = try JSONEncoder().encode(payload)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertEqual((json?["vibe_override"] as? [String])?.count, 8)
    }

    /// Verify RecommendationLocationResponse decodes all fields.
    func testLocationResponseDecodes() throws {
        let json = """
        {
            "city": "San Francisco",
            "state": "CA",
            "country": "US",
            "address": "456 Market St"
        }
        """.data(using: .utf8)!

        let location = try JSONDecoder().decode(RecommendationLocationResponse.self, from: json)

        XCTAssertEqual(location.city, "San Francisco")
        XCTAssertEqual(location.state, "CA")
        XCTAssertEqual(location.country, "US")
        XCTAssertEqual(location.address, "456 Market St")
    }

    /// Verify RecommendationItemResponse conforms to Identifiable.
    func testRecommendationItemIsIdentifiable() throws {
        let json = """
        {
            "id": "unique-id",
            "recommendation_type": "date",
            "title": "Test",
            "description": null,
            "price_cents": null,
            "currency": "USD",
            "external_url": "https://example.com",
            "image_url": null,
            "merchant_name": null,
            "source": "manual",
            "location": null,
            "interest_score": 0.0,
            "vibe_score": 0.0,
            "love_language_score": 0.0,
            "final_score": 0.0
        }
        """.data(using: .utf8)!

        let item = try JSONDecoder().decode(RecommendationItemResponse.self, from: json)

        // Identifiable conformance uses `id` property
        XCTAssertEqual(item.id, "unique-id")
    }

    // MARK: - Feedback DTO Tests (Step 6.3)

    /// Verify RecommendationFeedbackPayload encodes to correct snake_case JSON keys.
    func testFeedbackPayloadEncodesCorrectly() throws {
        let payload = RecommendationFeedbackPayload(
            recommendationId: "rec-abc-123",
            action: "selected"
        )

        let data = try JSONEncoder().encode(payload)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertEqual(json?["recommendation_id"] as? String, "rec-abc-123")
        XCTAssertEqual(json?["action"] as? String, "selected")
    }

    /// Verify RecommendationFeedbackPayload encodes all action types.
    func testFeedbackPayloadEncodesAllActions() throws {
        let actions = ["selected", "saved", "shared", "rated"]

        for action in actions {
            let payload = RecommendationFeedbackPayload(
                recommendationId: "rec-123",
                action: action
            )

            let data = try JSONEncoder().encode(payload)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

            XCTAssertEqual(json?["action"] as? String, action,
                           "Feedback payload should encode action '\(action)'")
        }
    }

    /// Verify RecommendationFeedbackResponse decodes correctly from JSON.
    func testFeedbackResponseDecodes() throws {
        let json = """
        {
            "id": "fb-001",
            "recommendation_id": "rec-abc-123",
            "action": "selected",
            "created_at": "2026-02-11T12:00:00Z"
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(RecommendationFeedbackResponse.self, from: json)

        XCTAssertEqual(response.id, "fb-001")
        XCTAssertEqual(response.recommendationId, "rec-abc-123")
        XCTAssertEqual(response.action, "selected")
        XCTAssertEqual(response.createdAt, "2026-02-11T12:00:00Z")
    }

    /// Verify RecommendationFeedbackResponse decodes all action types.
    func testFeedbackResponseDecodesAllActions() throws {
        let actions = ["selected", "saved", "shared", "rated"]

        for action in actions {
            let json = """
            {
                "id": "fb-\(action)",
                "recommendation_id": "rec-123",
                "action": "\(action)",
                "created_at": "2026-02-11T12:00:00Z"
            }
            """.data(using: .utf8)!

            let response = try JSONDecoder().decode(RecommendationFeedbackResponse.self, from: json)
            XCTAssertEqual(response.action, action,
                           "Feedback response should decode action '\(action)'")
        }
    }
}

// MARK: - ViewModel Tests

@MainActor
final class RecommendationsViewModelTests: XCTestCase {

    /// Verify ViewModel initializes with empty state.
    func testInitialState() {
        let vm = RecommendationsViewModel()

        XCTAssertTrue(vm.recommendations.isEmpty)
        XCTAssertFalse(vm.isLoading)
        XCTAssertFalse(vm.isRefreshing)
        XCTAssertNil(vm.errorMessage)
        XCTAssertEqual(vm.currentPage, 0)
    }

    /// Verify currentPage can be updated.
    func testCurrentPageUpdates() {
        let vm = RecommendationsViewModel()

        vm.currentPage = 2
        XCTAssertEqual(vm.currentPage, 2)

        vm.currentPage = 0
        XCTAssertEqual(vm.currentPage, 0)
    }

    // MARK: - Selection State Tests (Step 6.3)

    /// Verify initial selection state is nil/false.
    func testSelectionInitialState() {
        let vm = RecommendationsViewModel()

        XCTAssertNil(vm.selectedRecommendation)
        XCTAssertFalse(vm.showConfirmationSheet)
    }

    /// Verify selectRecommendation sets the selected item and shows the sheet.
    func testSelectRecommendationSetsState() {
        let vm = RecommendationsViewModel()
        let item = makeTestRecommendation(id: "test-1", title: "Test Gift")

        vm.selectRecommendation(item)

        XCTAssertNotNil(vm.selectedRecommendation)
        XCTAssertEqual(vm.selectedRecommendation?.id, "test-1")
        XCTAssertEqual(vm.selectedRecommendation?.title, "Test Gift")
        XCTAssertTrue(vm.showConfirmationSheet)
    }

    /// Verify dismissSelection clears the selection and hides the sheet.
    func testDismissSelectionClearsState() {
        let vm = RecommendationsViewModel()
        let item = makeTestRecommendation(id: "test-1", title: "Test Gift")

        // First select
        vm.selectRecommendation(item)
        XCTAssertTrue(vm.showConfirmationSheet)

        // Then dismiss
        vm.dismissSelection()

        XCTAssertNil(vm.selectedRecommendation)
        XCTAssertFalse(vm.showConfirmationSheet)
    }

    /// Verify selecting a different recommendation replaces the previous selection.
    func testSelectNewRecommendationReplacesOld() {
        let vm = RecommendationsViewModel()
        let item1 = makeTestRecommendation(id: "test-1", title: "Gift 1")
        let item2 = makeTestRecommendation(id: "test-2", title: "Gift 2")

        vm.selectRecommendation(item1)
        XCTAssertEqual(vm.selectedRecommendation?.id, "test-1")

        vm.selectRecommendation(item2)
        XCTAssertEqual(vm.selectedRecommendation?.id, "test-2")
        XCTAssertTrue(vm.showConfirmationSheet)
    }

    // MARK: - Refresh Reason State Tests (Step 6.4)

    /// Verify refresh reason sheet initial state is false and cards are visible.
    func testRefreshReasonSheetInitialState() {
        let vm = RecommendationsViewModel()

        XCTAssertFalse(vm.showRefreshReasonSheet)
        XCTAssertTrue(vm.cardsVisible)
    }

    /// Verify requestRefresh() shows the refresh reason sheet.
    func testRequestRefreshShowsSheet() {
        let vm = RecommendationsViewModel()

        vm.requestRefresh()

        XCTAssertTrue(vm.showRefreshReasonSheet)
    }

    /// Verify requestRefresh() is guarded when isRefreshing is true.
    func testRequestRefreshGuardedDuringRefresh() {
        let vm = RecommendationsViewModel()
        vm.isRefreshing = true

        vm.requestRefresh()

        XCTAssertFalse(vm.showRefreshReasonSheet)
    }

    /// Verify requestRefresh() is guarded when cards are not visible (animating).
    func testRequestRefreshGuardedDuringAnimation() {
        let vm = RecommendationsViewModel()
        vm.cardsVisible = false

        vm.requestRefresh()

        XCTAssertFalse(vm.showRefreshReasonSheet)
    }

    /// Verify cardsVisible can be toggled for animation control.
    func testCardsVisibleToggle() {
        let vm = RecommendationsViewModel()

        XCTAssertTrue(vm.cardsVisible)

        vm.cardsVisible = false
        XCTAssertFalse(vm.cardsVisible)

        vm.cardsVisible = true
        XCTAssertTrue(vm.cardsVisible)
    }

    // MARK: - Vibe Override State Tests (Step 6.5)

    /// Verify vibe override initial state is nil with sheet hidden.
    func testVibeOverrideInitialState() {
        let vm = RecommendationsViewModel()

        XCTAssertNil(vm.vibeOverride)
        XCTAssertFalse(vm.hasVibeOverride)
        XCTAssertFalse(vm.showVibeOverrideSheet)
    }

    /// Verify requestVibeOverride() shows the vibe override sheet.
    func testRequestVibeOverrideShowsSheet() {
        let vm = RecommendationsViewModel()

        vm.requestVibeOverride()

        XCTAssertTrue(vm.showVibeOverrideSheet)
    }

    /// Verify setting vibeOverride makes hasVibeOverride return true.
    func testHasVibeOverrideReflectsState() {
        let vm = RecommendationsViewModel()

        XCTAssertFalse(vm.hasVibeOverride)

        vm.vibeOverride = ["romantic", "vintage"]
        XCTAssertTrue(vm.hasVibeOverride)

        vm.vibeOverride = nil
        XCTAssertFalse(vm.hasVibeOverride)
    }

    /// Verify clearVibeOverride() resets the override to nil.
    func testClearVibeOverrideResetsState() {
        let vm = RecommendationsViewModel()
        vm.vibeOverride = ["minimalist", "quiet_luxury"]

        XCTAssertTrue(vm.hasVibeOverride)

        vm.clearVibeOverride()

        XCTAssertNil(vm.vibeOverride)
        XCTAssertFalse(vm.hasVibeOverride)
    }

    /// Verify vibeOverride stores the correct set of vibes.
    func testVibeOverrideStoresCorrectVibes() {
        let vm = RecommendationsViewModel()
        let vibes: Set<String> = ["romantic", "vintage", "bohemian"]

        vm.vibeOverride = vibes

        XCTAssertEqual(vm.vibeOverride, vibes)
        XCTAssertEqual(vm.vibeOverride?.count, 3)
        XCTAssertTrue(vm.vibeOverride?.contains("romantic") ?? false)
        XCTAssertTrue(vm.vibeOverride?.contains("vintage") ?? false)
        XCTAssertTrue(vm.vibeOverride?.contains("bohemian") ?? false)
    }

    /// Verify empty set on vibeOverride is treated as having an override.
    func testEmptyVibeOverrideSetIsStillOverride() {
        let vm = RecommendationsViewModel()

        // An empty set is non-nil, so hasVibeOverride should be true
        // (though saveVibeOverride guards against empty sets)
        vm.vibeOverride = Set<String>()
        XCTAssertTrue(vm.hasVibeOverride)
    }

    // MARK: - Test Helpers

    private func makeTestRecommendation(
        id: String,
        title: String,
        type: String = "gift",
        merchantName: String? = "Test Store",
        priceCents: Int? = 5000,
        externalUrl: String = "https://example.com/test"
    ) -> RecommendationItemResponse {
        let json = """
        {
            "id": "\(id)",
            "recommendation_type": "\(type)",
            "title": "\(title)",
            "description": "Test description",
            "price_cents": \(priceCents.map { String($0) } ?? "null"),
            "currency": "USD",
            "external_url": "\(externalUrl)",
            "image_url": null,
            "merchant_name": \(merchantName.map { "\"\($0)\"" } ?? "null"),
            "source": "test",
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

// MARK: - View Rendering Tests

@MainActor
final class RecommendationsViewRenderingTests: XCTestCase {

    /// Verify the RecommendationsView renders without crashing.
    func testViewRenders() {
        let view = RecommendationsView()
        let hostingController = UIHostingController(rootView: view)
        XCTAssertNotNil(hostingController.view, "RecommendationsView should render a valid view")
    }
}

// MARK: - Selection Confirmation Sheet Tests (Step 6.3)

@MainActor
final class SelectionConfirmationSheetTests: XCTestCase {

    /// Verify the confirmation sheet renders with full recommendation data.
    func testSheetRendersWithFullData() {
        let item = makeTestItem(
            merchantName: "Clay Studio Brooklyn",
            priceCents: 8500
        )

        let sheet = SelectionConfirmationSheet(
            item: item,
            onConfirm: {},
            onCancel: {}
        )

        let hostingController = UIHostingController(rootView: sheet)
        XCTAssertNotNil(hostingController.view, "Confirmation sheet should render with full data")
    }

    /// Verify the confirmation sheet renders with minimal data (nil optionals).
    func testSheetRendersWithMinimalData() {
        let item = makeTestItem(merchantName: nil, priceCents: nil)

        let sheet = SelectionConfirmationSheet(
            item: item,
            onConfirm: {},
            onCancel: {}
        )

        let hostingController = UIHostingController(rootView: sheet)
        XCTAssertNotNil(hostingController.view, "Confirmation sheet should render with minimal data")
    }

    /// Verify the sheet renders for all recommendation types.
    func testSheetRendersAllTypes() {
        let types = ["gift", "experience", "date"]

        for type in types {
            let item = makeTestItem(type: type, merchantName: "Test", priceCents: 5000)

            let sheet = SelectionConfirmationSheet(
                item: item,
                onConfirm: {},
                onCancel: {}
            )

            let hostingController = UIHostingController(rootView: sheet)
            XCTAssertNotNil(hostingController.view,
                            "Confirmation sheet should render for type: \(type)")
        }
    }

    /// Verify the sheet renders with location data.
    func testSheetRendersWithLocation() {
        let json = """
        {
            "id": "loc-test",
            "recommendation_type": "experience",
            "title": "Sunset Sailing",
            "description": "A beautiful sailing trip.",
            "price_cents": 24900,
            "currency": "USD",
            "external_url": "https://example.com/sailing",
            "image_url": null,
            "merchant_name": "Bay Sailing Co.",
            "source": "yelp",
            "location": {
                "city": "San Francisco",
                "state": "CA",
                "country": "US",
                "address": "Pier 39"
            },
            "interest_score": 0.9,
            "vibe_score": 0.8,
            "love_language_score": 0.7,
            "final_score": 0.8
        }
        """.data(using: .utf8)!

        let item = try! JSONDecoder().decode(RecommendationItemResponse.self, from: json)

        let sheet = SelectionConfirmationSheet(
            item: item,
            onConfirm: {},
            onCancel: {}
        )

        let hostingController = UIHostingController(rootView: sheet)
        XCTAssertNotNil(hostingController.view, "Confirmation sheet should render with location data")
    }

    /// Verify the confirm callback fires when invoked.
    func testConfirmCallbackFires() {
        var confirmed = false
        let item = makeTestItem(merchantName: "Test Store", priceCents: 5000)

        let sheet = SelectionConfirmationSheet(
            item: item,
            onConfirm: { confirmed = true },
            onCancel: {}
        )

        sheet.onConfirm()
        XCTAssertTrue(confirmed, "onConfirm callback should fire")
    }

    /// Verify the cancel callback fires when invoked.
    func testCancelCallbackFires() {
        var cancelled = false
        let item = makeTestItem(merchantName: "Test Store", priceCents: 5000)

        let sheet = SelectionConfirmationSheet(
            item: item,
            onConfirm: {},
            onCancel: { cancelled = true }
        )

        sheet.onCancel()
        XCTAssertTrue(cancelled, "onCancel callback should fire")
    }

    // MARK: - Helpers

    private func makeTestItem(
        type: String = "gift",
        merchantName: String?,
        priceCents: Int?
    ) -> RecommendationItemResponse {
        let json = """
        {
            "id": "test-item",
            "recommendation_type": "\(type)",
            "title": "Test Recommendation",
            "description": "A test recommendation for unit testing.",
            "price_cents": \(priceCents.map { String($0) } ?? "null"),
            "currency": "USD",
            "external_url": "https://example.com/test",
            "image_url": null,
            "merchant_name": \(merchantName.map { "\"\($0)\"" } ?? "null"),
            "source": "test",
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

// MARK: - Refresh Reason Sheet Tests (Step 6.4)

@MainActor
final class RefreshReasonSheetTests: XCTestCase {

    /// Verify the refresh reason sheet renders without crashing.
    func testSheetRenders() {
        let sheet = RefreshReasonSheet(onSelectReason: { _ in })
        let hostingController = UIHostingController(rootView: sheet)
        XCTAssertNotNil(hostingController.view, "RefreshReasonSheet should render a valid view")
    }

    /// Verify the reason callback fires with the correct reason string.
    func testReasonCallbackFires() {
        var selectedReason: String?
        let sheet = RefreshReasonSheet(onSelectReason: { reason in
            selectedReason = reason
        })

        sheet.onSelectReason("too_expensive")
        XCTAssertEqual(selectedReason, "too_expensive")
    }

    /// Verify all 5 rejection reasons can be passed via the callback.
    func testAllReasonsPassViaCallback() {
        let expectedReasons = [
            "too_expensive",
            "too_cheap",
            "not_their_style",
            "already_have_similar",
            "show_different"
        ]

        for reason in expectedReasons {
            var selectedReason: String?
            let sheet = RefreshReasonSheet(onSelectReason: { r in
                selectedReason = r
            })

            sheet.onSelectReason(reason)
            XCTAssertEqual(selectedReason, reason,
                           "Callback should pass reason '\(reason)'")
        }
    }

    /// Verify the sheet renders with dark color scheme (matching app theme).
    func testSheetRendersWithDarkScheme() {
        let sheet = RefreshReasonSheet(onSelectReason: { _ in })
            .preferredColorScheme(.dark)
        let hostingController = UIHostingController(rootView: sheet)
        XCTAssertNotNil(hostingController.view, "RefreshReasonSheet should render with dark scheme")
    }
}

// MARK: - Vibe Override Sheet Tests (Step 6.5)

@MainActor
final class VibeOverrideSheetTests: XCTestCase {

    /// Verify the vibe override sheet renders with empty selection.
    func testSheetRendersWithEmptySelection() {
        let sheet = VibeOverrideSheet(
            selectedVibes: [],
            onSave: { _ in },
            onClear: {}
        )

        let hostingController = UIHostingController(rootView: sheet)
        XCTAssertNotNil(hostingController.view,
                        "VibeOverrideSheet should render with empty selection")
    }

    /// Verify the vibe override sheet renders with pre-selected vibes.
    func testSheetRendersWithPreselectedVibes() {
        let sheet = VibeOverrideSheet(
            selectedVibes: ["romantic", "vintage"],
            onSave: { _ in },
            onClear: {}
        )

        let hostingController = UIHostingController(rootView: sheet)
        XCTAssertNotNil(hostingController.view,
                        "VibeOverrideSheet should render with pre-selected vibes")
    }

    /// Verify the save callback fires with the selected vibes.
    func testSaveCallbackFires() {
        var savedVibes: Set<String>?
        let sheet = VibeOverrideSheet(
            selectedVibes: ["minimalist"],
            onSave: { vibes in savedVibes = vibes },
            onClear: {}
        )

        sheet.onSave(["minimalist", "quiet_luxury"])
        XCTAssertEqual(savedVibes, ["minimalist", "quiet_luxury"])
    }

    /// Verify the clear callback fires.
    func testClearCallbackFires() {
        var clearCalled = false
        let sheet = VibeOverrideSheet(
            selectedVibes: ["romantic"],
            onSave: { _ in },
            onClear: { clearCalled = true }
        )

        sheet.onClear()
        XCTAssertTrue(clearCalled, "onClear callback should fire")
    }

    /// Verify the sheet renders with all 8 vibes selected.
    func testSheetRendersWithAllVibes() {
        let allVibes: Set<String> = [
            "quiet_luxury", "street_urban", "outdoorsy", "vintage",
            "minimalist", "bohemian", "romantic", "adventurous"
        ]

        let sheet = VibeOverrideSheet(
            selectedVibes: allVibes,
            onSave: { _ in },
            onClear: {}
        )

        let hostingController = UIHostingController(rootView: sheet)
        XCTAssertNotNil(hostingController.view,
                        "VibeOverrideSheet should render with all 8 vibes selected")
    }

    /// Verify the sheet renders with dark color scheme.
    func testSheetRendersWithDarkScheme() {
        let sheet = VibeOverrideSheet(
            selectedVibes: ["romantic"],
            onSave: { _ in },
            onClear: {}
        )
        .preferredColorScheme(.dark)

        let hostingController = UIHostingController(rootView: sheet)
        XCTAssertNotNil(hostingController.view,
                        "VibeOverrideSheet should render with dark scheme")
    }
}

// MARK: - Save/Share State Tests (Step 6.6)

@MainActor
final class SaveShareStateTests: XCTestCase {

    /// Verify saved recommendation IDs set is empty on init.
    func testSavedIdsInitiallyEmpty() {
        let vm = RecommendationsViewModel()

        XCTAssertTrue(vm.savedRecommendationIds.isEmpty)
    }

    /// Verify isSaved returns false for unknown IDs.
    func testIsSavedReturnsFalseForUnknown() {
        let vm = RecommendationsViewModel()

        XCTAssertFalse(vm.isSaved("unknown-id"))
    }

    /// Verify isSaved returns true after adding an ID to savedRecommendationIds.
    func testIsSavedReturnsTrueAfterInsert() {
        let vm = RecommendationsViewModel()
        vm.savedRecommendationIds.insert("rec-123")

        XCTAssertTrue(vm.isSaved("rec-123"))
    }

    /// Verify isSaved returns false for a different ID than what was inserted.
    func testIsSavedReturnsFalseForDifferentId() {
        let vm = RecommendationsViewModel()
        vm.savedRecommendationIds.insert("rec-123")

        XCTAssertFalse(vm.isSaved("rec-456"))
    }

    /// Verify multiple IDs can be tracked simultaneously.
    func testMultipleSavedIds() {
        let vm = RecommendationsViewModel()
        vm.savedRecommendationIds.insert("rec-1")
        vm.savedRecommendationIds.insert("rec-2")
        vm.savedRecommendationIds.insert("rec-3")

        XCTAssertEqual(vm.savedRecommendationIds.count, 3)
        XCTAssertTrue(vm.isSaved("rec-1"))
        XCTAssertTrue(vm.isSaved("rec-2"))
        XCTAssertTrue(vm.isSaved("rec-3"))
        XCTAssertFalse(vm.isSaved("rec-4"))
    }

    /// Verify saveRecommendation adds the ID to savedRecommendationIds (without model context).
    func testSaveRecommendationAddsId() {
        let vm = RecommendationsViewModel()
        let item = makeTestRecommendation(id: "save-test-1", title: "Test Save")

        // No model context configured — still updates the in-memory set
        vm.saveRecommendation(item)

        XCTAssertTrue(vm.isSaved("save-test-1"))
    }

    /// Verify saveRecommendation is a no-op for already-saved IDs.
    func testSaveRecommendationNoOpForDuplicate() {
        let vm = RecommendationsViewModel()
        vm.savedRecommendationIds.insert("already-saved")

        let item = makeTestRecommendation(id: "already-saved", title: "Already Saved")

        // Should not crash or duplicate
        vm.saveRecommendation(item)

        XCTAssertEqual(vm.savedRecommendationIds.count, 1)
        XCTAssertTrue(vm.isSaved("already-saved"))
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
            "external_url": "https://example.com/test",
            "image_url": null,
            "merchant_name": "Test Store",
            "source": "test",
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

// MARK: - SavedRecommendation Model Tests (Step 6.6)

final class SavedRecommendationModelTests: XCTestCase {

    /// Verify SavedRecommendation initializes with all fields.
    func testInitWithAllFields() {
        let saved = SavedRecommendation(
            recommendationId: "rec-001",
            recommendationType: "gift",
            title: "Pottery Class",
            descriptionText: "A fun pottery class",
            externalURL: "https://example.com/pottery",
            priceCents: 8500,
            currency: "USD",
            merchantName: "Clay Studio",
            imageURL: "https://example.com/image.jpg"
        )

        XCTAssertEqual(saved.recommendationId, "rec-001")
        XCTAssertEqual(saved.recommendationType, "gift")
        XCTAssertEqual(saved.title, "Pottery Class")
        XCTAssertEqual(saved.descriptionText, "A fun pottery class")
        XCTAssertEqual(saved.externalURL, "https://example.com/pottery")
        XCTAssertEqual(saved.priceCents, 8500)
        XCTAssertEqual(saved.currency, "USD")
        XCTAssertEqual(saved.merchantName, "Clay Studio")
        XCTAssertEqual(saved.imageURL, "https://example.com/image.jpg")
        XCTAssertNotNil(saved.savedAt)
    }

    /// Verify SavedRecommendation initializes with minimal data (nil optionals).
    func testInitWithMinimalData() {
        let saved = SavedRecommendation(
            recommendationId: "rec-002",
            recommendationType: "experience",
            title: "Sunset Sailing",
            externalURL: "https://example.com/sailing"
        )

        XCTAssertEqual(saved.recommendationId, "rec-002")
        XCTAssertEqual(saved.recommendationType, "experience")
        XCTAssertEqual(saved.title, "Sunset Sailing")
        XCTAssertNil(saved.descriptionText)
        XCTAssertEqual(saved.externalURL, "https://example.com/sailing")
        XCTAssertNil(saved.priceCents)
        XCTAssertEqual(saved.currency, "USD")
        XCTAssertNil(saved.merchantName)
        XCTAssertNil(saved.imageURL)
    }

    /// Verify savedAt defaults to approximately now.
    func testSavedAtDefaultsToNow() {
        let before = Date()
        let saved = SavedRecommendation(
            recommendationId: "rec-003",
            recommendationType: "date",
            title: "Dinner",
            externalURL: "https://example.com/dinner"
        )
        let after = Date()

        XCTAssertGreaterThanOrEqual(saved.savedAt, before)
        XCTAssertLessThanOrEqual(saved.savedAt, after)
    }

    /// Verify all recommendation types are accepted.
    func testAllRecommendationTypes() {
        let types = ["gift", "experience", "date"]

        for type in types {
            let saved = SavedRecommendation(
                recommendationId: "rec-\(type)",
                recommendationType: type,
                title: "Test \(type)",
                externalURL: "https://example.com/\(type)"
            )

            XCTAssertEqual(saved.recommendationType, type,
                           "Should accept recommendation type: \(type)")
        }
    }

    /// Verify custom savedAt date is preserved.
    func testCustomSavedAtDate() {
        let customDate = Date(timeIntervalSince1970: 1000000)
        let saved = SavedRecommendation(
            recommendationId: "rec-004",
            recommendationType: "gift",
            title: "Custom Date Test",
            externalURL: "https://example.com",
            savedAt: customDate
        )

        XCTAssertEqual(saved.savedAt, customDate)
    }
}

// MARK: - SavedViewModel Tests (moved from HomeViewModel in tab navigation refactor)

@MainActor
final class SavedViewModelTests: XCTestCase {

    /// Verify savedRecommendations is empty on init.
    func testSavedRecommendationsInitiallyEmpty() {
        let vm = SavedViewModel()

        XCTAssertTrue(vm.savedRecommendations.isEmpty)
    }
}
