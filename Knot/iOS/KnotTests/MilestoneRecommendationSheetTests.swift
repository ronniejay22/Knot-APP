//
//  MilestoneRecommendationSheetTests.swift
//  KnotTests
//
//  The bottom sheet the Journal card's recommendation icon raises — the
//  occasion-framed copy behind it (`MilestoneRecommendationCopy`), the occasion
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
            MilestoneRecommendationCopy.badge(
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
            MilestoneRecommendationCopy.badge(
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
            MilestoneRecommendationCopy.badge(
                milestoneName: "Christmas",
                emoji: "🎄",
                formattedDate: "   "
            ),
            "🎄 Christmas"
        )
        XCTAssertEqual(
            MilestoneRecommendationCopy.badge(
                milestoneName: "  ",
                emoji: nil,
                formattedDate: "Dec 25"
            ),
            "Dec 25"
        )
    }
}

// MARK: - Framing

@MainActor
final class MilestoneRecommendationFramingTests: XCTestCase {

    func testCategoriesMapToTheirFraming() {
        XCTAssertEqual(MilestoneRecommendationCopy.framing(for: "christmas"), .giftForward)
        XCTAssertEqual(MilestoneRecommendationCopy.framing(for: "birthday"), .giftForward)
        XCTAssertEqual(MilestoneRecommendationCopy.framing(for: "anniversary"), .sharedOccasion)
        XCTAssertEqual(MilestoneRecommendationCopy.framing(for: "halloween"), .sharedOccasion)
        XCTAssertEqual(MilestoneRecommendationCopy.framing(for: "thinking_of_you"), .gesture)
        XCTAssertEqual(MilestoneRecommendationCopy.framing(for: "big_day"), .gesture)
        XCTAssertEqual(MilestoneRecommendationCopy.framing(for: "just_because"), .spontaneous)
    }

    /// `default` means "we don't know what this occasion is", which is exactly
    /// what `.unknown` is for — and a key from a newer backend must land there
    /// too rather than trapping or producing an empty sheet.
    func testDefaultAndUnrecognisedCategoriesResolveToUnknown() {
        XCTAssertEqual(
            MilestoneRecommendationCopy.framing(for: OccasionCopy.defaultCategory),
            .unknown
        )
        XCTAssertEqual(
            MilestoneRecommendationCopy.framing(for: "not_a_real_occasion"),
            .unknown
        )
    }

    /// Pins the framing table against the copy catalogue, the same guard shape
    /// `testEveryKnownCategoryExceptDefaultHasAnEmoji` uses — so an occasion
    /// added to `OccasionCopy` cannot ship unframed.
    func testEveryKnownCategoryIsFramed() {
        for category in OccasionCopy.knownCategories {
            XCTAssertTrue(
                MilestoneRecommendationCopy.framedCategories.contains(category),
                "\(category) has copy but no framing"
            )
        }
    }

    /// The reverse direction: a framing entry for a category the backend can't
    /// emit is dead weight that will never be exercised.
    func testEveryFramedCategoryIsAKnownOccasion() {
        for category in MilestoneRecommendationCopy.framedCategories {
            XCTAssertTrue(
                OccasionCopy.knownCategories.contains(category),
                "\(category) is framed but is not an occasion the backend emits"
            )
        }
    }
}

// MARK: - Title

@MainActor
final class MilestoneRecommendationTitleTests: XCTestCase {

    private func title(_ framing: MilestoneRecommendationCopy.Framing) -> String {
        MilestoneRecommendationCopy.title(
            framing: framing,
            milestoneName: "Christmas",
            partnerName: "Jas"
        )
    }

    func testEachFramingAsksItsOwnQuestion() {
        XCTAssertEqual(title(.giftForward), "Get ideas for Christmas?")
        XCTAssertEqual(title(.sharedOccasion), "Plan Christmas together?")
        XCTAssertEqual(title(.gesture), "Ways to show up for Jas?")
        XCTAssertEqual(title(.spontaneous), "Surprise Jas today?")
        XCTAssertEqual(title(.unknown), "Get ideas for Christmas?")
    }

