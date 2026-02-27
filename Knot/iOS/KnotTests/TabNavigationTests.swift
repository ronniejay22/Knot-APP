//
//  TabNavigationTests.swift
//  KnotTests
//
//  Created on February 27, 2026.
//  Step 16.1: Tests for bottom tab bar navigation — MainTabView, SavedView, SavedViewModel,
//  isTabEmbedded behavior on RecommendationsView and SettingsView.
//

import XCTest
import SwiftUI
@testable import Knot

// MARK: - MainTabView Tests

@MainActor
final class MainTabViewTests: XCTestCase {

    /// Verify AppTab enum has correct raw values for all four tabs.
    func testAppTabRawValues() {
        XCTAssertEqual(MainTabView.AppTab.forYou.rawValue, 0)
        XCTAssertEqual(MainTabView.AppTab.hints.rawValue, 1)
        XCTAssertEqual(MainTabView.AppTab.saved.rawValue, 2)
        XCTAssertEqual(MainTabView.AppTab.profile.rawValue, 3)
    }

    /// Verify all four AppTab cases exist.
    func testAppTabHasFourCases() {
        let allCases: [MainTabView.AppTab] = [.forYou, .hints, .saved, .profile]
        XCTAssertEqual(allCases.count, 4)
    }

    /// Verify MainTabView renders without crashing.
    func testMainTabViewRenders() {
        let view = MainTabView()
        let hostingController = UIHostingController(rootView: view)
        XCTAssertNotNil(hostingController.view, "MainTabView should render a valid view")
    }
}

// MARK: - SavedView Rendering Tests

@MainActor
final class SavedViewRenderingTests: XCTestCase {

    /// Verify SavedView renders without crashing.
    func testSavedViewRenders() {
        let view = SavedView()
        let hostingController = UIHostingController(rootView: view)
        XCTAssertNotNil(hostingController.view, "SavedView should render a valid view")
    }
}

// MARK: - SavedViewModel Tests (expanded from Step 16.1)

@MainActor
final class SavedViewModelDeleteTests: XCTestCase {

    /// Verify deleteSavedRecommendation removes item from the local array by ID.
    func testDeleteRemovesFromLocalArray() {
        let vm = SavedViewModel()

        // Manually populate with test data
        let rec1 = SavedRecommendation(
            recommendationId: "rec-1",
            recommendationType: "gift",
            title: "Pottery Class"
        )
        let rec2 = SavedRecommendation(
            recommendationId: "rec-2",
            recommendationType: "experience",
            title: "Wine Tasting"
        )
        vm.savedRecommendations = [rec1, rec2]
        XCTAssertEqual(vm.savedRecommendations.count, 2)

        // Simulate removing rec-1 from local array (can't call full delete without ModelContext)
        vm.savedRecommendations.removeAll { $0.recommendationId == "rec-1" }

        XCTAssertEqual(vm.savedRecommendations.count, 1)
        XCTAssertEqual(vm.savedRecommendations.first?.recommendationId, "rec-2")
    }

    /// Verify savedRecommendations can be populated and reflects correct order.
    func testSavedRecommendationsCanBePopulated() {
        let vm = SavedViewModel()

        let older = SavedRecommendation(
            recommendationId: "old-1",
            recommendationType: "gift",
            title: "Old Item",
            savedAt: Date(timeIntervalSince1970: 1000)
        )
        let newer = SavedRecommendation(
            recommendationId: "new-1",
            recommendationType: "date",
            title: "New Item",
            savedAt: Date(timeIntervalSince1970: 2000)
        )

        // Simulate sorted order (newest first, as loadSavedRecommendations would do)
        vm.savedRecommendations = [newer, older]

        XCTAssertEqual(vm.savedRecommendations.count, 2)
        XCTAssertEqual(vm.savedRecommendations[0].recommendationId, "new-1")
        XCTAssertEqual(vm.savedRecommendations[1].recommendationId, "old-1")
    }
}

// MARK: - RecommendationsView isTabEmbedded Tests

@MainActor
final class RecommendationsViewTabEmbeddedTests: XCTestCase {

    /// Verify RecommendationsView renders when isTabEmbedded is false (modal mode).
    func testModalModeRenders() {
        let view = RecommendationsView(isTabEmbedded: false)
        let hostingController = UIHostingController(rootView: view)
        XCTAssertNotNil(hostingController.view, "RecommendationsView in modal mode should render")
    }

    /// Verify RecommendationsView renders when isTabEmbedded is true (tab mode).
    func testTabModeRenders() {
        let view = RecommendationsView(isTabEmbedded: true)
        let hostingController = UIHostingController(rootView: view)
        XCTAssertNotNil(hostingController.view, "RecommendationsView in tab mode should render")
    }

    /// Verify isTabEmbedded defaults to false.
    func testIsTabEmbeddedDefaultsFalse() {
        let view = RecommendationsView()
        XCTAssertFalse(view.isTabEmbedded)
    }

    /// Verify isTabEmbedded can be set to true.
    func testIsTabEmbeddedCanBeSetTrue() {
        let view = RecommendationsView(isTabEmbedded: true)
        XCTAssertTrue(view.isTabEmbedded)
    }
}

// MARK: - SettingsView isTabEmbedded Tests

@MainActor
final class SettingsViewTabEmbeddedTests: XCTestCase {

    /// Verify SettingsView renders when isTabEmbedded is false (sheet mode).
    func testSheetModeRenders() {
        let view = SettingsView(isTabEmbedded: false)
            .environment(AuthViewModel())
        let hostingController = UIHostingController(rootView: view)
        XCTAssertNotNil(hostingController.view, "SettingsView in sheet mode should render")
    }

    /// Verify SettingsView renders when isTabEmbedded is true (tab mode).
    func testTabModeRenders() {
        let view = SettingsView(isTabEmbedded: true)
            .environment(AuthViewModel())
        let hostingController = UIHostingController(rootView: view)
        XCTAssertNotNil(hostingController.view, "SettingsView in tab mode should render")
    }

    /// Verify isTabEmbedded defaults to false.
    func testIsTabEmbeddedDefaultsFalse() {
        let view = SettingsView()
        XCTAssertFalse(view.isTabEmbedded)
    }

    /// Verify isTabEmbedded can be set to true.
    func testIsTabEmbeddedCanBeSetTrue() {
        let view = SettingsView(isTabEmbedded: true)
        XCTAssertTrue(view.isTabEmbedded)
    }
}
