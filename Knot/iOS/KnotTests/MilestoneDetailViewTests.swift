//
//  MilestoneDetailViewTests.swift
//  KnotTests
//
//  The Journal event detail screen — its pure helpers, the saved-ideas view
//  model, and render smoke tests for the populated and empty states.
//

import XCTest
import SwiftUI
import SwiftData
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

/// An isolated in-memory store, so each test starts from a known empty library.
@MainActor
private func makeContext() throws -> ModelContext {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(for: SavedRecommendation.self, configurations: config)
    return ModelContext(container)
}

@MainActor
@discardableResult
private func insertSaved(
    _ context: ModelContext,
    id: String,
    milestoneId: String?,
    title: String = "A gift",
    savedAt: Date = Date()
) -> SavedRecommendation {
    let saved = SavedRecommendation(
        recommendationId: id,
        recommendationType: "gift",
        title: title,
        descriptionText: "A note about the gift.",
        priceCents: 4500,
        isIdea: false,
        milestoneId: milestoneId,
        savedAt: savedAt
    )
    context.insert(saved)
    try? context.save()
    return saved
}

@MainActor
private func makeItem(id: String, title: String = "A gift") -> RecommendationItemResponse {
    RecommendationItemResponse(
        id: id,
        recommendationType: "gift",
        title: title,
        description: "A note about the gift.",
        priceCents: 4500
    )
}

// MARK: - Date Formatting

@MainActor
final class MilestoneDetailDateTests: XCTestCase {

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
    /// not reach the UI as a blank column.
    func testFullDateShowsPlaceholderOnOutOfRangeMonth() {
        XCTAssertEqual(MilestoneDetailView.fullDate(from: "2000-13-25"), "—")
    }

    /// `daysUntilText(nil)` is "" — which a past one-time milestone genuinely
    /// produces — and an empty value under a "COUNTDOWN" label reads as a
    /// rendering failure. The three-column grid can't drop a column without
    /// stranding a divider, so it shows the same placeholder as DATE.
    func testCountdownShowsPlaceholderWhenUnknown() {
        XCTAssertEqual(MilestoneDetailView.countdownText(for: nil), "—")
        XCTAssertFalse(MilestoneDetailView.countdownText(for: nil).isEmpty)
    }

    func testCountdownUsesTheSharedPhrasingWhenKnown() {
        XCTAssertEqual(MilestoneDetailView.countdownText(for: 0), "Today!")
        XCTAssertEqual(MilestoneDetailView.countdownText(for: 1), "Tomorrow")
        XCTAssertEqual(MilestoneDetailView.countdownText(for: 175), "in 175 days")
    }
}

// MARK: - Section Header Accessibility

@MainActor
final class MilestoneDetailAccessibilityLabelTests: XCTestCase {

    /// A badge announcing a bare number after "Saved ideas" says nothing on its
    /// own, so the header and count read as one element.
    func testSingularPluralAndEmpty() {
        XCTAssertEqual(
            MilestoneDetailView.savedIdeasAccessibilityLabel(count: 0),
            "Saved ideas, none yet"
        )
        XCTAssertEqual(
            MilestoneDetailView.savedIdeasAccessibilityLabel(count: 1),
            "Saved ideas, 1 saved"
        )
        XCTAssertEqual(
            MilestoneDetailView.savedIdeasAccessibilityLabel(count: 3),
            "Saved ideas, 3 saved"
        )
    }
}

// MARK: - Saved Ideas View Model

@MainActor
final class MilestoneDetailViewModelTests: XCTestCase {

    func testLoadsOnlyThisMilestonesSaves() async throws {
        let context = try makeContext()
        insertSaved(context, id: "mine-1", milestoneId: "m1")
        insertSaved(context, id: "other", milestoneId: "m2")

        let viewModel = MilestoneDetailViewModel()
        await viewModel.load(milestoneId: "m1", modelContext: context)

        XCTAssertEqual(viewModel.savedIdeas.map(\.recommendationId), ["mine-1"])
    }

