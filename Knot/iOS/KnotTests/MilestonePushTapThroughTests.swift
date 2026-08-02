//
//  MilestonePushTapThroughTests.swift
//  KnotTests
//
//  Milestone push tap-through: tests for the notification-tap deep link
//  destination, the enriched by-milestone DTOs + mapping, and the
//  view model's preloaded-recommendations path.
//

import XCTest
@testable import Knot

// MARK: - DeepLinkHandler Destination Tests

@MainActor
final class DeepLinkHandlerTests: XCTestCase {

    /// A tapped milestone push with both custom keys maps to the milestone destination.
    func testDestinationWithMilestoneAndNotificationIds() {
        let destination = DeepLinkHandler.destination(
            milestoneId: "ms-123",
            notificationId: "notif-456"
        )
        XCTAssertEqual(
            destination,
            .milestoneRecommendations(milestoneId: "ms-123", notificationId: "notif-456")
        )
    }

    /// A payload without a notification_id still routes (no mark-viewed).
    func testDestinationWithNilNotificationId() {
        let destination = DeepLinkHandler.destination(
            milestoneId: "ms-123",
            notificationId: nil
        )
        XCTAssertEqual(
            destination,
            .milestoneRecommendations(milestoneId: "ms-123", notificationId: nil)
        )
    }

    /// An empty notification_id is normalized to nil.
    func testDestinationNormalizesEmptyNotificationId() {
        let destination = DeepLinkHandler.destination(
            milestoneId: "ms-123",
            notificationId: ""
        )
        XCTAssertEqual(
            destination,
            .milestoneRecommendations(milestoneId: "ms-123", notificationId: nil)
        )
    }

    /// No usable milestone id → no destination (the tap is ignored).
    func testDestinationNilForMissingMilestoneId() {
        XCTAssertNil(DeepLinkHandler.destination(milestoneId: nil, notificationId: "n1"))
        XCTAssertNil(DeepLinkHandler.destination(milestoneId: "", notificationId: "n1"))
    }

    /// Regression: Universal Link parsing still yields the recommendation case.
    func testHandleURLStillParsesRecommendation() {
        let handler = DeepLinkHandler()
        handler.handleURL(URL(string: "https://api.knot-app.com/recommendation/rec-789")!)
        XCTAssertEqual(handler.pendingDestination, .recommendation(id: "rec-789"))
    }

    /// The two destination cases never compare equal.
    func testDestinationCasesAreDistinct() {
        XCTAssertNotEqual(
            DeepLinkDestination.recommendation(id: "x"),
            DeepLinkDestination.milestoneRecommendations(milestoneId: "x", notificationId: nil)
        )
    }
}

// MARK: - Enriched By-Milestone DTO Tests

final class MilestoneRecommendationDTOTests: XCTestCase {