    /// The point of the whole framework: the sheet fronts a pipeline that emits
    /// gifts, experiences, dates, ideas and plans, so its headline must not
    /// promise one type.
    func testNoTitlePromisesGiftsAlone() {
        for framing in MilestoneRecommendationCopy.Framing.allCases {
            let resolved = title(framing).lowercased()
            XCTAssertFalse(
                resolved.contains("gift"),
                "\(framing) title names gifts specifically: \(resolved)"
            )
        }
    }

    /// A blank name must not produce "Get ideas for ?".
    func testTitleFallsBackWhenTheNameIsBlank() {
        XCTAssertEqual(
            MilestoneRecommendationCopy.title(
                framing: .giftForward,
                milestoneName: "   ",
                partnerName: "Jas"
            ),
            "Get ideas for this event?"
        )
    }

    /// Matches `OccasionCopy.resolve`'s fallback for the same situation.
    func testTitleFallsBackWhenThePartnerNameIsBlank() {
        XCTAssertEqual(
            MilestoneRecommendationCopy.title(
                framing: .gesture,
                milestoneName: "Christmas",
                partnerName: " "
            ),
            "Ways to show up for your partner?"
        )
    }
}

// MARK: - Body

@MainActor
final class MilestoneRecommendationBodyTests: XCTestCase {

    private func body(
        _ framing: MilestoneRecommendationCopy.Framing,
        name: String = "Christmas",
        partner: String = "Jas",
        daysUntil: Int? = 175
    ) -> String {
        MilestoneRecommendationCopy.body(
            framing: framing,
            milestoneName: name,
            partnerName: partner,
            daysUntil: daysUntil
        )
    }

    /// The contextual half — what is coming, and when.
    func testBodyLeadsWithTheEventAndItsTiming() {
        XCTAssertEqual(
            body(.giftForward),
            "Christmas is in 175 days. We'll find gifts, experiences and plans for Jas, built from their interests and how they like to be loved."
        )
        XCTAssertEqual(
            body(.sharedOccasion, name: "Our Anniversary", daysUntil: 7),
            "Our Anniversary is next week. We'll find date plans, experiences and gifts for the two of you, built from Jas's interests and how they like to be loved."
        )
        XCTAssertEqual(
            body(.gesture, name: "Jas's Big Presentation", daysUntil: 3),
            "Jas's Big Presentation is in 3 days. We'll find small gestures, thoughtful gifts and low-key ideas for Jas, built from their interests and how they like to be loved."
        )
    }

    /// `timingPhrase` is written to read after "is" for every value the backend
    /// can produce, including same-day and past-due.
    func testTimingPhrasingCoversTheEdges() {
        XCTAssertTrue(body(.giftForward, daysUntil: 0).hasPrefix("Christmas is today."))
        XCTAssertTrue(body(.giftForward, daysUntil: 1).hasPrefix("Christmas is tomorrow."))
        XCTAssertTrue(body(.giftForward, daysUntil: -2).hasPrefix("Christmas is here."))
        XCTAssertTrue(body(.giftForward, daysUntil: 14).hasPrefix("Christmas is two weeks away."))
    }

    /// A past one-time milestone genuinely has no day count. Asserting a timing
    /// it doesn't have would be worse than saying nothing, so the lead sentence
    /// is dropped and the offer clause stands alone.
    func testUndatedMilestoneDropsTheLeadSentence() {
        let resolved = body(.giftForward, daysUntil: nil)
        XCTAssertFalse(resolved.contains("Christmas is"))
        XCTAssertTrue(resolved.hasPrefix("We'll find gifts"))
    }

    /// A timing sentence is nonsense for an occasion that is the absence of one.
    func testSpontaneousLeadsWithItsOwnSentenceRegardlessOfDate() {
        XCTAssertTrue(body(.spontaneous).hasPrefix("No occasion needed."))
        XCTAssertTrue(body(.spontaneous, daysUntil: nil).hasPrefix("No occasion needed."))
    }

    /// The regression guard for the actual request: every framing must promise
    /// more than one kind of recommendation.
    func testEveryFramingNamesMoreThanOneRecommendationType() {
        let types = ["gift", "experience", "date", "idea", "plan", "gesture"]

        for framing in MilestoneRecommendationCopy.Framing.allCases {
            let resolved = body(framing).lowercased()
            let named = types.filter { resolved.contains($0) }
            XCTAssertGreaterThanOrEqual(
                named.count, 2,
                "\(framing) body names only \(named): \(resolved)"
            )
        }
    }

