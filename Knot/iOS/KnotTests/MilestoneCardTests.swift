//
//  MilestoneCardTests.swift
//  KnotTests
//
//  Journal tab redesign — the milestone card's pure helpers plus render smoke tests.
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

// MARK: - Artwork Resolution

@MainActor
final class MilestoneCardArtworkTests: XCTestCase {

    /// A category with bundled artwork resolves to the namespaced asset name.
    func testKnownCategoryResolvesToIllustration() {
        XCTAssertEqual(
            MilestoneCard.artwork(for: "christmas"),
            .illustration("OccasionIllustrations/occasion-christmas")
        )
    }

    /// Underscored categories are slugified to the hyphenated asset name.
    func testUnderscoredCategoryIsSlugified() {
        XCTAssertEqual(
            MilestoneCard.artwork(for: "new_years"),
            .illustration("OccasionIllustrations/occasion-new-years")
        )
        XCTAssertEqual(
            MilestoneCard.artwork(for: "lunar_new_year"),
            .illustration("OccasionIllustrations/occasion-lunar-new-year")
        )
    }

    /// `default` deliberately ships no illustration — it must fall back.
    func testDefaultCategoryFallsBackToPlaceholder() {
        XCTAssertEqual(MilestoneCard.artwork(for: "default"), .placeholder)
    }

    /// An occasion added on the backend before its artwork ships must degrade
    /// to the placeholder rather than render a broken image.
    func testUnknownCategoryFallsBackToPlaceholder() {
        XCTAssertEqual(MilestoneCard.artwork(for: "not_a_real_occasion"), .placeholder)
        XCTAssertEqual(MilestoneCard.artwork(for: ""), .placeholder)
    }

    /// Every category the entry modal knows about — bar `default` — has art,
    /// so a milestone can't reach the card with a category the design forgot.
    func testEveryKnownCategoryExceptDefaultHasArtwork() {
        for category in OccasionCopy.knownCategories where category != OccasionCopy.defaultCategory {
            XCTAssertNotEqual(
                MilestoneCard.artwork(for: category),
                .placeholder,
                "Expected bundled artwork for occasion category '\(category)'"
            )
        }
    }
}

// MARK: - Date Label

@MainActor
final class MilestoneCardDateLabelTests: XCTestCase {

    /// The card uppercases the view model's "MMM d" output for its meta row.
    func testDateLabelUppercasesFormattedDate() {
        XCTAssertEqual(MilestoneCard.dateLabel(from: "Dec 25"), "DEC 25")
        XCTAssertEqual(MilestoneCard.dateLabel(from: "Jan 1"), "JAN 1")
    }

    /// An already-uppercase or empty value passes through unchanged.
    func testDateLabelIsIdempotentAndEmptySafe() {
        XCTAssertEqual(MilestoneCard.dateLabel(from: "FEB 14"), "FEB 14")
        XCTAssertEqual(MilestoneCard.dateLabel(from: ""), "")
    }
}

// MARK: - Countdown Colour

@MainActor
final class MilestoneCardCountdownColorTests: XCTestCase {

    /// The design's accent pink is the default; only the two genuinely urgent
    /// tiers deviate, so a milestone days away can't read like one months away.
    func testUrgentTiersUseStatusColorsAndTheRestUseAccent() {
        XCTAssertEqual(MilestoneCard.countdownColor(for: .critical), Theme.statusError)
        XCTAssertEqual(MilestoneCard.countdownColor(for: .soon), Theme.statusWarning)
        XCTAssertEqual(MilestoneCard.countdownColor(for: .upcoming), Theme.accent)
        XCTAssertEqual(MilestoneCard.countdownColor(for: .planning), Theme.accent)
        XCTAssertEqual(MilestoneCard.countdownColor(for: .distant), Theme.accent)
    }

    /// The urgent tiers must be visually distinct from the default, or the
    /// signal the timeline carried is silently lost.
    func testUrgentTiersAreDistinctFromAccent() {
        XCTAssertNotEqual(MilestoneCard.countdownColor(for: .critical), Theme.accent)
        XCTAssertNotEqual(MilestoneCard.countdownColor(for: .soon), Theme.accent)
        XCTAssertNotEqual(
            MilestoneCard.countdownColor(for: .critical),
            MilestoneCard.countdownColor(for: .soon)
        )
    }
}

// MARK: - Rendering

@MainActor
final class MilestoneCardRenderingTests: XCTestCase {

