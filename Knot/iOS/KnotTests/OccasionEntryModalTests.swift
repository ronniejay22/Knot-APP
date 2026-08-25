//
//  OccasionEntryModalTests.swift
//  KnotTests
//
//  Covers the occasion entry modal shown on milestone push tap-through:
//  the copy resolver, token interpolation, timing phrasing, and rendering.
//

import XCTest
import SwiftUI
@testable import Knot

// MARK: - Copy resolution

@MainActor
final class OccasionCopyTests: XCTestCase {

    /// Mirrors `OCCASION_CATEGORIES` in backend `app/services/occasion_category.py`.
    /// If the backend gains a category and this list isn't updated, the modal
    /// would silently fall back to generic copy — so pin both ends.
    private let backendCategories = [
        "birthday", "anniversary",
        "valentines_day", "new_years",
        "mothers_day", "fathers_day",
        "christmas", "hanukkah", "diwali", "lunar_new_year", "eid",
        "thanksgiving", "easter", "halloween",
        "graduation", "new_job", "new_home", "big_day", "thinking_of_you",
        "just_because", "hint_followup",
        "default",
    ]

    func testEveryBackendCategoryHasCopy() {
        for category in backendCategories {
            XCTAssertTrue(
                OccasionCopy.knownCategories.contains(category),
                "No modal copy for backend category '\(category)'"
            )
        }
    }

    func testNoExtraCategories() {
        XCTAssertEqual(
            OccasionCopy.knownCategories,
            Set(backendCategories),
            "Copy categories drifted from the backend's set"
        )
    }

    /// The failure that matters most: an unreplaced token shipping to a user.
    func testNoUnreplacedTokensSurvive() {
        for category in backendCategories {
            let copy = OccasionCopy.resolve(
                category: category,
                partnerName: "Jerry",
                daysUntil: 3,
                milestoneName: "Jerry's Birthday"
            )
            for text in [copy.title, copy.body] {
                XCTAssertFalse(text.contains("{"), "Unreplaced token in \(category): \(text)")
                XCTAssertFalse(text.contains("}"), "Unreplaced token in \(category): \(text)")
            }
            XCTAssertFalse(copy.title.isEmpty)
            XCTAssertFalse(copy.body.isEmpty)
            XCTAssertFalse(copy.ctaLabel.isEmpty)
        }
    }

    /// Missing data must not produce "'s birthday" or "{partner}".
    func testTokensFallBackWhenDataIsMissing() {
        for category in backendCategories {
            let copy = OccasionCopy.resolve(
                category: category,
                partnerName: nil,
                daysUntil: nil,
                milestoneName: nil
            )
            for text in [copy.title, copy.body] {
                XCTAssertFalse(text.contains("{"), "Unreplaced token in \(category)")
            }
        }

        let copy = OccasionCopy.resolve(
            category: "birthday", partnerName: "   ", daysUntil: nil, milestoneName: nil
        )
        XCTAssertTrue(copy.title.contains("your partner"),
                      "A whitespace-only partner name should fall back")
    }

    func testUnknownCategoryFallsBackToDefault() {
        let unknown = OccasionCopy.resolve(
            category: "mardi_gras", partnerName: "Sam", daysUntil: 7, milestoneName: "Mardi Gras"
        )
        let fallback = OccasionCopy.resolve(
            category: "default", partnerName: "Sam", daysUntil: 7, milestoneName: "Mardi Gras"
        )
        XCTAssertEqual(unknown, fallback)
    }

    func testBirthdayCopyMatchesTheApprovedVoice() {
        let copy = OccasionCopy.resolve(
            category: "birthday", partnerName: "Jerry", daysUntil: 3, milestoneName: "Jerry's Birthday"
        )
        XCTAssertEqual(copy.title, "Happy Birthday to Jerry!")
        XCTAssertTrue(copy.body.hasPrefix("Jerry's birthday is in 3 days!"))
        XCTAssertEqual(copy.ctaLabel, "See recommendations")
    }

    /// The one occasion that deliberately breaks the house voice — a heavy week
    /// should not get an exclamation mark or a "See recommendations" CTA.
    func testRoughPatchUsesASofterVoice() {
        let copy = OccasionCopy.resolve(
            category: "thinking_of_you", partnerName: "Alex", daysUntil: nil, milestoneName: nil
        )
        XCTAssertEqual(copy.title, "Thinking Of Alex")
        XCTAssertFalse(copy.title.contains("!"))
        XCTAssertEqual(copy.ctaLabel, "See ideas")
    }

    func testFallbackUsesTheMilestoneName() {
        let copy = OccasionCopy.resolve(
            category: "default", partnerName: "Sam", daysUntil: 7, milestoneName: "First Date"
        )
        XCTAssertTrue(copy.title.contains("First Date"))
        XCTAssertTrue(copy.body.contains("First Date"))
        XCTAssertTrue(copy.body.contains("Sam"))
    }
}

// MARK: - Timing

@MainActor
final class OccasionTimingTests: XCTestCase {

    /// Pushes fire at 14/7/3, but the user can open one at any point — every
    /// value has to read correctly after "is".
    func testTimingPhrases() {
        let cases: [(Int?, String)] = [
            (nil, "coming up"),
            (-2, "here"),
            (0, "today"),
            (1, "tomorrow"),
            (3, "in 3 days"),
            (7, "next week"),
            (10, "in 10 days"),
            (14, "two weeks away"),
            (30, "in 30 days"),
        ]
        for (days, expected) in cases {
            XCTAssertEqual(
                OccasionCopy.timingPhrase(daysUntil: days),
                expected,
                "daysUntil \(String(describing: days))"
            )
        }
    }

