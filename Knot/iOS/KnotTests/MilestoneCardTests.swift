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
            onSeeDetails: {},
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
            onSeeDetails: {},
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
            onSeeDetails: {},
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
            onSeeDetails: {},
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
                onSeeDetails: {},
                onGetRecommendations: {}
            )
            XCTAssertNotNil(
                UIHostingController(rootView: view).view,
                "MilestoneCard should render for milestone type '\(type)'"
            )
        }
    }

    /// "See details" is optional; the card must render without it, leaving the
    /// recommendation icon as the footer's only control.
    func testCardRendersWithoutSeeDetailsAction() {
        let view = MilestoneCard(
            milestone: makeMilestone(),
            partnerName: "Jas",
            formattedDate: "Dec 25",
            urgency: .distant,
            onSeeDetails: nil,
            onGetRecommendations: {}
        )
        XCTAssertNotNil(UIHostingController(rootView: view).view)
    }

    /// Both footer controls present — the layout this change actually ships.
    func testCardRendersWithBothFooterActions() {
        let view = MilestoneCard(
            milestone: makeMilestone(),
            partnerName: "Jas",
            formattedDate: "Dec 25",
            urgency: .distant,
            onSeeDetails: {},
            onGetRecommendations: {}
        )
        XCTAssertNotNil(UIHostingController(rootView: view).view)
    }

    /// The footer now carries three controls on one line, and "For {partner}"
    /// is the variable-length part. A long name must not break the row.
    func testCardRendersWithLongPartnerName() {
        let view = MilestoneCard(
            milestone: makeMilestone(),
            partnerName: "Alexandria Wellington-Fitzgerald",
            formattedDate: "Dec 25",
            urgency: .critical,
            onSeeDetails: {},
            onGetRecommendations: {}
        )
        XCTAssertNotNil(UIHostingController(rootView: view).view)
    }

    /// The "See details" button fires the host's closure.
    func testSeeDetailsCallbackFires() {
        var fired = false
        let view = MilestoneCard(
            milestone: makeMilestone(),
            partnerName: "Jas",
            formattedDate: "Dec 25",
            urgency: .distant,
            onSeeDetails: { fired = true },
            onGetRecommendations: {}
        )
        view.onSeeDetails?()
        XCTAssertTrue(fired)
    }

    /// The recommendation button fires the host's closure.
    func testRecommendationCallbackFires() {
        var fired = false
        let view = MilestoneCard(
            milestone: makeMilestone(),
            partnerName: "Jas",
            formattedDate: "Dec 25",
            urgency: .distant,
            onSeeDetails: {},
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

// MARK: - Milestone Detail (placeholder destination)

@MainActor
final class MilestoneDetailViewTests: XCTestCase {

    func testFullDateExpandsStoredDate() {
        XCTAssertEqual(MilestoneDetailView.fullDate(from: "2000-12-25"), "December 25")
    }

    /// An unparseable stored date must never surface the raw "2000-MM-DD"
    /// storage format. Deliberately not falling back to
    /// `ForYouViewModel.formattedDate(_:)`, which returns that raw string on
    /// exactly the same failure.
    func testFullDateShowsPlaceholderWhenUnparseable() {
        for raw in ["not-a-date", "", "2000-12"] {
            let shown = MilestoneDetailView.fullDate(from: raw)
            XCTAssertEqual(shown, "—", "Unparseable date '\(raw)' should render the placeholder")
            XCTAssertFalse(shown.contains("2000"), "The storage format must never reach the UI")
        }
    }

    /// Out-of-range months make `formattedMilestoneDate` return "", which must
    /// not reach the UI as a blank row.
    func testFullDateShowsPlaceholderOnOutOfRangeMonth() {
        XCTAssertEqual(MilestoneDetailView.fullDate(from: "2000-13-25"), "—")
    }

    func testRecurrenceLabels() {
        XCTAssertEqual(MilestoneDetailView.recurrenceLabel("yearly"), "Every year")
        XCTAssertEqual(MilestoneDetailView.recurrenceLabel("one_time"), "Once")
        // An unrecognised value is humanised rather than shown as a raw slug.
        XCTAssertFalse(MilestoneDetailView.recurrenceLabel("every_other_year").contains("_"))
    }

    /// Every milestone written before migration 00027 resolves to the `default`
    /// occasion category, whose catalogue name is the picker phrasing
    /// "Something Else". The detail row must show the milestone type instead.
    func testOccasionLabelFallsBackToTypeForDefaultCategory() {
        XCTAssertEqual(
            MilestoneDetailView.occasionLabel(
                for: makeMilestone(type: "custom", occasionCategory: "default")
            ),
            "Custom"
        )
        XCTAssertEqual(
            MilestoneDetailView.occasionLabel(
                for: makeMilestone(type: "holiday", occasionCategory: "default")
            ),
            "Holiday"
        )
    }

    /// A category the client's catalogue doesn't know (added on the backend
    /// before the app ships its option) must not render as a bare slug.
    func testOccasionLabelFallsBackToTypeForUnlistedCategory() {
        XCTAssertEqual(
            MilestoneDetailView.occasionLabel(
                for: makeMilestone(type: "holiday", occasionCategory: "st_patricks_day")
            ),
            "Holiday"
        )
    }

    func testOccasionLabelUsesCatalogueName() {
        let label = MilestoneDetailView.occasionLabel(
            for: makeMilestone(type: "holiday", occasionCategory: "christmas")
        )
        XCTAssertEqual(label, MilestoneOccasionOption.option(id: "christmas")?.displayName)
    }

    func testDetailViewRenders() {
        let view = MilestoneDetailView(
            milestone: makeMilestone(),
            partnerName: "Jas",
            onDismiss: {}
        )
        XCTAssertNotNil(UIHostingController(rootView: view).view)
    }

    /// The `default` category ships no illustration — the placeholder artwork
    /// path must render too.
    func testDetailViewRendersWithPlaceholderArtwork() {
        let view = MilestoneDetailView(
            milestone: makeMilestone(type: "custom", occasionCategory: "default"),
            partnerName: "Jas",
            onDismiss: {}
        )
        XCTAssertNotNil(UIHostingController(rootView: view).view)
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
