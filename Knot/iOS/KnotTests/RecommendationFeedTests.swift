//
//  RecommendationFeedTests.swift
//  KnotTests
//
//  Step 19.59: The vertical recommendation feed — the section-heading map, the
//  photo card's press forwarding and VoiceOver label, and render smoke tests
//  for the card and the list. Replaces the deck / carousel rendering tests
//  that went with `SpotlightDeckView.swift`.
//  Step 19.60: The heading now prefers the backend's generated `headline` and
//  falls back to the type map; the type ribbon's label/icon maps and its place
//  in the card's VoiceOver label.
//

import XCTest
import SwiftUI
@testable import Knot

// MARK: - Helpers

private let allTypes = ["gift", "experience", "date", "idea", "plan"]

/// A pick with no `headline` key — what every batch stored before headlines
/// existed looks like, so the feed's fallback heading is what these exercise.
@MainActor
private func makeItem(type: String) -> RecommendationItemResponse {
    PreviewRecommendations.decode(type: type, isIdea: type == "idea" || type == "plan")
}

@MainActor
private func makeItem(type: String, headline: String) -> RecommendationItemResponse {
    PreviewRecommendations.decode(type: type, isIdea: type == "idea" || type == "plan", headline: headline)
}

/// A pick whose description (and, optionally, headline) is whitespace-only,
/// so the card's description line is omitted rather than rendered blank and
/// the heading falls back rather than rendering as empty space.
@MainActor
private func makeBlankDescriptionItem(headline: String? = nil) -> RecommendationItemResponse {
    let headlineField = headline.map { ", \"headline\": \"\($0)\"" } ?? ""
    let json = """
    {
        "id": "gift-blank", "recommendation_type": "gift", "title": "Gift for Alex"\(headlineField),
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

// MARK: - Heading

@MainActor
final class RecommendationFeedHeadingTests: XCTestCase {

    /// A pick with a backend headline is headed by it, whatever its type.
    func testHeadingPrefersBackendHeadline() {
        XCTAssertEqual(
            RecommendationFeedList.heading(for: makeItem(type: "gift", headline: "Small Luxuries")),
            "Small Luxuries"
        )
        XCTAssertEqual(
            RecommendationFeedList.heading(for: makeItem(type: "idea", headline: "The Art of Pause")),
            "The Art of Pause"
        )
    }

    /// No headline (a batch stored before Step 19.60) → the type-derived heading.
    func testHeadingFallsBackToTypeLabelWhenHeadlineMissing() {
        for type in allTypes {
            let item = makeItem(type: type)
            XCTAssertNil(item.headline, "fixture for \(type) must carry no headline")
            XCTAssertEqual(
                RecommendationFeedList.heading(for: item),
                RecommendationFeedList.sectionLabel(for: type),
                "type \(type) must fall back to its section label"
            )
        }
    }

    /// A whitespace-only headline is treated as missing — never an empty heading.
    func testHeadingFallsBackWhenHeadlineIsBlank() {
        XCTAssertEqual(
            RecommendationFeedList.heading(for: makeBlankDescriptionItem(headline: "   ")),
            "Gift"
        )
    }

    /// Surrounding whitespace is trimmed off a real headline.
    func testHeadingTrimsHeadline() {
        XCTAssertEqual(
            RecommendationFeedList.heading(for: makeBlankDescriptionItem(headline: "  Small Luxuries ")),
            "Small Luxuries"
        )
    }
}

// MARK: - Section Label (fallback)

@MainActor
final class RecommendationFeedSectionLabelTests: XCTestCase {

    /// Every backend recommendation type maps to its fallback heading.
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

// MARK: - Type Ribbon

@MainActor
final class RecommendationTypeRibbonTests: XCTestCase {

    /// The ribbon's label mirrors the detail page's hero badge, so the tag the
    /// user taps is the tag they land on.
    func testLabelForKnownTypes() {
        XCTAssertEqual(RecommendationTypeRibbon.label(for: "gift"), "Gift")
        XCTAssertEqual(RecommendationTypeRibbon.label(for: "experience"), "Experience")
        XCTAssertEqual(RecommendationTypeRibbon.label(for: "date"), "Date")
        XCTAssertEqual(RecommendationTypeRibbon.label(for: "idea"), "Idea")
        XCTAssertEqual(RecommendationTypeRibbon.label(for: "plan"), "Date Plan")
    }

    /// An unknown type from a newer backend is shown capitalized, not raw.
    func testLabelForUnknownTypeIsCapitalized() {
        XCTAssertEqual(RecommendationTypeRibbon.label(for: "surprise"), "Surprise")
        XCTAssertEqual(RecommendationTypeRibbon.label(for: ""), "")
    }

    /// The ribbon is a tag and the heading is a heading — the two maps are
    /// allowed to differ exactly where the tag would read badly at 20pt.
    func testLabelDiffersFromTheFallbackHeadingWhereIntended() {
        XCTAssertNotEqual(RecommendationTypeRibbon.label(for: "date"), RecommendationFeedList.sectionLabel(for: "date"))
        XCTAssertNotEqual(RecommendationTypeRibbon.label(for: "idea"), RecommendationFeedList.sectionLabel(for: "idea"))
        XCTAssertEqual(RecommendationTypeRibbon.label(for: "gift"), RecommendationFeedList.sectionLabel(for: "gift"))
    }

    /// Every type has an icon, and the unknown-type icon is a real glyph too.
    func testIconForEveryType() {
        for type in allTypes + ["surprise"] {
            XCTAssertGreaterThan(RecommendationTypeRibbon.icon(for: type).size.width, 0, "no icon for \(type)")
        }
    }

    /// The ribbon renders for every type without crashing.
    func testRibbonRendersAllTypes() {
        for type in allTypes + ["surprise"] {
            let host = UIHostingController(rootView: RecommendationTypeRibbon(recommendationType: type))
            XCTAssertNotNil(host.view, "RecommendationTypeRibbon should render for type: \(type)")
        }
    }
}

// MARK: - Card

@MainActor
final class RecommendationFeedCardTests: XCTestCase {

    /// The card renders for every recommendation type (each has its own
    /// fallback photo and ribbon) without a URL, so the fallback path is what
    /// is hosted.
    func testCardRendersAllTypes() {
        for type in allTypes {
            let card = RecommendationFeedCard(item: makeItem(type: type), isSaved: false, onOpenDetail: {})
            let host = UIHostingController(rootView: card)
            XCTAssertNotNil(host.view, "RecommendationFeedCard should render for type: \(type)")
        }
    }

    /// A pick carrying a backend headline renders the same card — the headline
    /// is the list's heading, not the card's concern.
    func testCardRendersWithHeadline() {
        let card = RecommendationFeedCard(
            item: makeItem(type: "experience", headline: "Weekend Curations"),
            isSaved: false,
            onOpenDetail: {}
        )
        let host = UIHostingController(rootView: card)
        XCTAssertNotNil(host.view, "RecommendationFeedCard should render a headlined pick")
    }

    /// The saved indicator branch renders (alongside the ribbon in the top row).
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

    /// "Title, Type. Description" — the type rides in the label because the
    /// ribbon that shows it is hidden from VoiceOver.
    func testAccessibilityLabelIncludesTypeAndDescription() {
        XCTAssertEqual(
            RecommendationFeedCard.accessibilityLabel(
                title: "Pottery Class",
                typeLabel: "Experience",
                description: "A hands-on evening.",
                isSaved: false
            ),
            "Pottery Class, Experience. A hands-on evening."
        )
    }

    func testAccessibilityLabelWithoutDescription() {
        XCTAssertEqual(
            RecommendationFeedCard.accessibilityLabel(
                title: "Pottery Class", typeLabel: "Experience", description: nil, isSaved: false
            ),
            "Pottery Class, Experience"
        )
        XCTAssertEqual(
            RecommendationFeedCard.accessibilityLabel(
                title: "Pottery Class", typeLabel: "Experience", description: "", isSaved: false
            ),
            "Pottery Class, Experience"
        )
    }

    /// An empty type label (an unknown "" type) is skipped, not read as ", ".
    func testAccessibilityLabelSkipsEmptyType() {
        XCTAssertEqual(
            RecommendationFeedCard.accessibilityLabel(
                title: "Pottery Class", typeLabel: "", description: "A hands-on evening.", isSaved: false
            ),
            "Pottery Class. A hands-on evening."
        )
    }

    /// The title is always first, so a prefix match on the button label finds
    /// the card (`PRScreenshotTests` depends on this).
    func testAccessibilityLabelStartsWithTheTitle() {
        let label = RecommendationFeedCard.accessibilityLabel(
            title: "Experience for Alex", typeLabel: "Experience", description: "A thoughtful pick.", isSaved: true
        )
        XCTAssertTrue(label.hasPrefix("Experience for Alex, Experience"))
    }

    func testAccessibilityLabelAppendsSaved() {
        XCTAssertEqual(
            RecommendationFeedCard.accessibilityLabel(
                title: "Pottery Class",
                typeLabel: "Experience",
                description: "A hands-on evening.",
                isSaved: true
            ),
            "Pottery Class, Experience. A hands-on evening., Saved"
        )
        XCTAssertEqual(
            RecommendationFeedCard.accessibilityLabel(
                title: "Pottery Class", typeLabel: "Experience", description: nil, isSaved: true
            ),
            "Pottery Class, Experience, Saved"
        )
    }
}

// MARK: - List

@MainActor
final class RecommendationFeedListTests: XCTestCase {

    /// The list renders the usual three picks — a mix of headlined and
    /// legacy (headline-less) items, as a feed can hold both.
    func testListRendersThreeItems() {
        let list = RecommendationFeedList(
            items: [
                makeItem(type: "experience", headline: "Weekend Curations"),
                makeItem(type: "gift", headline: "Small Luxuries"),
                makeItem(type: "idea"),
            ],
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
