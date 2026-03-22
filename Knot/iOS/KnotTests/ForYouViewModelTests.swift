//
//  ForYouViewModelTests.swift
//  KnotTests
//
//  Created on March 21, 2026.
//  Tests for the ForYouViewModel — timeline milestone loading, urgency levels, date formatting.
//

import XCTest
@testable import Knot

@MainActor
final class ForYouViewModelTests: XCTestCase {

    // MARK: - Urgency Level Tests

    func testCriticalUrgency() {
        let vm = ForYouViewModel()
        XCTAssertEqual(vm.urgencyLevel(for: 0), .critical)
        XCTAssertEqual(vm.urgencyLevel(for: 1), .critical)
        XCTAssertEqual(vm.urgencyLevel(for: 3), .critical)
    }

    func testSoonUrgency() {
        let vm = ForYouViewModel()
        XCTAssertEqual(vm.urgencyLevel(for: 4), .soon)
        XCTAssertEqual(vm.urgencyLevel(for: 7), .soon)
    }

    func testUpcomingUrgency() {
        let vm = ForYouViewModel()
        XCTAssertEqual(vm.urgencyLevel(for: 8), .upcoming)
        XCTAssertEqual(vm.urgencyLevel(for: 14), .upcoming)
    }

    func testPlanningUrgency() {
        let vm = ForYouViewModel()
        XCTAssertEqual(vm.urgencyLevel(for: 15), .planning)
        XCTAssertEqual(vm.urgencyLevel(for: 30), .planning)
    }

    func testDistantUrgency() {
        let vm = ForYouViewModel()
        XCTAssertEqual(vm.urgencyLevel(for: 31), .distant)
        XCTAssertEqual(vm.urgencyLevel(for: 365), .distant)
    }

    // MARK: - Date Formatting Tests

    func testFormattedDateValidInput() {
        let vm = ForYouViewModel()
        let result = vm.formattedDate("2000-03-28")
        XCTAssertEqual(result, "Mar 28")
    }

    func testFormattedDateDecemberDate() {
        let vm = ForYouViewModel()
        let result = vm.formattedDate("2000-12-25")
        XCTAssertEqual(result, "Dec 25")
    }

    func testFormattedDateJanuaryFirst() {
        let vm = ForYouViewModel()
        let result = vm.formattedDate("2000-01-01")
        XCTAssertEqual(result, "Jan 1")
    }

    func testFormattedDateInvalidInput() {
        let vm = ForYouViewModel()
        let result = vm.formattedDate("invalid")
        XCTAssertEqual(result, "invalid")
    }

    // MARK: - Occasion Type Tests

    func testOccasionTypeWithBudgetTier() {
        let vm = ForYouViewModel()
        let milestone = MilestoneItemResponse(
            id: "1", milestoneType: "birthday", milestoneName: "Birthday",
            milestoneDate: "2000-03-28", recurrence: "yearly",
            budgetTier: "major_milestone", daysUntil: 8, createdAt: "2026-01-01"
        )
        XCTAssertEqual(vm.occasionType(for: milestone), "major_milestone")
    }

    func testOccasionTypeWithoutBudgetTier() {
        let vm = ForYouViewModel()
        let milestone = MilestoneItemResponse(
            id: "1", milestoneType: "birthday", milestoneName: "Birthday",
            milestoneDate: "2000-03-28", recurrence: "yearly",
            budgetTier: nil, daysUntil: 8, createdAt: "2026-01-01"
        )
        XCTAssertEqual(vm.occasionType(for: milestone), "major_milestone")
    }

    // MARK: - Initial State Tests

    func testInitialState() {
        let vm = ForYouViewModel()
        XCTAssertTrue(vm.milestones.isEmpty)
        XCTAssertEqual(vm.partnerName, "Your Partner")
        XCTAssertFalse(vm.isLoading)
        XCTAssertNil(vm.errorMessage)
    }

    // MARK: - MilestoneDisplayContext Tests

    func testMilestoneDisplayContextCreation() {
        let ctx = MilestoneDisplayContext(
            name: "Birthday",
            type: "birthday",
            daysUntil: 8,
            partnerName: "Alex",
            occasionType: "major_milestone"
        )
        XCTAssertEqual(ctx.name, "Birthday")
        XCTAssertEqual(ctx.type, "birthday")
        XCTAssertEqual(ctx.daysUntil, 8)
        XCTAssertEqual(ctx.partnerName, "Alex")
        XCTAssertEqual(ctx.occasionType, "major_milestone")
    }

    // MARK: - MilestoneUrgency Equatable Tests

    func testMilestoneUrgencyEquality() {
        XCTAssertEqual(MilestoneUrgency.critical, MilestoneUrgency.critical)
        XCTAssertNotEqual(MilestoneUrgency.critical, MilestoneUrgency.soon)
    }
}
