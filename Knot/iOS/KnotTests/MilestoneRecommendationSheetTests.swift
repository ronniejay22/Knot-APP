//
//  MilestoneRecommendationSheetTests.swift
//  KnotTests
//
//  The Journal "See details" bottom sheet — its pure copy helpers, the occasion
//  emoji map, and render smoke tests.
//

import XCTest
import SwiftUI
@testable import Knot

// MARK: - Helpers

@MainActor
private func makeMilestone(
    id: String = "m1",
    type: String = "holiday",
    name: String = "Christmas",
    days: Int? = 175,
    occasionCategory: String? = "christmas"
) -> MilestoneItemResponse {
    MilestoneItemResponse(
        id: id,
        milestoneType: type,
        milestoneName: name,
        milestoneDate: "2000-12-25",
        recurrence: "yearly",
        budgetTier: "major_milestone",
        daysUntil: days,
        createdAt: "2026-07-04",
        occasionCategory: occasionCategory
    )
}

// MARK: - Badge Text

@MainActor
final class MilestoneRecommendationSheetBadgeTests: XCTestCase {

    /// The comp's badge: emoji, name, then the date after a middot.
    func testBadgeCombinesEmojiNameAndDate() {
        XCTAssertEqual(
            MilestoneRecommendationSheet.badgeText(
                milestoneName: "Christmas",
                emoji: "🎄",
                formattedDate: "Dec 25"
            ),
            "🎄 Christmas · Dec 25"
        )
    }

    /// `default` and any unknown category have no emoji — the badge must read as
    /// deliberate text, not as a string with a missing leading glyph.
    func testBadgeDropsTheEmojiWhenThereIsNone() {
        XCTAssertEqual(
            MilestoneRecommendationSheet.badgeText(
                milestoneName: "Christmas",
                emoji: nil,
                formattedDate: "Dec 25"
            ),
            "Christmas · Dec 25"
        )
    }

    /// `ForYouViewModel.formattedDate(_:)` returns the raw stored string when it
    /// can't parse, and a milestone could carry an empty name — neither may
    /// leave a dangling separator.
    func testBadgeOmitsTheSeparatorWhenAPartIsMissing() {
        XCTAssertEqual(
            MilestoneRecommendationSheet.badgeText(
                milestoneName: "Christmas",
                emoji: "🎄",
                formattedDate: "   "
            ),
            "🎄 Christmas"
        )
        XCTAssertEqual(
            MilestoneRecommendationSheet.badgeText(
                milestoneName: "  ",
                emoji: nil,
                formattedDate: "Dec 25"
            ),
            "Dec 25"
        )
    }
}

// MARK: - Title & Body

@MainActor
final class MilestoneRecommendationSheetCopyTests: XCTestCase {

    func testTitleNamesTheEvent() {
        XCTAssertEqual(
            MilestoneRecommendationSheet.title(milestoneName: "Christmas"),
            "Get gift ideas for Christmas?"
        )
        XCTAssertEqual(
            MilestoneRecommendationSheet.title(milestoneName: "Jas's Birthday"),
            "Get gift ideas for Jas's Birthday?"
        )
    }

    /// A blank name must not produce "Get gift ideas for ?".
    func testTitleFallsBackWhenTheNameIsBlank() {
        XCTAssertEqual(
            MilestoneRecommendationSheet.title(milestoneName: "   "),
            "Get gift ideas for this event?"
        )
    }

    func testBodyNamesThePartner() {
        XCTAssertEqual(
            MilestoneRecommendationSheet.body(partnerName: "Jas"),
            "We'll find personalized recommendations for Jas based on their interests and the hints you've saved."
        )
    }

    /// Matches `OccasionCopy.resolve`'s fallback for the same situation.
    func testBodyFallsBackWhenThePartnerNameIsBlank() {
        XCTAssertTrue(
            MilestoneRecommendationSheet.body(partnerName: "").contains("your partner")
        )
    }

    /// The app has no wishlist and no purchase history, and never collects a
    /// gender — the comp's copy claimed all three. Guards the rewrite so nobody
    /// "restores" the mock's wording later.
    func testBodyClaimsNothingTheAppDoesNotDo() {
        let body = MilestoneRecommendationSheet.body(partnerName: "Jas").lowercased()
        for forbidden in ["wishlist", "past gifts", " her ", " his "] {
            XCTAssertFalse(body.contains(forbidden), "Body copy must not mention \"\(forbidden)\"")
        }
    }
}

