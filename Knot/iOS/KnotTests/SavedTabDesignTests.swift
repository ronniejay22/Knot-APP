//
//  SavedTabDesignTests.swift
//  KnotTests
//
//  The Saved tab's "Saved ideas" design — the shared `SavedIdeaCard` (its tag
//  and VoiceOver mappings and every render path) and `SavedView`'s header
//  copy, empty-state rule and render states. The event-detail call site of
//  the same card stays covered by `MilestoneDetailRenderingTests`.
//

import XCTest
import SwiftUI
import SwiftData
@testable import Knot

// MARK: - Helpers

/// An isolated in-memory store, so each test starts from a known empty library.
@MainActor
private func makeContainer() throws -> ModelContainer {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    return try ModelContainer(for: SavedRecommendation.self, configurations: config)
}

@MainActor
private func makeSaved(
    id: String = "saved-1",
    type: String = "gift",
    title: String = "Japanese Cuisine Cook-Along & Criterion Film Night",
    description: String? = "An evening anchored around making hand-rolled sushi together.",
    priceCents: Int? = nil,
    isIdea: Bool = false,
    completedAt: Date? = nil,
    rating: Int? = nil,
    reflectionNote: String? = nil
) -> SavedRecommendation {
    SavedRecommendation(
        recommendationId: id,
        recommendationType: type,
        title: title,
        descriptionText: description,
        priceCents: priceCents,
        isIdea: isIdea,
        completedAt: completedAt,
        rating: rating,
        reflectionNote: reflectionNote
    )
}

/// Puts a view in a window and lays it out so SwiftUI actually evaluates the
/// body — a bare `host.view` may not — then takes the window down again.
///
/// The render tests are smoke tests, like `MilestoneDetailRenderingTests`:
/// each drives one body path, and a path that traps fails the run. The copy
/// and mappings those paths show are pinned by the pure statics tested here.
///
/// The whole lifecycle stays inside the calling test. A window left up carries
/// its hosting controller into later tests: it receives appearance
/// transitions whenever a later test spins the run loop (a dozen of them
/// stalled the main thread past `SavedViewModelTests`' 2s waits), and
/// `SavedView`'s `.task` could load after its store was gone.
@MainActor
private func render<V: View>(_ view: V, runningTasks: Bool = false) {
    let host = UIHostingController(rootView: view)
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
    window.rootViewController = host
    window.isHidden = false
    host.view.layoutIfNeeded()

    if runningTasks {
        // One run-loop turn lets a `.task` (SavedView's load) run and
        // re-render against the live store before teardown.
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        host.view.layoutIfNeeded()
    }

    window.isHidden = true
    window.rootViewController = nil
    // Flush the disappearance here rather than in whichever test runs next.
    RunLoop.main.run(until: Date().addingTimeInterval(0.05))
}

// MARK: - Card Tag

@MainActor
final class SavedIdeaCardBadgeTests: XCTestCase {

    func testSavedStyleShowsTheAccentSavedTag() {
        let badge = SavedIdeaCard.badge(for: .saved)
        XCTAssertEqual(badge.text, "SAVED")
        XCTAssertEqual(badge.variant, .accent)
    }

    func testMomentStyleShowsTheSuccessDoneTag() {
        let badge = SavedIdeaCard.badge(for: .moment)
        XCTAssertEqual(badge.text, "DONE")
        XCTAssertEqual(badge.variant, .success)
    }

    /// A completed date must never read the same as one still to be done.
    func testStylesAreDistinguishable() {
        XCTAssertNotEqual(SavedIdeaCard.badge(for: .saved).text, SavedIdeaCard.badge(for: .moment).text)
        XCTAssertNotEqual(SavedIdeaCard.badge(for: .saved).variant, SavedIdeaCard.badge(for: .moment).variant)
    }

    /// The remove control names the section the card sits in; the `.saved`
    /// wording is the one the event detail screen has always used.
    func testRemoveLabelNamesTheSection() {
        XCTAssertEqual(
            SavedIdeaCard.removeAccessibilityLabel(title: "Sunset Picnic", style: .saved),
            "Remove Sunset Picnic from saved ideas"
        )
        XCTAssertEqual(
            SavedIdeaCard.removeAccessibilityLabel(title: "Sunset Picnic", style: .moment),
            "Remove Sunset Picnic from moments"
        )
    }
}

// MARK: - Card Rendering

@MainActor
final class SavedIdeaCardRenderingTests: XCTestCase {

    /// The default call shape — the one `MilestoneDetailView` uses.
    func testRendersPlainSavedCard() {
        let card = SavedIdeaCard(saved: makeSaved(), onOpen: {}, onRemove: {})
        render(card)
    }

    func testRendersWithPrice() {
        let card = SavedIdeaCard(saved: makeSaved(priceCents: 4500), onOpen: {}, onRemove: {})
        render(card)
    }

    func testRendersWithoutDescription() {
        let card = SavedIdeaCard(saved: makeSaved(description: nil), onOpen: {}, onRemove: {})
        render(card)
    }

    /// Tag, "We did this" and bookmark on one footer row.
    func testRendersDoableCardWithMarkDoneAction() {
        let card = SavedIdeaCard(
            saved: makeSaved(type: "date", title: "Sunset Picnic in the Park", isIdea: true),
            onOpen: {},
            onRemove: {},
            onMarkDone: {}
        )
        render(card)
    }