    func testTimingReadsCorrectlyInASentence() {
        for days in [0, 1, 3, 7, 14, 21] {
            let copy = OccasionCopy.resolve(
                category: "christmas", partnerName: "Jas", daysUntil: days, milestoneName: nil
            )
            XCTAssertTrue(copy.body.hasPrefix("Christmas is "), copy.body)
        }
    }
}

// MARK: - Illustrations

@MainActor
final class OccasionIllustrationTests: XCTestCase {

    /// Every occasion with artwork in the catalogue must resolve to it — a typo
    /// in a slug would silently drop the illustration.
    func testIllustratedCategoriesResolve() {
        let illustrated = [
            "birthday", "anniversary", "valentines_day", "mothers_day", "fathers_day",
            "christmas", "new_years", "thanksgiving", "easter", "halloween",
            "hanukkah", "diwali", "lunar_new_year", "eid",
            "graduation", "new_job", "new_home", "big_day", "thinking_of_you",
            "just_because", "hint_followup",
        ]
        for category in illustrated {
            XCTAssertNotNil(
                OccasionCopy.illustrationName(for: category),
                "Missing illustration asset for '\(category)'"
            )
        }
    }

    /// There is no `occasion-default` artwork — a generic milestone gets the
    /// card without an image band rather than borrowing another occasion's.
    func testDefaultHasNoIllustration() {
        XCTAssertNil(OccasionCopy.illustrationName(for: "default"))
    }

    func testUnknownCategoryHasNoIllustration() {
        XCTAssertNil(OccasionCopy.illustrationName(for: "mardi_gras"))
    }
}

// MARK: - Rendering

@MainActor
final class OccasionEntryModalRenderingTests: XCTestCase {

    func testRendersForEveryCategory() {
        for category in OccasionCopy.knownCategories {
            let modal = OccasionEntryModal(
                copy: OccasionCopy.resolve(
                    category: category,
                    partnerName: "Jerry",
                    daysUntil: 3,
                    milestoneName: "Jerry's Birthday"
                ),
                onContinue: {},
                onClose: {}
            )
            let host = UIHostingController(rootView: modal)
            XCTAssertNotNil(host.view, "Modal failed to render for '\(category)'")
        }
    }

    /// The no-illustration path is a different layout branch, so exercise it.
    func testRendersWithoutIllustration() {
        let modal = OccasionEntryModal(
            copy: OccasionCopy.resolve(
                category: "default", partnerName: "Sam", daysUntil: 7, milestoneName: "First Date"
            ),
            onContinue: {},
            onClose: {}
        )
        XCTAssertNotNil(UIHostingController(rootView: modal).view)
    }

    /// A push from a backend predating this feature carries no display payload.
    /// There is nothing to say in a modal at that point, so the cover must go
    /// straight to the picks rather than show placeholder copy.
    func testCoverSkipsTheModalWithoutADisplayPayload() {
        let cover = MilestoneRecommendationsCoverView(
            milestoneId: "m-1",
            notificationId: nil,
            display: nil,
            onDismiss: {}
        )
        XCTAssertFalse(cover.showsEntryModalOnAppear)
        XCTAssertNotNil(UIHostingController(rootView: cover).view)
    }

    func testCoverShowsTheModalWhenThePushCarriesContext() {
        let cover = MilestoneRecommendationsCoverView(
            milestoneId: "m-1",
            notificationId: nil,
            display: MilestonePushDisplay(
                milestoneName: "Jas's Birthday",
                partnerName: "Jas",
                daysBefore: 7,
                occasionCategory: "birthday"
            ),
            onDismiss: {}
        )
        XCTAssertTrue(cover.showsEntryModalOnAppear)
    }
}

// MARK: - Push payload

@MainActor
final class OccasionPushPayloadTests: XCTestCase {

    func testCategoryRidesInTheDeepLinkDestination() {
        let destination = DeepLinkHandler.destination(
            milestoneId: "m-1",
            notificationId: "n-1",
            milestoneName: "Jas's Birthday",
            partnerName: "Jas",
            daysBefore: 7,
            occasionCategory: "birthday"
        )

        guard case let .milestoneRecommendations(_, _, display) = destination else {
            return XCTFail("Expected a milestoneRecommendations destination")
        }
        XCTAssertEqual(display?.occasionCategory, "birthday")
    }

    /// A push from a backend predating the key still routes — the modal just
    /// falls back to generic copy.
    func testMissingCategoryStillRoutes() {
        let destination = DeepLinkHandler.destination(
            milestoneId: "m-1",
            notificationId: nil,
            milestoneName: "Jas's Birthday",
            partnerName: "Jas",
            daysBefore: 7
        )

        guard case let .milestoneRecommendations(_, _, display) = destination else {
            return XCTFail("Expected a milestoneRecommendations destination")
        }
        XCTAssertNil(display?.occasionCategory)

        let copy = OccasionCopy.resolve(
            category: display?.occasionCategory ?? OccasionCopy.defaultCategory,
            partnerName: display?.partnerName,
            daysUntil: display?.daysBefore,
            milestoneName: display?.milestoneName
        )
        XCTAssertTrue(copy.title.contains("Jas's Birthday"))
        XCTAssertFalse(copy.title.contains("{"))
    }

    func testEmptyCategoryIsTreatedAsAbsent() {
        let destination = DeepLinkHandler.destination(
            milestoneId: "m-1",
            notificationId: nil,
            milestoneName: "Jas's Birthday",
            occasionCategory: ""
        )

        guard case let .milestoneRecommendations(_, _, display) = destination else {
            return XCTFail("Expected a milestoneRecommendations destination")
        }
        XCTAssertNil(display?.occasionCategory)
    }
}