    /// Saves with no event behind them — the "Surprise them today" card, the
    /// onboarding reveal — must never leak into an event's list.
    func testExcludesSavesWithNoMilestone() async throws {
        let context = try makeContext()
        insertSaved(context, id: "mine-1", milestoneId: "m1")
        insertSaved(context, id: "unattributed", milestoneId: nil)

        let viewModel = MilestoneDetailViewModel()
        await viewModel.load(milestoneId: "m1", modelContext: context)

        XCTAssertEqual(viewModel.savedIdeas.map(\.recommendationId), ["mine-1"])
    }

    func testOrdersNewestFirst() async throws {
        let context = try makeContext()
        insertSaved(
            context,
            id: "older",
            milestoneId: "m1",
            savedAt: Date(timeIntervalSince1970: 1_000)
        )
        insertSaved(
            context,
            id: "newer",
            milestoneId: "m1",
            savedAt: Date(timeIntervalSince1970: 2_000)
        )

        let viewModel = MilestoneDetailViewModel()
        await viewModel.load(milestoneId: "m1", modelContext: context)

        XCTAssertEqual(viewModel.savedIdeas.map(\.recommendationId), ["newer", "older"])
    }

    func testEmptyWhenNothingSavedForThisMilestone() async throws {
        let context = try makeContext()
        insertSaved(context, id: "other", milestoneId: "m2")

        let viewModel = MilestoneDetailViewModel()
        await viewModel.load(milestoneId: "m1", modelContext: context)

        XCTAssertTrue(viewModel.savedIdeas.isEmpty)
    }

    /// Remove drops the row from the store, not just from the in-memory list —
    /// a reload must not bring it back.
    func testRemoveDeletesFromTheStore() async throws {
        let context = try makeContext()
        let saved = insertSaved(context, id: "mine-1", milestoneId: "m1")
        insertSaved(context, id: "mine-2", milestoneId: "m1")

        let viewModel = MilestoneDetailViewModel()
        await viewModel.load(milestoneId: "m1", modelContext: context)
        XCTAssertEqual(viewModel.savedIdeas.count, 2)

        viewModel.remove(saved, modelContext: context)
        XCTAssertEqual(viewModel.savedIdeas.map(\.recommendationId), ["mine-2"])

        await viewModel.load(milestoneId: "m1", modelContext: context)
        XCTAssertEqual(
            viewModel.savedIdeas.map(\.recommendationId),
            ["mine-2"],
            "A removed idea must not come back on reload"
        )
    }
}

// MARK: - Save Attribution

@MainActor
final class SavedRecommendationMilestoneAttributionTests: XCTestCase {

    /// The default keeps every existing call site — and every save made from a
    /// surface with no event — unattributed.
    func testMilestoneIdDefaultsToNil() {
        let saved = SavedRecommendation(
            recommendationId: "r1",
            recommendationType: "gift",
            title: "A gift"
        )
        XCTAssertNil(saved.milestoneId)
    }

    func testMilestoneIdIsStoredWhenProvided() {
        let saved = SavedRecommendation(
            recommendationId: "r1",
            recommendationType: "gift",
            title: "A gift",
            milestoneId: "m1"
        )
        XCTAssertEqual(saved.milestoneId, "m1")
    }

    /// A save made from an event stamps that event.
    func testSavingFromAnEventAttributesTheIdea() async throws {
        let context = try makeContext()
        let viewModel = RecommendationsViewModel()
        viewModel.configure(modelContext: context, milestoneId: "m1")

        viewModel.saveRecommendation(makeItem(id: "r1"))

        let detail = MilestoneDetailViewModel()
        await detail.load(milestoneId: "m1", modelContext: context)
        XCTAssertEqual(detail.savedIdeas.map(\.recommendationId), ["r1"])
    }