    func testRendersMomentWithRatingAndNote() {
        let card = SavedIdeaCard(
            saved: makeSaved(
                type: "date",
                isIdea: true,
                completedAt: Date(),
                rating: 5,
                reflectionNote: "We stayed up talking about the soundtrack for an hour."
            ),
            style: .moment,
            onOpen: {},
            onRemove: {}
        )
        render(card)
    }

    /// At accessibility text sizes the footer no longer fits on one line, so
    /// "We did this" drops to a full-width row under the tag and bookmark.
    func testRendersDoableCardAtAccessibilityTextSize() {
        let card = SavedIdeaCard(
            saved: makeSaved(type: "date", title: "Sunset Picnic in the Park", isIdea: true),
            onOpen: {},
            onRemove: {},
            onMarkDone: {}
        )
        .environment(\.dynamicTypeSize, .accessibility5)
        render(card)
    }

    /// The reflection sheet makes the note optional.
    func testRendersMomentWithoutNote() {
        let card = SavedIdeaCard(
            saved: makeSaved(type: "date", isIdea: true, completedAt: Date(), rating: 3),
            style: .moment,
            onOpen: {},
            onRemove: {}
        )
        render(card)
    }

    func testRendersEveryRecommendationType() {
        for type in ["gift", "experience", "date", "idea", "plan", "unknown"] {
            let card = SavedIdeaCard(saved: makeSaved(type: type), onOpen: {}, onRemove: {})
            render(card)
        }
    }
}

// MARK: - Header Copy

@MainActor
final class SavedViewHeaderTextTests: XCTestCase {

    func testSavedCountText() {
        XCTAssertEqual(SavedView.savedCountText(1), "1 saved")
        XCTAssertEqual(SavedView.savedCountText(3), "3 saved")
    }

    func testMomentsCountText() {
        XCTAssertEqual(SavedView.momentsCountText(1), "1 made real")
        XCTAssertEqual(SavedView.momentsCountText(4), "4 made real")
    }

    func testSavedAccessibilityLabel() {
        XCTAssertEqual(SavedView.savedAccessibilityLabel(count: 0), "Saved ideas, none yet")
        XCTAssertEqual(SavedView.savedAccessibilityLabel(count: 1), "Saved ideas, 1 saved")
        XCTAssertEqual(SavedView.savedAccessibilityLabel(count: 2), "Saved ideas, 2 saved")
    }

    func testMomentsAccessibilityLabel() {
        XCTAssertEqual(SavedView.momentsAccessibilityLabel(count: 0), "Moments, none yet")
        XCTAssertEqual(SavedView.momentsAccessibilityLabel(count: 1), "Moments, 1 made real")
        XCTAssertEqual(SavedView.momentsAccessibilityLabel(count: 5), "Moments, 5 made real")
    }
}

// MARK: - Empty State

@MainActor
final class SavedViewEmptyStateTests: XCTestCase {

    func testEmptyCardShowsWhenNothingIsSaved() {
        XCTAssertTrue(SavedView.showsEmptyCard(activeCount: 0, momentCount: 0))
    }

    /// Once every idea has been done, "No saved items" would sit directly
    /// above the Moments that hold them, so the header stands alone.
    func testEmptyCardHiddenWhenEverythingIsDone() {
        XCTAssertFalse(SavedView.showsEmptyCard(activeCount: 0, momentCount: 1))
        XCTAssertFalse(SavedView.showsEmptyCard(activeCount: 0, momentCount: 4))
    }

    func testEmptyCardHiddenWhileIdeasRemain() {
        XCTAssertFalse(SavedView.showsEmptyCard(activeCount: 1, momentCount: 0))
        XCTAssertFalse(SavedView.showsEmptyCard(activeCount: 2, momentCount: 3))
    }
}

// MARK: - Screen Rendering

@MainActor
final class SavedViewDesignRenderingTests: XCTestCase {

    /// Every container these tests create, kept for the life of the test
    /// process. `render` normally lets `SavedView`'s `.task` load inside the
    /// test, but a task SwiftUI has already queued still runs if it misses
    /// that turn, and `container.mainContext` does not keep its container
    /// alive. A late fetch against a released container traps inside
    /// SwiftData, which takes the whole unit-test host down mid-way through
    /// an unrelated test. A few tiny in-memory stores cost nothing to keep.
    private static var retainedContainers: [ModelContainer] = []

    private func host(_ container: ModelContainer) {
        Self.retainedContainers.append(container)
        render(SavedView().modelContainer(container), runningTasks: true)
    }

    /// Nothing saved: the "Saved ideas" header still renders over the empty card.
    func testRendersEmptyLibrary() throws {
        host(try makeContainer())
    }

    func testRendersActiveItemsOnly() throws {
        let container = try makeContainer()
        container.mainContext.insert(makeSaved(id: "a"))
        container.mainContext.insert(makeSaved(id: "b", type: "date", title: "Sunset Picnic", isIdea: true))
        try container.mainContext.save()

        host(container)
    }

    /// Every item done: the "Saved ideas" header stands alone above "Moments".
    func testRendersMomentsOnly() throws {
        let container = try makeContainer()
        container.mainContext.insert(
            makeSaved(id: "m", type: "date", isIdea: true, completedAt: Date(), rating: 4, reflectionNote: "Lovely.")
        )
        try container.mainContext.save()

        host(container)
    }

    func testRendersBothSections() throws {
        let container = try makeContainer()
        container.mainContext.insert(makeSaved(id: "a", priceCents: 14000))
        container.mainContext.insert(
            makeSaved(id: "m", type: "date", isIdea: true, completedAt: Date(), rating: 5)
        )
        try container.mainContext.save()

        host(container)
    }
}
