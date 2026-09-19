//
//  RecommendationFeedTests.swift
//  KnotTests
//
//  Step 19.59: The vertical recommendation feed — the section-heading map, the
//  photo card's press forwarding and VoiceOver label, and render smoke tests
//  for the card and the list. Replaces the deck / carousel rendering tests
//  that went with `SpotlightDeckView.swift`.
//

import XCTest
import SwiftUI
@testable import Knot

// MARK: - Helpers

private let allTypes = ["gift", "experience", "date", "idea", "plan"]

@MainActor
private func makeItem(type: String) -> RecommendationItemResponse {
    PreviewRecommendations.decode(type: type, isIdea: type == "idea" || type == "plan")
}

/// A pick whose description is whitespace-only, so the card's description
/// line is omitted rather than rendered blank.
@MainActor
private func makeBlankDescriptionItem() -> RecommendationItemResponse {
    let json = """
    {
        "id": "gift-blank", "recommendation_type": "gift", "title": "Gift for Alex",
        "description": "   \\n ", "price_cents": 8500, "currency": "USD",
        "external_url": "https://example.com/x", "image_url": null,
        "merchant_name": "Clay Studio Brooklyn", "source": "test",
        "location": {"city": "Brooklyn", "state": "NY", "country": "US", "address": "1 Main St"},
        "is_idea": false,
        "interest_score": 0.8, "vibe_score": 0.7, "love_language_score": 0.6, "final_score": 0.7,
        "matched_interests": ["Art"], "matched_vibes": ["romantic"], "matched_love_languages": ["quality_time"],
        "personalization_note": "She mentioned loving this."
    }
    """.data(using: .utf8)!
    return try! JSONDecoder().decode(RecommendationItemResponse.self, from: json)
}

// MARK: - Section Label

@MainActor
final class RecommendationFeedSectionLabelTests: XCTestCase {

    /// Every backend recommendation type maps to its editorial heading.
    func testSectionLabelForKnownTypes() {
        XCTAssertEqual(RecommendationFeedList.sectionLabel(for: "gift"), "Gift")
        XCTAssertEqual(RecommendationFeedList.sectionLabel(for: "experience"), "Experience")
        XCTAssertEqual(RecommendationFeedList.sectionLabel(for: "date"), "Date Idea")
        XCTAssertEqual(RecommendationFeedList.sectionLabel(for: "idea"), "Knot Original")
        XCTAssertEqual(RecommendationFeedList.sectionLabel(for: "plan"), "Date Plan")
    }

    /// The heading is deliberately NOT the detail page's uppercase type tag —
    /// "Date" / "Idea" read badly at heading size. Pin the two that differ.
    func testSectionLabelDivergesFromTheTypeTagWhereTheTagReadsBadly() {
        XCTAssertNotEqual(RecommendationFeedList.sectionLabel(for: "date"), "Date")
        XCTAssertNotEqual(RecommendationFeedList.sectionLabel(for: "idea"), "Idea")
    }

    /// An unknown type from a newer backend degrades to a generic heading
    /// rather than leaking the raw key or crashing.
    func testSectionLabelForUnknownTypeIsGeneric() {
        XCTAssertEqual(RecommendationFeedList.sectionLabel(for: "surprise"), "Recommendation")
        XCTAssertEqual(RecommendationFeedList.sectionLabel(for: ""), "Recommendation")
    }

    /// The map is exact-match on the backend key, not case-folded.
    func testSectionLabelIsCaseSensitive() {
        XCTAssertEqual(RecommendationFeedList.sectionLabel(for: "Gift"), "Recommendation")
    }
}

// MARK: - Card

@MainActor
final class RecommendationFeedCardTests: XCTestCase {

    /// The card renders for every recommendation type (each has its own
    /// fallback photo) without a URL, so the fallback path is what is hosted.
    func testCardRendersAllTypes() {
        for type in allTypes {
            let card = RecommendationFeedCard(item: makeItem(type: type), isSaved: false, onOpenDetail: {})
            let host = UIHostingController(rootView: card)
            XCTAssertNotNil(host.view, "RecommendationFeedCard should render for type: \(type)")
        }
    }

    /// The saved indicator branch renders.
    func testCardRendersWhenSaved() {
        let card = RecommendationFeedCard(item: makeItem(type: "gift"), isSaved: true, onOpenDetail: {})
        let host = UIHostingController(rootView: card)
        XCTAssertNotNil(host.view, "RecommendationFeedCard should render a saved pick")
    }

    /// A whitespace-only description takes the description-omitted branch.
    func testCardRendersWithBlankDescription() {
        let card = RecommendationFeedCard(item: makeBlankDescriptionItem(), isSaved: false, onOpenDetail: {})
        let host = UIHostingController(rootView: card)
        XCTAssertNotNil(host.view, "RecommendationFeedCard should render without a description")
    }

