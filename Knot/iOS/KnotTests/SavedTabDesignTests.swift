//
//  SavedTabDesignTests.swift
//  KnotTests
//
//  The Saved tab's "Saved recommendations" design — the shared
//  `SavedIdeaCard`'s remove label and render paths, and `SavedView`'s header
//  copy and render states. The event-detail call site of the same card stays
//  covered by `MilestoneDetailRenderingTests`.
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
    isIdea: Bool = false
) -> SavedRecommendation {
    SavedRecommendation(
        recommendationId: id,
        recommendationType: type,
        title: title,
        descriptionText: description,
        priceCents: priceCents,
        isIdea: isIdea
    )
}

/// Puts a view in a window and lays it out so SwiftUI actually evaluates the
/// body — a bare `host.view` may not — then takes the window down again.
///
/// The render tests are smoke tests, like `MilestoneDetailRenderingTests`:
/// each drives one body path, and a path that traps fails the run. The copy
/// those paths show is pinned by the pure statics tested here.
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

// MARK: - Card Label

@MainActor
final class SavedIdeaCardLabelTests: XCTestCase {

    /// The remove control names the list the card sits in: "saved ideas" on
    /// an event's detail screen, and the Saved tab's header on that tab.
    func testRemoveLabelNamesTheList() {
        XCTAssertEqual(
            SavedIdeaCard.removeAccessibilityLabel(title: "Sunset Picnic", listName: "saved ideas"),
            "Remove Sunset Picnic from saved ideas"
        )
        XCTAssertEqual(
            SavedIdeaCard.removeAccessibilityLabel(title: "Sunset Picnic", listName: "saved recommendations"),
            "Remove Sunset Picnic from saved recommendations"
        )
    }

    /// `MilestoneDetailView` passes no list name, so its wording is unchanged.
    func testListNameDefaultsToSavedIdeas() {
        let card = SavedIdeaCard(saved: makeSaved(), onOpen: {}, onRemove: {})
        XCTAssertEqual(card.listName, "saved ideas")
    }
}

// MARK: - Card Rendering

@MainActor
final class SavedIdeaCardRenderingTests: XCTestCase {

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

    func testSavedAccessibilityLabel() {
        XCTAssertEqual(SavedView.savedAccessibilityLabel(count: 0), "Saved recommendations, none yet")
        XCTAssertEqual(SavedView.savedAccessibilityLabel(count: 1), "Saved recommendations, 1 saved")
        XCTAssertEqual(SavedView.savedAccessibilityLabel(count: 2), "Saved recommendations, 2 saved")
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

    private func host(_ container: ModelContainer, viewModel: SavedViewModel = SavedViewModel()) {
        Self.retainedContainers.append(container)
        render(SavedView(viewModel: viewModel).modelContainer(container), runningTasks: true)
    }

    /// Nothing saved: the header still renders, over the "No saved items" card.
    func testRendersEmptyLibrary() throws {
        host(try makeContainer())
    }

    /// The view model loads before the view is hosted, so the first layout
    /// pass already draws the cards instead of depending on `.task` landing
    /// inside `render`'s one run-loop turn.
    func testRendersSavedItems() throws {
        let container = try makeContainer()
        container.mainContext.insert(makeSaved(id: "a", priceCents: 14000))
        container.mainContext.insert(makeSaved(id: "b", type: "date", title: "Sunset Picnic", isIdea: true))
        try container.mainContext.save()

        let viewModel = SavedViewModel()
        let loaded = expectation(description: "load")
        Task {
            await viewModel.loadSavedRecommendations(modelContext: container.mainContext)
            loaded.fulfill()
        }
        wait(for: [loaded], timeout: 5)
        XCTAssertEqual(viewModel.savedRecommendations.count, 2)

        host(container, viewModel: viewModel)
    }
}