    func testCardRendersWithIllustration() {
        let view = MilestoneCard(
            milestone: makeMilestone(),
            partnerName: "Jas",
            formattedDate: "Dec 25",
            urgency: .distant,
            onGetRecommendations: {}
        )
        XCTAssertNotNil(UIHostingController(rootView: view).view)
    }

    func testCardRendersWithPlaceholderArtwork() {
        let view = MilestoneCard(
            milestone: makeMilestone(
                type: "custom",
                name: "Our First Concert",
                occasionCategory: "default"
            ),
            partnerName: "Jas",
            formattedDate: "Mar 2",
            urgency: .planning,
            onGetRecommendations: {}
        )
        XCTAssertNotNil(UIHostingController(rootView: view).view)
    }

    /// `daysUntil` is optional on the DTO — the countdown must simply be absent.
    func testCardRendersWithoutCountdown() {
        let view = MilestoneCard(
            milestone: makeMilestone(days: nil),
            partnerName: "Jas",
            formattedDate: "Dec 25",
            urgency: .distant,
            onGetRecommendations: {}
        )
        XCTAssertNotNil(UIHostingController(rootView: view).view)
    }

    /// The recommendation button is optional; the card must render without it.
    func testCardRendersWithoutRecommendationAction() {
        let view = MilestoneCard(
            milestone: makeMilestone(),
            partnerName: "Jas",
            formattedDate: "Dec 25",
            urgency: .distant,
            onGetRecommendations: nil
        )
        XCTAssertNotNil(UIHostingController(rootView: view).view)
    }

    func testCardRendersEveryMilestoneType() {
        for type in ["birthday", "anniversary", "holiday", "custom"] {
            let view = MilestoneCard(
                milestone: makeMilestone(type: type, occasionCategory: "birthday"),
                partnerName: "Jas",
                formattedDate: "Jan 1",
                urgency: .distant,
                onGetRecommendations: {}
            )
            XCTAssertNotNil(
                UIHostingController(rootView: view).view,
                "MilestoneCard should render for milestone type '\(type)'"
            )
        }
    }

    /// The recommendation button fires the host's closure.
    func testRecommendationCallbackFires() {
        var fired = false
        let view = MilestoneCard(
            milestone: makeMilestone(),
            partnerName: "Jas",
            formattedDate: "Dec 25",
            urgency: .distant,
            onGetRecommendations: { fired = true }
        )
        view.onGetRecommendations?()
        XCTAssertTrue(fired)
    }
}

// MARK: - Partner Initial Avatar

@MainActor
final class PartnerInitialAvatarTests: XCTestCase {

    func testAvatarRenders() {
        XCTAssertNotNil(
            UIHostingController(rootView: PartnerInitialAvatar(name: "Jas", diameter: 56)).view
        )
    }

    /// The partner name defaults to "Your Partner" and can in principle be
    /// blank — neither may crash the initial lookup.
    func testAvatarRendersWithBlankName() {
        XCTAssertNotNil(
            UIHostingController(rootView: PartnerInitialAvatar(name: "   ", diameter: 22)).view
        )
        XCTAssertNotNil(
            UIHostingController(rootView: PartnerInitialAvatar(name: "", diameter: 22)).view
        )
    }
}

// MARK: - Journal Screen

@MainActor
final class JournalViewRenderingTests: XCTestCase {

    /// The redesigned Journal tab still renders (header + card feed).
    func testJournalViewRenders() {
        XCTAssertNotNil(UIHostingController(rootView: ForYouView()).view)
    }
}

// MARK: - Upcoming Count Indicator

@MainActor
final class UpcomingCountLabelTests: XCTestCase {

    /// The count badge is a bare number, so VoiceOver gets the whole header as
    /// one label — and it has to say "milestone" or "milestones" correctly.
    func testSingularAndPlural() {
        XCTAssertEqual(ForYouView.upcomingAccessibilityLabel(count: 1), "Upcoming, 1 milestone")
        XCTAssertEqual(ForYouView.upcomingAccessibilityLabel(count: 2), "Upcoming, 2 milestones")
        XCTAssertEqual(ForYouView.upcomingAccessibilityLabel(count: 11), "Upcoming, 11 milestones")
    }

    /// The header only renders alongside a non-empty feed, but the label must
    /// not read "1 milestone" for a zero it should never be handed.
    func testZeroIsPlural() {
        XCTAssertEqual(ForYouView.upcomingAccessibilityLabel(count: 0), "Upcoming, 0 milestones")
    }
}
