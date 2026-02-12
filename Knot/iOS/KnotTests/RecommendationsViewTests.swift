//
//  RecommendationsViewTests.swift
//  KnotTests
//
//  Created on February 10, 2026.
//  Step 6.2: Unit tests for RecommendationsView, RecommendationsViewModel, DTOs, and RecommendationService.
//  Step 6.3: Tests for card selection flow, feedback DTOs, and confirmation sheet.
//  Step 6.4: Tests for refresh reason sheet and refresh animation state management.
//

import XCTest
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
            "final_score": 0.82
        }
        """.data(using: .utf8)!

        let item = try JSONDecoder().decode(RecommendationItemResponse.self, from: json)

        XCTAssertEqual(item.id, "abc-123")
        XCTAssertEqual(item.recommendationType, "gift")
        XCTAssertEqual(item.title, "Ceramic Pottery Class")
        XCTAssertEqual(item.description, "A hands-on pottery experience.")
        XCTAssertEqual(item.priceCents, 8500)
        XCTAssertEqual(item.currency, "USD")
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

    /// Verify RecommendationRefreshPayload encodes to correct snake_case JSON keys.
    func testRefreshPayloadEncodesCorrectly() throws {
        let payload = RecommendationRefreshPayload(
            rejectedRecommendationIds: ["r1", "r2", "r3"],
            rejectionReason: "not_their_style"
        )

        let data = try JSONEncoder().encode(payload)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertEqual(json?["rejected_recommendation_ids"] as? [String], ["r1", "r2", "r3"])
        XCTAssertEqual(json?["rejection_reason"] as? String, "not_their_style")
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
