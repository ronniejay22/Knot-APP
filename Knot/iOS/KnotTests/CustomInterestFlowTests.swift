//
//  CustomInterestFlowTests.swift
//  KnotTests
//
//  Covers the "add a custom interest/dislike" onboarding flow that runs when
//  the user's search yields no matches. Custom names live alongside the
//  predefined catalog, auto-select on add, and round-trip through the vault
//  payload sent to the backend (migration 00025 dropped the DB allowlist).
//

import XCTest
@testable import Knot

@MainActor
final class CustomInterestFlowTests: XCTestCase {

    // MARK: - addCustomInterest

    func test_addCustomInterest_trimsAndSelects() {
        let vm = OnboardingViewModel()
        let result = vm.addCustomInterest("  Surfing Lessons  ")
        XCTAssertEqual(result, .added("Surfing Lessons"))
        XCTAssertTrue(vm.customInterests.contains("Surfing Lessons"))
        XCTAssertTrue(vm.selectedInterests.contains("Surfing Lessons"))
    }

    func test_addCustomInterest_rejectsEmpty() {
        let vm = OnboardingViewModel()
        XCTAssertEqual(vm.addCustomInterest(""), .empty)
        XCTAssertEqual(vm.addCustomInterest("   \n\t"), .empty)
        XCTAssertTrue(vm.customInterests.isEmpty)
        XCTAssertTrue(vm.selectedInterests.isEmpty)
    }

    func test_addCustomInterest_rejectsTooLong() {
        let vm = OnboardingViewModel()
        let longName = String(repeating: "X", count: OnboardingViewModel.maxCustomInterestLength + 1)
        XCTAssertEqual(vm.addCustomInterest(longName), .tooLong)
        XCTAssertTrue(vm.customInterests.isEmpty)
    }

    func test_addCustomInterest_rejectsPredefinedDuplicate() {
        let vm = OnboardingViewModel()
        XCTAssertEqual(vm.addCustomInterest("travel"), .duplicate)
        XCTAssertEqual(vm.addCustomInterest("TRAVEL"), .duplicate)
        XCTAssertTrue(vm.customInterests.isEmpty)
    }

    func test_addCustomInterest_rejectsCustomDuplicate() {
        let vm = OnboardingViewModel()
        XCTAssertEqual(vm.addCustomInterest("Stargazing"), .added("Stargazing"))
        XCTAssertEqual(vm.addCustomInterest("stargazing"), .duplicate)
        XCTAssertEqual(vm.customInterests.count, 1)
    }

    func test_addCustomInterest_satisfiesMinValidation() {
        let vm = OnboardingViewModel()
        vm.currentStep = .interests
        for name in ["Pottery", "Bird Watching", "Origami", "Mixology"] {
            _ = vm.addCustomInterest(name)
        }
        vm.validateCurrentStep()
        XCTAssertFalse(vm.canProceed, "4 customs shouldn't be enough yet")
        _ = vm.addCustomInterest("Sailing")
        XCTAssertTrue(vm.canProceed, "5 customs should let the user proceed")
    }

    // MARK: - addCustomDislike

    func test_addCustomDislike_trimsAndSelects() {
        let vm = OnboardingViewModel()
        let result = vm.addCustomDislike("Spicy Food")
        XCTAssertEqual(result, .added("Spicy Food"))
        XCTAssertTrue(vm.customDislikes.contains("Spicy Food"))
        XCTAssertTrue(vm.selectedDislikes.contains("Spicy Food"))
    }

    func test_addCustomDislike_rejectsOverlapWithSelectedLikes() {
        let vm = OnboardingViewModel()
        _ = vm.addCustomInterest("Stargazing")
        XCTAssertEqual(vm.addCustomDislike("stargazing"), .overlapsLikes)
        XCTAssertFalse(vm.customDislikes.contains("stargazing"))
        XCTAssertFalse(vm.selectedDislikes.contains("stargazing"))
    }

    func test_addCustomDislike_rejectsPredefinedDuplicate() {
        let vm = OnboardingViewModel()
        XCTAssertEqual(vm.addCustomDislike("gaming"), .duplicate)
    }

    // MARK: - Round-trip into the vault payload

    func test_buildVaultPayload_includesCustomInterestsAndDislikes() {
        let vm = OnboardingViewModel()
        vm.partnerName = "Alex"
        vm.locationCity = "Brooklyn"
        vm.locationState = "NY"
        vm.selectedInterests = Set(Constants.interestCategories.prefix(4))
        vm.selectedDislikes = Set(
            Constants.interestCategories
                .dropFirst(Constants.Validation.minInterests)
                .prefix(4)
        )
        _ = vm.addCustomInterest("Stargazing")
        _ = vm.addCustomDislike("Karaoke Bars")
        // Top up to the minimum from predefined catalog where needed.
        vm.selectedInterests.insert("Photography")
        vm.selectedDislikes.insert("Karaoke")

        let payload = vm.buildVaultPayload()
        XCTAssertTrue(payload.interests.contains("Stargazing"))
        XCTAssertTrue(payload.dislikes.contains("Karaoke Bars"))
        XCTAssertGreaterThanOrEqual(payload.interests.count, 5)
        XCTAssertGreaterThanOrEqual(payload.dislikes.count, 5)
    }
}