    /// Enriched response (briefing + per-item note/idea fields) decodes fully.
    func testEnrichedResponseDecodes() throws {
        let json = """
        {
            "recommendations": [
                {
                    "id": "rec-1",
                    "recommendation_type": "gift",
                    "title": "Ceramic Mug Set",
                    "description": "Handmade mugs.",
                    "external_url": "https://example.com/mugs",
                    "price_cents": 4500,
                    "merchant_name": "Artisan Co.",
                    "image_url": "https://example.com/mugs.jpg",
                    "created_at": "2026-08-01T12:00:00Z",
                    "personalization_note": "She loves handmade things.",
                    "is_idea": false,
                    "content_sections": null
                },
                {
                    "id": "rec-2",
                    "recommendation_type": "idea",
                    "title": "Cozy Night In",
                    "description": "A quiet evening.",
                    "external_url": null,
                    "price_cents": null,
                    "merchant_name": null,
                    "image_url": "https://example.com/idea.jpg",
                    "created_at": "2026-08-01T12:00:00Z",
                    "personalization_note": "Quality time is her love language.",
                    "is_idea": true,
                    "content_sections": [
                        {"type": "overview", "heading": "Overview", "body": "A cozy night.", "items": null}
                    ]
                }
            ],
            "count": 2,
            "milestone_id": "ms-123",
            "briefing_text": "Her birthday is next week — she mentioned pottery."
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(MilestoneRecommendationsResponse.self, from: json)

        XCTAssertEqual(response.count, 2)
        XCTAssertEqual(response.briefingText, "Her birthday is next week — she mentioned pottery.")

        let gift = response.recommendations[0]
        XCTAssertEqual(gift.personalizationNote, "She loves handmade things.")
        XCTAssertEqual(gift.isIdea, false)
        XCTAssertNil(gift.contentSections)

        let idea = response.recommendations[1]
        XCTAssertEqual(idea.isIdea, true)
        XCTAssertEqual(idea.contentSections?.first?.type, "overview")
        XCTAssertEqual(idea.contentSections?.first?.body, "A cozy night.")
    }

    /// Legacy JSON (older backend without the new fields) still decodes.
    func testLegacyResponseWithoutNewFieldsDecodes() throws {
        let json = """
        {
            "recommendations": [
                {
                    "id": "rec-1",
                    "recommendation_type": "gift",
                    "title": "Test Gift",
                    "description": null,
                    "external_url": null,
                    "price_cents": null,
                    "merchant_name": null,
                    "image_url": null,
                    "created_at": "2026-08-01T12:00:00Z"
                }
            ],
            "count": 1,
            "milestone_id": "ms-123"
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(MilestoneRecommendationsResponse.self, from: json)

        XCTAssertNil(response.briefingText)
        XCTAssertNil(response.recommendations[0].personalizationNote)
        XCTAssertNil(response.recommendations[0].isIdea)
        XCTAssertNil(response.recommendations[0].contentSections)
    }

    /// Mapping to the full recommendation item preserves fields and applies
    /// the standard tag-token sanitation to prose.
    func testToRecommendationItemMapsFields() {
        let item = MilestoneRecommendationItemResponse(
            id: "rec-1",
            recommendationType: "gift",
            title: "Ceramic Mug Set",
            description: "Fits her quiet_luxury style.",
            externalUrl: "https://example.com/mugs",
            priceCents: 4500,
            merchantName: "Artisan Co.",
            imageUrl: "https://example.com/mugs.jpg",
            createdAt: "2026-08-01T12:00:00Z",
            personalizationNote: "Matches her acts_of_service love language.",
            isIdea: false,
            contentSections: nil
        )

        let mapped = item.toRecommendationItem()

        XCTAssertEqual(mapped.id, "rec-1")
        XCTAssertEqual(mapped.recommendationType, "gift")
        XCTAssertEqual(mapped.title, "Ceramic Mug Set")
        XCTAssertEqual(mapped.priceCents, 4500)
        XCTAssertEqual(mapped.externalUrl, "https://example.com/mugs")
        XCTAssertEqual(mapped.imageUrl, "https://example.com/mugs.jpg")
        XCTAssertEqual(mapped.merchantName, "Artisan Co.")
        XCTAssertEqual(mapped.source, "milestone_pregenerated")
        // Snake_case tag tokens are humanized on read (model-layer sanitation).
        XCTAssertEqual(mapped.description, "Fits her quiet luxury style.")
        XCTAssertEqual(mapped.personalizationNote, "Matches her acts of service love language.")
    }

    /// Idea rows keep their idea-ness through the mapping so the detail page
    /// renders content sections and the Save CTA (not a merchant link).
    func testToRecommendationItemPreservesIdeaFields() throws {
        let sectionJSON = """
        {"type": "steps", "heading": "The Plan", "body": null, "items": ["Bake", "Watch a movie"]}
        """.data(using: .utf8)!
        let section = try JSONDecoder().decode(IdeaContentSection.self, from: sectionJSON)

        let item = MilestoneRecommendationItemResponse(
            id: "rec-2",
            recommendationType: "idea",
            title: "Cozy Night In",
            description: nil,
            externalUrl: nil,
            priceCents: nil,
            merchantName: nil,
            imageUrl: nil,
            createdAt: "2026-08-01T12:00:00Z",
            personalizationNote: nil,
            isIdea: true,
            contentSections: [section]
        )

        let mapped = item.toRecommendationItem()

        XCTAssertEqual(mapped.isIdea, true)
        XCTAssertEqual(mapped.contentSections?.count, 1)
        XCTAssertEqual(mapped.contentSections?.first?.items, ["Bake", "Watch a movie"])
        XCTAssertNil(mapped.externalUrl)
    }
}

// MARK: - ViewModel Preloaded Path Tests

/// Mock fetcher driving the preloaded-recommendations seam.
@MainActor
private final class MockMilestoneFetcher: MilestoneRecommendationsFetching {
    enum Behavior {
        case success(MilestoneRecommendationsResponse)
        case failure(Error)
    }

    var behavior: Behavior
    private(set) var requestedMilestoneIds: [String] = []

    init(behavior: Behavior) {
        self.behavior = behavior
    }

    func fetchMilestoneRecommendations(
        milestoneId: String
    ) async throws -> MilestoneRecommendationsResponse {
        requestedMilestoneIds.append(milestoneId)
        switch behavior {
        case .success(let response):
            return response
        case .failure(let error):
            throw error
        }
    }
}

@MainActor
final class PregeneratedRecommendationsViewModelTests: XCTestCase {