    /// `savedRecommendationIds` spans the whole library, so an idea saved
    /// earlier from a no-event surface would otherwise hit the early return and
    /// could never reach an event's list — the button reads "Saved" while the
    /// detail screen stays empty.
    func testResavingFromAnEventBackfillsAnUnattributedIdea() async throws {
        let context = try makeContext()

        let justBecause = RecommendationsViewModel()
        justBecause.configure(modelContext: context)
        justBecause.saveRecommendation(makeItem(id: "r1"))

        let fromEvent = RecommendationsViewModel()
        fromEvent.configure(modelContext: context, milestoneId: "m1")
        fromEvent.saveRecommendation(makeItem(id: "r1"))

        let detail = MilestoneDetailViewModel()
        await detail.load(milestoneId: "m1", modelContext: context)
        XCTAssertEqual(
            detail.savedIdeas.map(\.recommendationId),
            ["r1"],
            "An unattributed idea re-saved from an event should appear under it"
        )
    }

    /// Backfill fills a blank; it never steals. `recommendationId` is unique, so
    /// re-pointing an attributed idea would silently drop it from the other
    /// event's list.
    func testResavingDoesNotStealAnIdeaFromAnotherEvent() async throws {
        let context = try makeContext()

        let first = RecommendationsViewModel()
        first.configure(modelContext: context, milestoneId: "m1")
        first.saveRecommendation(makeItem(id: "r1"))

        let second = RecommendationsViewModel()
        second.configure(modelContext: context, milestoneId: "m2")
        second.saveRecommendation(makeItem(id: "r1"))

        let original = MilestoneDetailViewModel()
        await original.load(milestoneId: "m1", modelContext: context)
        XCTAssertEqual(original.savedIdeas.map(\.recommendationId), ["r1"])

        let other = MilestoneDetailViewModel()
        await other.load(milestoneId: "m2", modelContext: context)
        XCTAssertTrue(other.savedIdeas.isEmpty)
    }

    /// A save with no event behind it stays unattributed.
    func testSavingWithoutAnEventLeavesTheIdeaUnattributed() async throws {
        let context = try makeContext()
        let viewModel = RecommendationsViewModel()
        viewModel.configure(modelContext: context)

        viewModel.saveRecommendation(makeItem(id: "r1"))

        let descriptor = FetchDescriptor<SavedRecommendation>()
        let saved = try context.fetch(descriptor)
        XCTAssertEqual(saved.count, 1)
        XCTAssertNil(saved.first?.milestoneId)
    }
}

// MARK: - Rendering

@MainActor
final class MilestoneDetailRenderingTests: XCTestCase {

    private func host(
        milestone: MilestoneItemResponse,
        context: ModelContext
    ) -> UIView? {
        let view = MilestoneDetailView(
            milestone: milestone,
            partnerName: "Jas",
            urgency: .distant,
            onGetIdeas: {},
            onDismiss: {}
        )
        .modelContext(context)

        return UIHostingController(rootView: view).view
    }

    func testRendersWithSavedIdeas() throws {
        let context = try makeContext()
        insertSaved(context, id: "mine-1", milestoneId: "m1", title: "Cozy Ribbed Knit Scarf")

        XCTAssertNotNil(host(milestone: makeMilestone(), context: context))
    }

    func testRendersEmptyState() throws {
        let context = try makeContext()

        XCTAssertNotNil(host(milestone: makeMilestone(), context: context))
    }

    /// The `default` category ships no illustration — the placeholder artwork
    /// path must render too.
    func testRendersWithPlaceholderArtwork() throws {
        let context = try makeContext()

        XCTAssertNotNil(
            host(
                milestone: makeMilestone(type: "custom", occasionCategory: "default"),
                context: context
            )
        )
    }

    /// A milestone with no countdown must not render a blank column.
    func testRendersWithoutCountdown() throws {
        let context = try makeContext()

        XCTAssertNotNil(host(milestone: makeMilestone(days: nil), context: context))
    }

    func testRendersEveryUrgencyTier() throws {
        let context = try makeContext()

        for urgency in [
            MilestoneUrgency.critical,
            .soon,
            .upcoming,
            .planning,
            .distant
        ] {
            let view = MilestoneDetailView(
                milestone: makeMilestone(),
                partnerName: "Jas",
                urgency: urgency,
                onGetIdeas: {},
                onDismiss: {}
            )
            .modelContext(context)

            XCTAssertNotNil(
                UIHostingController(rootView: view).view,
                "Detail should render for urgency \(urgency)"
            )
        }
    }
}
