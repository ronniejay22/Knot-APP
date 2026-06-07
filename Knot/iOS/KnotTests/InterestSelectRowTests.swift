//
//  InterestSelectRowTests.swift
//  KnotTests
//
//  Step 18.30: Render smoke tests for the shared `InterestSelectRow` and the
//  list-based Interests / Dislikes onboarding screens that consume it.
//

import XCTest
import SwiftUI
@testable import Knot

// MARK: - Row Render Smoke Tests

@MainActor
final class InterestSelectRowTests: XCTestCase {

    func testRowRendersUnselected() {
        let view = InterestSelectRow(title: "Travel", isSelected: false, iconName: "airplane") {}
        let host = UIHostingController(rootView: view)
        XCTAssertNotNil(host.view, "InterestSelectRow should render when unselected")
    }

    func testRowRendersSelected() {
        let view = InterestSelectRow(title: "Cooking", isSelected: true, iconName: "flame.fill") {}
        let host = UIHostingController(rootView: view)
        XCTAssertNotNil(host.view, "InterestSelectRow should render when selected")
    }

    func testRowRendersDark() {
        let view = InterestSelectRow(title: "Music", isSelected: true, iconName: "music.note") {}
            .preferredColorScheme(.dark)
        let host = UIHostingController(rootView: view)
        XCTAssertNotNil(host.view, "InterestSelectRow should render in dark mode")
    }

    /// Every catalog interest must resolve to a non-empty SF Symbol name so the
    /// row's leading icon never renders blank.
    func testEveryCatalogInterestHasAnIcon() {
        for interest in Constants.interestCategories {
            let symbol = OnboardingInterestsView.iconName(for: interest)
            XCTAssertFalse(symbol.isEmpty, "\(interest) should map to an SF Symbol")
        }
    }
}

// MARK: - Screen Render Smoke Tests

@MainActor
final class InterestSelectionScreenRenderTests: XCTestCase {

    func testInterestsScreenRendersAsList() {
        let vm = OnboardingViewModel()
        vm.partnerName = "Alex"
        vm.selectedInterests = ["Travel", "Cooking", "Music"]
        let view = OnboardingInterestsView().environment(vm)
        let host = UIHostingController(rootView: view)
        XCTAssertNotNil(host.view, "OnboardingInterestsView should render the list layout")
    }

    func testDislikesScreenRendersAsList() {
        let vm = OnboardingViewModel()
        vm.partnerName = "Alex"
        vm.selectedInterests = ["Travel", "Cooking", "Music", "Hiking", "Photography"]
        vm.selectedDislikes = ["Gaming", "Cars"]
        let view = OnboardingDislikesView().environment(vm)
        let host = UIHostingController(rootView: view)
        XCTAssertNotNil(host.view, "OnboardingDislikesView should render the list layout")
    }
}
