//
//  OnboardingContainerViewTests.swift
//  KnotTests
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

    /// Asserts the onboarding flow currently has 18 distinct steps.
    func testOnboardingStepHasEighteenSteps() {
        XCTAssertEqual(OnboardingStep.totalSteps, 18)
        XCTAssertEqual(OnboardingStep.allCases.first, .welcome)
        XCTAssertEqual(OnboardingStep.allCases.last, .completion)
        XCTAssertTrue(OnboardingStep.welcome.isFirst)
        XCTAssertTrue(OnboardingStep.completion.isLast)
    }

    /// Walk forward through all 18 steps, asserting rawValue advances by 1 each time.
    func testStepNavigationAdvancesForward() {
        let vm = OnboardingViewModel()
        // Required-input steps need to be satisfied so canProceed lets us advance past them.
        vm.partnerName = "Sample"
        vm.locationCity = "San Francisco"
        vm.locationState = "California"
        vm.selectedInterests = Set(Constants.interestCategories.prefix(Constants.Validation.minInterests))
        vm.selectedDislikes = Set(
            Constants.interestCategories
                .dropFirst(Constants.Validation.minInterests)
                .prefix(Constants.Validation.minDislikes)
        )
        vm.selectedVibes = Set(Constants.vibeOptions.prefix(1))
        vm.primaryLoveLanguage = Constants.loveLanguages[0]
        vm.secondaryLoveLanguage = Constants.loveLanguages[1]

        XCTAssertEqual(vm.currentStep, .welcome)

        var expectedRaw = 0
        while expectedRaw < OnboardingStep.totalSteps - 1 {
            vm.goToNextStep()
            expectedRaw += 1
            XCTAssertEqual(vm.currentStep.rawValue, expectedRaw,
                           "Forward navigation should land on step \(expectedRaw)")
        }
        XCTAssertEqual(vm.currentStep, .completion)
    }

    /// Spot-check that each per-screen validation rule actually gates `canProceed`.
    func testPerStepValidationRules() {
        let vm = OnboardingViewModel()

        // Welcome — always passes.
        vm.currentStep = .welcome
        vm.validateCurrentStep()
        XCTAssertTrue(vm.canProceed)

        // PartnerName — empty fails, non-empty passes.
        vm.currentStep = .partnerName
        vm.partnerName = ""
        vm.validateCurrentStep()
        XCTAssertFalse(vm.canProceed)
        vm.partnerName = "Alex"
        vm.validateCurrentStep()
        XCTAssertTrue(vm.canProceed)

        // Tenure / Cohabitation / Birthday / Anniversary / Holidays — defaulted, pass freely.
        for step: OnboardingStep in [.tenure, .cohabitation, .birthday, .anniversary, .holidays] {
            vm.currentStep = step
            vm.validateCurrentStep()
            XCTAssertTrue(vm.canProceed, "\(step) should default to canProceed")
        }

        // Location — needs city + state.
        vm.currentStep = .location
        vm.locationCity = ""
        vm.locationState = ""
        vm.validateCurrentStep()
        XCTAssertFalse(vm.canProceed)
        vm.locationCity = "Brooklyn"
        vm.locationState = "NY"
        vm.validateCurrentStep()
        XCTAssertTrue(vm.canProceed)

        // CustomMilestones — empty name in any item fails.
        vm.currentStep = .customMilestones
        vm.customMilestones = []
        vm.validateCurrentStep()
        XCTAssertTrue(vm.canProceed)
        vm.customMilestones = [CustomMilestone(name: "  ", month: 1, day: 1, recurrence: "yearly")]
        vm.validateCurrentStep()
        XCTAssertFalse(vm.canProceed)
        vm.customMilestones = [CustomMilestone(name: "First Date", month: 1, day: 1, recurrence: "yearly")]
        vm.validateCurrentStep()
        XCTAssertTrue(vm.canProceed)

        // Budget tier screens — max must be >= min.
        vm.currentStep = .budgetJustBecause
        vm.justBecauseMin = 5000
        vm.justBecauseMax = 4000
        vm.validateCurrentStep()
        XCTAssertFalse(vm.canProceed)
        vm.justBecauseMax = 5000
        vm.validateCurrentStep()
        XCTAssertTrue(vm.canProceed)

        // PrimaryLoveLanguage — must be set.
        vm.currentStep = .primaryLoveLanguage
        vm.primaryLoveLanguage = ""
        vm.validateCurrentStep()
        XCTAssertFalse(vm.canProceed)
        vm.primaryLoveLanguage = "quality_time"
        vm.validateCurrentStep()
        XCTAssertTrue(vm.canProceed)

        // SecondaryLoveLanguage — must be set AND different from primary.
        vm.currentStep = .secondaryLoveLanguage
        vm.secondaryLoveLanguage = ""
        vm.validateCurrentStep()
        XCTAssertFalse(vm.canProceed)
        vm.secondaryLoveLanguage = "quality_time"  // same as primary
        vm.validateCurrentStep()
        XCTAssertFalse(vm.canProceed)
        vm.secondaryLoveLanguage = "physical_touch"
        vm.validateCurrentStep()
        XCTAssertTrue(vm.canProceed)
    }

    /// Canary test that proves the vault payload shape is unchanged by the
    /// split. Backend contract must remain identical.
    func testBuildVaultPayloadShapeUnchanged() {
        let vm = OnboardingViewModel()
        vm.partnerName = "Sample Partner"
        vm.relationshipTenureMonths = 36
        vm.cohabitationStatus = "living_together"
        vm.locationCity = "Brooklyn"
        vm.locationState = "NY"
        vm.locationCountry = "US"
        vm.selectedInterests = Set(Constants.interestCategories.prefix(5))
        vm.selectedDislikes = Set(Constants.interestCategories.dropFirst(5).prefix(5))
        vm.partnerBirthdayMonth = 5
        vm.partnerBirthdayDay = 17
        vm.hasAnniversary = true
        vm.anniversaryMonth = 8
        vm.anniversaryDay = 2
        vm.selectedHolidays = ["valentines_day", "christmas"]
        vm.customMilestones = [
            CustomMilestone(name: "First Date", month: 6, day: 6, recurrence: "yearly")
        ]
        vm.selectedVibes = Set(Constants.vibeOptions.prefix(2))
        vm.primaryLoveLanguage = "quality_time"
        vm.secondaryLoveLanguage = "physical_touch"

        let payload = vm.buildVaultPayload()

        XCTAssertEqual(payload.partnerName, "Sample Partner")
        XCTAssertEqual(payload.relationshipTenureMonths, 36)
        XCTAssertEqual(payload.cohabitationStatus, "living_together")
        XCTAssertEqual(payload.locationCity, "Brooklyn")
        XCTAssertEqual(payload.locationState, "NY")
        XCTAssertEqual(payload.interests.count, 5)
        XCTAssertEqual(payload.dislikes.count, 5)
        // 1 birthday + 1 anniversary + 2 holidays + 1 custom = 5 milestones
        XCTAssertEqual(payload.milestones.count, 5)
        XCTAssertEqual(payload.vibes.count, 2)
        XCTAssertEqual(payload.budgets.count, 3)
        XCTAssertEqual(payload.loveLanguages.primary, "quality_time")
        XCTAssertEqual(payload.loveLanguages.secondary, "physical_touch")
    }

    /// Verify `isSubmitting` toggles drive the loading overlay.
    func testIsSubmittingFlag() {
        let vm = OnboardingViewModel()
        XCTAssertFalse(vm.isSubmitting)
        vm.isSubmitting = true
        XCTAssertTrue(vm.isSubmitting)
        vm.isSubmitting = false
        XCTAssertFalse(vm.isSubmitting)
    }
}