// MARK: - Occasion Emoji

@MainActor
final class OccasionEmojiTests: XCTestCase {

    func testKnownCategoriesResolve() {
        XCTAssertEqual(OccasionCopy.emoji(for: "christmas"), "🎄")
        XCTAssertEqual(OccasionCopy.emoji(for: "birthday"), "🎂")
        XCTAssertEqual(OccasionCopy.emoji(for: "halloween"), "🎃")
    }

    /// `default` means "we don't know what this occasion is" — there is no
    /// honest glyph for that, so the badge falls back to plain text.
    func testDefaultAndUnknownCategoriesHaveNoEmoji() {
        XCTAssertNil(OccasionCopy.emoji(for: OccasionCopy.defaultCategory))
        XCTAssertNil(OccasionCopy.emoji(for: "not_a_real_occasion"))
    }

    /// Pins the map against the copy catalogue, the same guard
    /// `MilestoneOccasionOptionTests` uses — so an occasion added to
    /// `OccasionCopy` can't silently ship without a badge glyph.
    func testEveryKnownCategoryExceptDefaultHasAnEmoji() {
        for category in OccasionCopy.knownCategories where category != OccasionCopy.defaultCategory {
            XCTAssertNotNil(
                OccasionCopy.emoji(for: category),
                "\(category) has copy but no badge emoji"
            )
        }
    }
}

// MARK: - Rendering

@MainActor
final class MilestoneRecommendationSheetRenderingTests: XCTestCase {

    private func makeSheet(
        name: String = "Christmas",
        occasionCategory: String? = "christmas",
        partnerName: String = "Jas",
        formattedDate: String = "Dec 25"
    ) -> MilestoneRecommendationSheet {
        MilestoneRecommendationSheet(
            milestone: makeMilestone(name: name, occasionCategory: occasionCategory),
            partnerName: partnerName,
            formattedDate: formattedDate,
            onGetRecommendations: {},
            onDismiss: {}
        )
    }

    func testSheetRenders() {
        XCTAssertNotNil(UIHostingController(rootView: makeSheet()).view)
    }

    /// A milestone written before migration 00027 resolves to `default`, which
    /// has no emoji — the badge must still render.
    func testSheetRendersWithoutAnOccasionEmoji() {
        XCTAssertNotNil(
            UIHostingController(rootView: makeSheet(occasionCategory: nil)).view
        )
    }

    /// The 26pt headline wraps to three lines on a name this long; the sheet
    /// measures its own height, so this is the case most likely to break it.
    func testSheetRendersWithALongMilestoneName() {
        XCTAssertNotNil(
            UIHostingController(
                rootView: makeSheet(name: "Our Tenth Wedding Anniversary Celebration")
            ).view
        )
    }

    func testSheetRendersWithBlankPartnerNameAndDate() {
        XCTAssertNotNil(
            UIHostingController(rootView: makeSheet(partnerName: "", formattedDate: "")).view
        )
    }

    func testSheetRendersInDarkMode() {
        let view = makeSheet().environment(\.colorScheme, .dark)
        XCTAssertNotNil(UIHostingController(rootView: view).view)
    }

    /// Every occasion the backend can emit must produce a renderable sheet.
    func testSheetRendersEveryKnownOccasionCategory() {
        for category in OccasionCopy.knownCategories {
            XCTAssertNotNil(
                UIHostingController(rootView: makeSheet(occasionCategory: category)).view,
                "Sheet failed to render for \(category)"
            )
        }
    }
}

// MARK: - Callbacks

@MainActor
final class MilestoneRecommendationSheetCallbackTests: XCTestCase {

    func testGetRecommendationsCallbackFires() {
        var fired = false
        let sheet = MilestoneRecommendationSheet(
            milestone: makeMilestone(),
            partnerName: "Jas",
            formattedDate: "Dec 25",
            onGetRecommendations: { fired = true },
            onDismiss: {}
        )
        sheet.onGetRecommendations()
        XCTAssertTrue(fired)
    }

    func testDismissCallbackFires() {
        var fired = false
        let sheet = MilestoneRecommendationSheet(
            milestone: makeMilestone(),
            partnerName: "Jas",
            formattedDate: "Dec 25",
            onGetRecommendations: {},
            onDismiss: { fired = true }
        )
        sheet.onDismiss()
        XCTAssertTrue(fired)
    }
}