    /// The card is 200pt tall — two cards and a heading share a viewport.
    func testCardHeight() {
        XCTAssertEqual(RecommendationFeedCard.cardHeight, 200)
    }

    /// Pressing the card forwards to `onOpenDetail`. `delay: .zero` fires
    /// synchronously so the test needs no expectation.
    func testCardTapForwardsToOpenDetail() {
        var opened = false
        let card = RecommendationFeedCard(
            item: makeItem(type: "experience"),
            isSaved: false,
            onOpenDetail: { opened = true }
        )
        card.cardTapped(delay: .zero)
        XCTAssertTrue(opened, "a card tap must open the detail")
    }

    /// The default tap waits out `Theme.Motion.pressHold` before opening, so
    /// the cover never slides over a card that is still pressed.
    func testCardTapDefersOpenDetailPastThePressHold() async {
        let fired = expectation(description: "onOpenDetail fires after the hold")
        var firedSynchronously = false
        let card = RecommendationFeedCard(
            item: makeItem(type: "experience"),
            isSaved: false,
            onOpenDetail: {
                firedSynchronously = true
                fired.fulfill()
            }
        )
        card.cardTapped()
        XCTAssertFalse(firedSynchronously, "the cover must wait for the press to release")
        await fulfillment(of: [fired], timeout: 2)
    }

    // MARK: Accessibility label

    func testAccessibilityLabelWithDescription() {
        XCTAssertEqual(
            RecommendationFeedCard.accessibilityLabel(
                title: "Pottery Class",
                description: "A hands-on evening.",
                isSaved: false
            ),
            "Pottery Class. A hands-on evening."
        )
    }

    func testAccessibilityLabelWithoutDescription() {
        XCTAssertEqual(
            RecommendationFeedCard.accessibilityLabel(title: "Pottery Class", description: nil, isSaved: false),
            "Pottery Class"
        )
        XCTAssertEqual(
            RecommendationFeedCard.accessibilityLabel(title: "Pottery Class", description: "", isSaved: false),
            "Pottery Class"
        )
    }

    func testAccessibilityLabelAppendsSaved() {
        XCTAssertEqual(
            RecommendationFeedCard.accessibilityLabel(
                title: "Pottery Class",
                description: "A hands-on evening.",
                isSaved: true
            ),
            "Pottery Class. A hands-on evening., Saved"
        )
        XCTAssertEqual(
            RecommendationFeedCard.accessibilityLabel(title: "Pottery Class", description: nil, isSaved: true),
            "Pottery Class, Saved"
        )
    }
}

// MARK: - List

@MainActor
final class RecommendationFeedListTests: XCTestCase {

    /// The list renders the usual three picks.
    func testListRendersThreeItems() {
        let list = RecommendationFeedList(
            items: [makeItem(type: "experience"), makeItem(type: "gift"), makeItem(type: "idea")],
            isSaved: { _ in false },
            onOpenDetail: { _ in }
        )
        let host = UIHostingController(rootView: list)
        XCTAssertNotNil(host.view, "RecommendationFeedList should render three items")
    }

    /// A single pick renders — no assumption of three.
    func testListRendersSingleItem() {
        let list = RecommendationFeedList(
            items: [makeItem(type: "date")],
            isSaved: { _ in true },
            onOpenDetail: { _ in }
        )
        let host = UIHostingController(rootView: list)
        XCTAssertNotNil(host.view, "RecommendationFeedList should render a single item")
    }

    /// An empty list renders nothing rather than crashing (the host's phase
    /// switch normally routes an empty result to its own empty state).
    func testListRendersEmpty() {
        let list = RecommendationFeedList(items: [], isSaved: { _ in false }, onOpenDetail: { _ in })
        let host = UIHostingController(rootView: list)
        XCTAssertNotNil(host.view, "RecommendationFeedList should render with no items")
    }

    /// `isSaved` is consulted with each pick's id, so the saved indicator
    /// lands on the right card. The list is put in a window and laid out so
    /// SwiftUI actually evaluates the body (a bare `host.view` may not).
    func testListConsultsIsSavedWithEachItemId() {
        let items = [makeItem(type: "experience"), makeItem(type: "gift"), makeItem(type: "idea")]
        var queried: [String] = []
        let list = RecommendationFeedList(
            items: items,
            isSaved: { id in
                queried.append(id)
                return false
            },
            onOpenDetail: { _ in }
        )
        let host = UIHostingController(rootView: list)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.layoutIfNeeded()

        XCTAssertEqual(Set(queried), Set(items.map(\.id)), "every pick's id must be checked against the saved set")
    }
}
