//
//  MerchantHandoffTests.swift
//  KnotTests
//
//  Created on February 12, 2026.
//  Step 9.3: Tests for external merchant handoff service, DTOs, and handoff flow.
//  Step 9.4: Tests for return-to-app purchase prompt and rating flow.
//  Step 10.4: Tests for App Store review prompt after 5-star rating.
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

    /// Verify confirmSelection clears confirmation state and sets pending handoff (Step 9.4).
    func testConfirmSelectionSetsPendingHandoff() async {
        let vm = RecommendationsViewModel()
        let item = makeTestRecommendation(id: "handoff-1", title: "Test Handoff")

        vm.selectRecommendation(item)
        XCTAssertTrue(vm.showConfirmationSheet)
        XCTAssertNotNil(vm.selectedRecommendation)

        await vm.confirmSelection()

        XCTAssertFalse(vm.showConfirmationSheet, "Confirmation sheet should be dismissed")
        XCTAssertNil(vm.selectedRecommendation, "Selected recommendation should be cleared")
        XCTAssertNotNil(vm.pendingHandoffRecommendation, "Pending handoff should be set")
        XCTAssertEqual(vm.pendingHandoffRecommendation?.id, "handoff-1")
    }

    /// Verify confirmSelection is a no-op when no recommendation is selected.
    func testConfirmSelectionNoOpWithoutSelection() async {
        let vm = RecommendationsViewModel()

        // No selection — should not crash
        await vm.confirmSelection()

        XCTAssertFalse(vm.showConfirmationSheet)
        XCTAssertNil(vm.selectedRecommendation)
        XCTAssertNil(vm.pendingHandoffRecommendation)
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

// MARK: - Return-to-App ViewModel Tests (Step 9.4)

@MainActor
final class ReturnToAppTests: XCTestCase {

    /// handleReturnFromMerchant shows purchase prompt when pending handoff exists.
    func testHandleReturnShowsPromptWithPendingHandoff() async {
        let vm = RecommendationsViewModel()
        let item = makeTestRecommendation(id: "return-1", title: "Test Return")

        vm.selectRecommendation(item)
        await vm.confirmSelection()

        XCTAssertNotNil(vm.pendingHandoffRecommendation)
        XCTAssertFalse(vm.showPurchasePromptSheet)

        vm.handleReturnFromMerchant()
        // Wait for the 500ms delay
        try? await Task.sleep(for: .milliseconds(700))

        XCTAssertTrue(vm.showPurchasePromptSheet,
                      "Purchase prompt should be shown after returning from merchant")
    }

    /// handleReturnFromMerchant is a no-op without pending handoff.
    func testHandleReturnNoOpWithoutPendingHandoff() async {
        let vm = RecommendationsViewModel()

        vm.handleReturnFromMerchant()
        try? await Task.sleep(for: .milliseconds(700))

        XCTAssertFalse(vm.showPurchasePromptSheet,
                       "Purchase prompt should not show without a pending handoff")
    }

    /// confirmPurchase dismisses purchase prompt and shows rating prompt.
    func testConfirmPurchaseShowsRating() async {
        let vm = RecommendationsViewModel()
        let item = makeTestRecommendation(id: "return-2", title: "Test Purchase")

        vm.pendingHandoffRecommendation = item
        vm.showPurchasePromptSheet = true

        await vm.confirmPurchase()

        XCTAssertFalse(vm.showPurchasePromptSheet,
                       "Purchase prompt should be dismissed")
        XCTAssertTrue(vm.showRatingPrompt,
                      "Rating prompt should be shown after confirming purchase")
        XCTAssertNotNil(vm.pendingHandoffRecommendation,
                        "Pending handoff should be preserved for rating step")
    }

    /// submitPurchaseRating clears all return-to-app state.
    func testSubmitPurchaseRatingClearsState() async {
        let vm = RecommendationsViewModel()
        let item = makeTestRecommendation(id: "return-3", title: "Test Rating")

        vm.pendingHandoffRecommendation = item
        vm.showRatingPrompt = true

        await vm.submitPurchaseRating(5, feedbackText: "Great pick!")

        XCTAssertFalse(vm.showRatingPrompt, "Rating prompt should be dismissed")
        XCTAssertNil(vm.pendingHandoffRecommendation,
                     "Pending handoff should be cleared after rating")
    }

    /// skipPurchaseRating clears all return-to-app state.
    func testSkipPurchaseRatingClearsState() {
        let vm = RecommendationsViewModel()
        let item = makeTestRecommendation(id: "return-4", title: "Test Skip Rating")

        vm.pendingHandoffRecommendation = item
        vm.showRatingPrompt = true

        vm.skipPurchaseRating()

        XCTAssertFalse(vm.showRatingPrompt, "Rating prompt should be dismissed")
        XCTAssertNil(vm.pendingHandoffRecommendation,
                     "Pending handoff should be cleared on skip")
    }

    /// declinePurchaseAndSave clears purchase prompt state.
    func testDeclinePurchaseSavesAndClears() {
        let vm = RecommendationsViewModel()
        let item = makeTestRecommendation(id: "return-5", title: "Test Decline")

        vm.pendingHandoffRecommendation = item
        vm.showPurchasePromptSheet = true

        vm.declinePurchaseAndSave()

        XCTAssertFalse(vm.showPurchasePromptSheet,
                       "Purchase prompt should be dismissed")
        XCTAssertNil(vm.pendingHandoffRecommendation,
                     "Pending handoff should be cleared")
    }

    /// dismissPurchasePrompt clears all state.
    func testDismissPurchasePromptClearsState() {
        let vm = RecommendationsViewModel()
        let item = makeTestRecommendation(id: "return-6", title: "Test Dismiss")

        vm.pendingHandoffRecommendation = item
        vm.showPurchasePromptSheet = true

        vm.dismissPurchasePrompt()

        XCTAssertFalse(vm.showPurchasePromptSheet,
                       "Purchase prompt should be dismissed")
        XCTAssertNil(vm.pendingHandoffRecommendation,
                     "Pending handoff should be cleared on dismiss")
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

// MARK: - Purchased Feedback DTO Tests (Step 9.4)

final class PurchasedFeedbackDTOTests: XCTestCase {

    /// Verify RecommendationFeedbackPayload encodes "purchased" action correctly.
    func testFeedbackPayloadEncodesPurchasedAction() throws {
        let payload = RecommendationFeedbackPayload(
            recommendationId: "rec-purchase-123",
            action: "purchased"
        )

        let data = try JSONEncoder().encode(payload)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertEqual(json?["action"] as? String, "purchased")
        XCTAssertEqual(json?["recommendation_id"] as? String, "rec-purchase-123")
    }

    /// Verify RecommendationFeedbackPayload encodes rating and feedback_text correctly.
    func testFeedbackPayloadEncodesWithRating() throws {
        let payload = RecommendationFeedbackPayload(
            recommendationId: "rec-rated-123",
            action: "rated",
            rating: 5,
            feedbackText: "She loved it!"
        )

        let data = try JSONEncoder().encode(payload)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertEqual(json?["action"] as? String, "rated")
        XCTAssertEqual(json?["rating"] as? Int, 5)
        XCTAssertEqual(json?["feedback_text"] as? String, "She loved it!")
    }

    /// Verify nil rating/feedbackText are omitted from encoded JSON.
    func testFeedbackPayloadOmitsNilOptionals() throws {
        let payload = RecommendationFeedbackPayload(
            recommendationId: "rec-123",
            action: "purchased"
        )

        let data = try JSONEncoder().encode(payload)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        // Swift's default Codable synthesis omits nil optionals (encodeIfPresent).
        // The backend (Pydantic) defaults missing fields to None, so this is correct.
        XCTAssertFalse(json?.keys.contains("rating") == true,
                       "rating key should be omitted when nil")
        XCTAssertFalse(json?.keys.contains("feedback_text") == true,
                       "feedback_text key should be omitted when nil")
    }
}

// MARK: - Purchase Prompt View Tests (Step 9.4)

@MainActor
final class PurchasePromptViewTests: XCTestCase {

    /// Verify PurchasePromptSheet renders without crashing.
    func testPurchasePromptSheetRenders() {
        let view = PurchasePromptSheet(
            title: "Test Item",
            merchantName: "Test Store",
            onConfirmPurchase: {},
            onSaveForLater: {},
            onDismiss: {}
        )
        let hostingController = UIHostingController(rootView: view)
        XCTAssertNotNil(hostingController.view,
                        "PurchasePromptSheet should render a valid view")
    }

    /// Verify PurchasePromptSheet renders with nil merchant name.
    func testPurchasePromptSheetRendersWithoutMerchant() {
        let view = PurchasePromptSheet(
            title: "Test Item",
            merchantName: nil,
            onConfirmPurchase: {},
            onSaveForLater: {},
            onDismiss: {}
        )
        let hostingController = UIHostingController(rootView: view)
        XCTAssertNotNil(hostingController.view,
                        "PurchasePromptSheet should render with nil merchant name")
    }

    /// Verify PurchaseRatingSheet renders without crashing.
    func testPurchaseRatingSheetRenders() {
        let view = PurchaseRatingSheet(
            itemTitle: "Test Item",
            onSubmit: { _, _ in },
            onSkip: {}
        )
        let hostingController = UIHostingController(rootView: view)
        XCTAssertNotNil(hostingController.view,
                        "PurchaseRatingSheet should render a valid view")
    }
}

// MARK: - App Store Review Prompt Tests (Step 10.4)

@MainActor
final class AppStoreReviewPromptTests: XCTestCase {

    override func tearDown() {
        super.tearDown()
        // Clean up UserDefaults after each test
        UserDefaults.standard.removeObject(forKey: "lastAppReviewPromptDate")
    }

    /// 5-star rating triggers the App Store review prompt after 2-second delay.
    func testFiveStarRatingShowsReviewPrompt() async {
        let vm = RecommendationsViewModel()
        let item = makeTestRecommendation(id: "review-1", title: "Test Review")

        vm.pendingHandoffRecommendation = item
        vm.showRatingPrompt = true

        await vm.submitPurchaseRating(5, feedbackText: "Amazing!")

        // Rating prompt should be dismissed immediately
        XCTAssertFalse(vm.showRatingPrompt, "Rating prompt should be dismissed")
        XCTAssertNil(vm.pendingHandoffRecommendation,
                     "Pending handoff should be cleared")

        // submitPurchaseRating includes the 2-second delay internally,
        // so showAppReviewPrompt should already be true when await returns
        XCTAssertTrue(vm.showAppReviewPrompt,
                      "App review prompt should appear after 5-star rating")
    }

    /// 4-star rating does NOT trigger the App Store review prompt.
    func testFourStarRatingDoesNotShowReviewPrompt() async {
        let vm = RecommendationsViewModel()
        let item = makeTestRecommendation(id: "review-2", title: "Test No Review")

        vm.pendingHandoffRecommendation = item
        vm.showRatingPrompt = true

        await vm.submitPurchaseRating(4, feedbackText: "Pretty good")

        XCTAssertFalse(vm.showAppReviewPrompt,
                       "App review prompt should NOT appear for non-5-star rating")
    }

    /// 3-star rating does NOT trigger the App Store review prompt.
    func testThreeStarRatingDoesNotShowReviewPrompt() async {
        let vm = RecommendationsViewModel()
        let item = makeTestRecommendation(id: "review-3", title: "Test 3 Star")

        vm.pendingHandoffRecommendation = item
        vm.showRatingPrompt = true

        await vm.submitPurchaseRating(3)

        XCTAssertFalse(vm.showAppReviewPrompt,
                       "App review prompt should NOT appear for 3-star rating")
    }

    /// 90-day cooldown prevents the prompt from showing again.
    func testNinetyDayCooldownPreventsPrompt() async {
        let vm = RecommendationsViewModel()
        let item = makeTestRecommendation(id: "review-4", title: "Test Cooldown")

        // Simulate a recent review prompt (10 days ago)
        let tenDaysAgo = Calendar.current.date(byAdding: .day, value: -10, to: Date())!
        UserDefaults.standard.set(tenDaysAgo, forKey: "lastAppReviewPromptDate")

        vm.pendingHandoffRecommendation = item
        vm.showRatingPrompt = true

        await vm.submitPurchaseRating(5, feedbackText: "Love it!")

        XCTAssertFalse(vm.showAppReviewPrompt,
                       "App review prompt should NOT appear within 90-day cooldown")
    }

    /// Prompt appears when cooldown has expired (91+ days since last prompt).
    func testExpiredCooldownAllowsPrompt() async {
        let vm = RecommendationsViewModel()
        let item = makeTestRecommendation(id: "review-5", title: "Test Expired Cooldown")

        // Simulate an old review prompt (91 days ago)
        let ninetyOneDaysAgo = Calendar.current.date(byAdding: .day, value: -91, to: Date())!
        UserDefaults.standard.set(ninetyOneDaysAgo, forKey: "lastAppReviewPromptDate")

        vm.pendingHandoffRecommendation = item
        vm.showRatingPrompt = true

        await vm.submitPurchaseRating(5, feedbackText: "Still great!")

        XCTAssertTrue(vm.showAppReviewPrompt,
                      "App review prompt should appear after 90-day cooldown expires")
    }

    /// canPromptForAppReview returns true when no date is stored.
    func testCanPromptReturnsTrueWhenNeverPrompted() {
        let vm = RecommendationsViewModel()

        XCTAssertTrue(vm.canPromptForAppReview(),
                      "Should allow prompt when never prompted before")
    }

    /// canPromptForAppReview returns false when prompted recently.
    func testCanPromptReturnsFalseWhenRecentlyPrompted() {
        let vm = RecommendationsViewModel()
        UserDefaults.standard.set(Date(), forKey: "lastAppReviewPromptDate")

        XCTAssertFalse(vm.canPromptForAppReview(),
                       "Should deny prompt when prompted today")
    }

    /// recordAppReviewPromptDate stores a date that blocks future prompts.
    func testRecordPromptDateBlocksFuturePrompts() {
        let vm = RecommendationsViewModel()

        XCTAssertTrue(vm.canPromptForAppReview())

        vm.recordAppReviewPromptDate()

        XCTAssertFalse(vm.canPromptForAppReview(),
                       "Recording prompt date should block future prompts")
    }

    /// dismissAppReviewPrompt sets showAppReviewPrompt to false.
    func testDismissAppReviewPromptClearsState() {
        let vm = RecommendationsViewModel()
        vm.showAppReviewPrompt = true

        vm.dismissAppReviewPrompt()

        XCTAssertFalse(vm.showAppReviewPrompt,
                       "Dismiss should clear the prompt flag")
    }

    /// showAppReviewPrompt defaults to false.
    func testInitialAppReviewPromptState() {
        let vm = RecommendationsViewModel()

        XCTAssertFalse(vm.showAppReviewPrompt,
                       "App review prompt should be hidden by default")
    }

    /// AppReviewPromptSheet renders without crashing.
    func testAppReviewPromptSheetRenders() {
        let view = AppReviewPromptSheet(
            onAccept: {},
            onDecline: {}
        )
        let hostingController = UIHostingController(rootView: view)
        XCTAssertNotNil(hostingController.view,
                        "AppReviewPromptSheet should render a valid view")
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