    func testBodyFallsBackWhenThePartnerNameIsBlank() {
        for framing in MilestoneRecommendationCopy.Framing.allCases {
            XCTAssertTrue(
                body(framing, partner: "  ").contains("your partner"),
                "\(framing) body drops the partner fallback"
            )
        }
    }

    /// The grounding tail may only name mechanisms the user can actually reach.
    /// Three claims have already failed that test and are pinned here:
    ///
    /// - `wishlist` / `past gifts` — the comp promised both; the app has
    ///   neither a wishlist nor purchase history.
    /// - `her` / `his` — the comp used a pronoun for a gender the app never
    ///   collects.
    /// - `hint` — hint capture has **no UI entry point**: `SessionHintsSheet`
    ///   is defined but never presented (the Refresh button that raised it was
    ///   removed), so `HintService.createHint` is unreachable. The backend
    ///   still reads hints into the prompt, but a user cannot save one, so
    ///   "the hints you've saved" invited an action the app doesn't offer.
    ///   That one shipped *past this test* because the list only named the
    ///   comp's claims — hence this note, and hence the check below that the
    ///   list itself hasn't been quietly emptied.
    func testNoBodyClaimsAnythingTheAppDoesNotDo() {
        let forbiddenClaims = ["wishlist", "past gifts", " her ", " his ", "hint"]

        // A guard that can be defeated by deleting its own list isn't a guard.
        XCTAssertEqual(
            forbiddenClaims.count, 5,
            "Claims were removed from the forbidden list — each was added because copy shipped that the app could not back up"
        )

        for framing in MilestoneRecommendationCopy.Framing.allCases {
            let resolved = body(framing).lowercased()
            for forbidden in forbiddenClaims {
                XCTAssertFalse(
                    resolved.contains(forbidden),
                    "\(framing) body mentions \"\(forbidden)\""
                )
            }
        }
    }

    /// The replacement tail names interests and love languages. Both are
    /// collected during onboarding and remain editable in Settings → Edit
    /// Profile, and both are read by the generation prompt on every run — so
    /// unlike hints, the sheet is describing something the user can act on.
    func testEveryFramingGroundsItselfInReachableVaultFields() {
        for framing in MilestoneRecommendationCopy.Framing.allCases {
            let resolved = body(framing).lowercased()
            XCTAssertTrue(
                resolved.contains("interests"),
                "\(framing) body drops the interests grounding"
            )
            XCTAssertTrue(
                resolved.contains("how they like to be loved"),
                "\(framing) body drops the love-language grounding"
            )
        }
    }
}

// MARK: - Resolution

@MainActor
final class MilestoneRecommendationCopyResolutionTests: XCTestCase {

    /// The three slots must describe the same occasion — resolving them from one
    /// call is what guarantees it.
    func testResolveFillsAllThreeSlotsFromTheMilestone() {
        let copy = MilestoneRecommendationCopy.resolve(
            milestone: makeMilestone(),
            partnerName: "Jas",
            formattedDate: "Dec 25"
        )

        XCTAssertEqual(copy.badge, "🎄 Christmas · Dec 25")
        XCTAssertEqual(copy.title, "Get ideas for Christmas?")
        XCTAssertTrue(copy.body.hasPrefix("Christmas is in 175 days."))
    }

    /// A `{token}` reaching the screen is the failure mode a template system
    /// invites; this file interpolates directly, and this pins that it stays
    /// that way for every occasion and both date states.
    func testNoResolvedCopyLeaksATemplateToken() {
        for category in OccasionCopy.knownCategories {
            for days in [175, nil] {
                let copy = MilestoneRecommendationCopy.resolve(
                    milestone: makeMilestone(days: days, occasionCategory: category),
                    partnerName: "Jas",
                    formattedDate: "Dec 25"
                )

                for slot in [copy.badge, copy.title, copy.body] {
                    XCTAssertFalse(
                        slot.contains("{"),
                        "\(category) (days: \(String(describing: days))) leaked a token: \(slot)"
                    )
                    XCTAssertFalse(slot.isEmpty, "\(category) produced an empty slot")
                }
            }
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
