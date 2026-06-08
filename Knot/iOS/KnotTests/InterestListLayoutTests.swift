//
//  InterestListLayoutTests.swift
//  KnotTests
//
//  Covers the vertical-list redesign of the onboarding interests and dislikes
//  screens (grid → single-column `InterestListRow` list). Smoke-tests that both
//  screens and the shared row render, and that selection still drives the
//  per-step min-5 validation.
//

import XCTest
import SwiftUI
@testable import Knot

@MainActor
final class InterestListLayoutTests: XCTestCase {

    // MARK: - Rendering

    /// The interests screen renders without crashing in its new list layout.
    func testInterestsViewRenders() {
        let vm = OnboardingViewModel()
        vm.partnerName = "Alex"
        vm.selectedInterests = ["Travel", "Cooking", "Music"]
        let host = UIHostingController(
            rootView: OnboardingInterestsView().environment(vm)
        )
        XCTAssertNotNil(host.view, "OnboardingInterestsView should render in list layout")
    }

    /// The dislikes screen renders without crashing in its new list layout.
    func testDislikesViewRenders() {
        let vm = OnboardingViewModel()
        vm.partnerName = "Alex"
        vm.selectedInterests = ["Travel", "Cooking", "Music", "Hiking", "Photography"]
        vm.selectedDislikes = ["Gaming", "Cars"]
        let host = UIHostingController(
            rootView: OnboardingDislikesView().environment(vm)
        )
        XCTAssertNotNil(host.view, "OnboardingDislikesView should render in list layout")
    }

    /// The shared row renders in both selected and unselected states.
    func testInterestListRowRenders() {
        let selected = UIHostingController(
            rootView: InterestListRow(title: "Travel", iconName: "airplane", isSelected: true) {}
        )
        let unselected = UIHostingController(
            rootView: InterestListRow(title: "Cooking", iconName: "flame.fill", isSelected: false) {}
        )
        XCTAssertNotNil(selected.view)
        XCTAssertNotNil(unselected.view)
    }

    /// The shared row renders with a subtitle in both selected and unselected states.
    func testInterestListRowRendersWithSubtitle() {
        let selected = UIHostingController(
            rootView: InterestListRow(
                title: "Quiet Luxury",
                iconName: "diamond",
                subtitle: "Elegant & understated",
                isSelected: true
            ) {}
        )
        let unselected = UIHostingController(
            rootView: InterestListRow(
                title: "Outdoorsy",
                iconName: "leaf.fill",
                subtitle: "Nature & fresh air",
                isSelected: false
            ) {}
        )
        XCTAssertNotNil(selected.view)
        XCTAssertNotNil(unselected.view)
    }

    /// The vibes screen renders without crashing in its new list layout.
    func testVibesViewRenders() {
        let vm = OnboardingViewModel()
        vm.partnerName = "Alex"
        vm.selectedVibes = ["quiet_luxury", "romantic"]
        let host = UIHostingController(
            rootView: OnboardingVibesView().environment(vm)
        )
        XCTAssertNotNil(host.view, "OnboardingVibesView should render in list layout")
    }

    // MARK: - Selection still drives validation

    /// Selecting the minimum number of interests lets the interests step proceed.
    func testInterestSelectionDrivesValidation() {
        let vm = OnboardingViewModel()
        vm.partnerName = "Alex"
        vm.currentStep = .interests

        vm.selectedInterests = Set(Constants.interestCategories.prefix(Constants.Validation.minInterests - 1))
        vm.validateCurrentStep()
        XCTAssertFalse(vm.canProceed, "Below the minimum should block proceeding")

        vm.selectedInterests = Set(Constants.interestCategories.prefix(Constants.Validation.minInterests))
        vm.validateCurrentStep()
        XCTAssertTrue(vm.canProceed, "At the minimum should allow proceeding")
    }

    /// Selecting the minimum number of dislikes lets the dislikes step proceed.
    func testDislikeSelectionDrivesValidation() {
        let vm = OnboardingViewModel()
        vm.partnerName = "Alex"
        vm.selectedInterests = Set(Constants.interestCategories.prefix(Constants.Validation.minInterests))
        vm.currentStep = .dislikes

        vm.selectedDislikes = Set(
            Constants.interestCategories
                .dropFirst(Constants.Validation.minInterests)
                .prefix(Constants.Validation.minDislikes)
        )
        vm.validateCurrentStep()
        XCTAssertTrue(vm.canProceed, "At the minimum dislikes the step should allow proceeding")
    }

    /// Selecting at least one vibe lets the vibes step proceed.
    func testVibeSelectionDrivesValidation() {
        let vm = OnboardingViewModel()
        vm.partnerName = "Alex"
        vm.currentStep = .vibes

        vm.selectedVibes = []
        vm.validateCurrentStep()
        XCTAssertFalse(vm.canProceed, "No vibes selected should block proceeding")

        vm.selectedVibes = Set(Constants.vibeOptions.prefix(Constants.Validation.minVibes))
        vm.validateCurrentStep()
        XCTAssertTrue(vm.canProceed, "At the minimum vibes the step should allow proceeding")
    }
}