    private struct MockError: LocalizedError {
        var errorDescription: String? { "Network unavailable." }
    }

    private func makeResponse(itemCount: Int, briefing: String? = nil) throws -> MilestoneRecommendationsResponse {
        let items = (0..<itemCount).map { i in
            """
            {
                "id": "rec-\(i)",
                "recommendation_type": "gift",
                "title": "Pick \(i)",
                "description": "Desc \(i).",
                "external_url": "https://example.com/\(i)",
                "price_cents": 4500,
                "merchant_name": "Merchant \(i)",
                "image_url": "https://example.com/\(i).jpg",
                "created_at": "2026-08-01T12:00:00Z",
                "personalization_note": "Note \(i)."
            }
            """
        }.joined(separator: ",")
        let briefingJSON = briefing.map { "\"\($0)\"" } ?? "null"
        let json = """
        {
            "recommendations": [\(items)],
            "count": \(itemCount),
            "milestone_id": "ms-123",
            "briefing_text": \(briefingJSON)
        }
        """.data(using: .utf8)!
        return try JSONDecoder().decode(MilestoneRecommendationsResponse.self, from: json)
    }

    /// Stored batch found → recommendations + briefing populate, deck resets,
    /// returns true (no generate fallback needed).
    func testPreloadSuccessPopulatesState() async throws {
        let response = try makeResponse(itemCount: 3, briefing: "Knot's take here.")
        let fetcher = MockMilestoneFetcher(behavior: .success(response))
        let vm = RecommendationsViewModel(milestoneFetcher: fetcher)

        let displayed = await vm.loadPregeneratedRecommendations(milestoneId: "ms-123")

        XCTAssertTrue(displayed)
        XCTAssertEqual(vm.recommendations.count, 3)
        XCTAssertEqual(vm.recommendations[0].title, "Pick 0")
        XCTAssertEqual(vm.recommendations[0].personalizationNote, "Note 0.")
        XCTAssertEqual(vm.briefingText, "Knot's take here.")
        XCTAssertTrue(vm.hasLoadedInitially)
        XCTAssertEqual(vm.deckResetToken, 1)
        XCTAssertNil(vm.errorMessage)
        XCTAssertFalse(vm.isLoading)
        XCTAssertEqual(fetcher.requestedMilestoneIds, ["ms-123"])
    }

    /// No stored rows → returns false and leaves state untouched so the
    /// caller can run the generate fallback.
    func testPreloadEmptyReturnsFalse() async throws {
        let response = try makeResponse(itemCount: 0)
        let fetcher = MockMilestoneFetcher(behavior: .success(response))
        let vm = RecommendationsViewModel(milestoneFetcher: fetcher)

        let displayed = await vm.loadPregeneratedRecommendations(milestoneId: "ms-123")

        XCTAssertFalse(displayed)
        XCTAssertTrue(vm.recommendations.isEmpty)
        XCTAssertNil(vm.briefingText)
        XCTAssertFalse(vm.hasLoadedInitially)
        XCTAssertEqual(vm.deckResetToken, 0)
        XCTAssertFalse(vm.isLoading)
    }

    /// Fetch error → error state is shown (returns true) instead of silently
    /// falling back to the 30s generation pipeline.
    func testPreloadErrorSurfacesErrorState() async {
        let fetcher = MockMilestoneFetcher(behavior: .failure(MockError()))
        let vm = RecommendationsViewModel(milestoneFetcher: fetcher)

        let displayed = await vm.loadPregeneratedRecommendations(milestoneId: "ms-123")

        XCTAssertTrue(displayed)
        XCTAssertEqual(vm.errorMessage, "Network unavailable.")
        XCTAssertTrue(vm.recommendations.isEmpty)
        XCTAssertFalse(vm.hasLoadedInitially)
        XCTAssertFalse(vm.isLoading)
    }

    /// Guard: a preload while another load is in flight is a no-op that
    /// reports "displayed" so no duplicate generate fires.
    func testPreloadGuardedWhileLoading() async throws {
        let response = try makeResponse(itemCount: 3)
        let fetcher = MockMilestoneFetcher(behavior: .success(response))
        let vm = RecommendationsViewModel(milestoneFetcher: fetcher)
        vm.isLoading = true

        let displayed = await vm.loadPregeneratedRecommendations(milestoneId: "ms-123")

        XCTAssertTrue(displayed)
        XCTAssertTrue(vm.recommendations.isEmpty)
        XCTAssertTrue(fetcher.requestedMilestoneIds.isEmpty)
    }
}
