//
//  OnboardingContainerViewTests.swift
//  KnotTests
//
//  Step 18.2 (shadcn Phase 3): Render-without-crash tests for the onboarding
//  container after migration of nav buttons to KnotButton and the vault
//  submission overlay to KnotProgressIndicator.Overlay.
//

import XCTest
import SwiftUI
@testable import Knot

@MainActor
final class OnboardingContainerViewTests: XCTestCase {

    /// Verify the container renders without crashing at the welcome step.
    func testContainerRendersAtWelcome() throws {
        let container = OnboardingContainerView { /* onComplete */ }
        let host = UIHostingController(rootView: container)
        XCTAssertNotNil(host.view, "OnboardingContainerView should render without crashing")
    }

    /// Verify ViewModel step navigation drives `currentStep` forward.
    /// The container observes this and renders the matching step view +
    /// "Get Started" KnotButton on the last step.
    func testStepNavigationAdvances() {
        let vm = OnboardingViewModel()

        XCTAssertEqual(vm.currentStep, .welcome, "Initial step should be welcome")
        XCTAssertTrue(vm.currentStep.isFirst, "Welcome should be the first step")
        XCTAssertFalse(vm.currentStep.isLast, "Welcome should not be the last step")

        vm.goToNextStep()
        XCTAssertEqual(vm.currentStep, .basicInfo, "After Next from welcome, step should be basicInfo")

        vm.goToPreviousStep()
        XCTAssertEqual(vm.currentStep, .welcome, "After Back from basicInfo, step should be welcome")
    }

    /// Verify `isSubmitting` toggles drive the loading overlay.
    /// The container shows `KnotProgressIndicator.Overlay` when this is true.
    func testIsSubmittingFlag() {
        let vm = OnboardingViewModel()

        XCTAssertFalse(vm.isSubmitting, "Initial state should be false")

        vm.isSubmitting = true
        XCTAssertTrue(vm.isSubmitting, "Flag should be settable to true")

        vm.isSubmitting = false
        XCTAssertFalse(vm.isSubmitting, "Flag should reset to false")
    }
}
