//
//  MilestoneOccasionOptionTests.swift
//  KnotTests
//
//  The occasion catalogue offered in the post-onboarding milestone form.
//

import XCTest
@testable import Knot

final class MilestoneOccasionOptionCatalogueTests: XCTestCase {

    func testHolidaysAndLifeEventsHaveUniqueIDs() {
        let ids = (MilestoneOccasionOption.holidays + MilestoneOccasionOption.lifeEvents)
            .map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count, "Duplicate occasion_category in the catalogue")
    }

    /// Every offered id must be a category the backend recognises, or the
    /// scheduler will fall through to `default` and the modal will lose its
    /// illustration.
    func testEveryOptionIsAKnownOccasionCategory() {
        for option in MilestoneOccasionOption.holidays + MilestoneOccasionOption.lifeEvents {
            XCTAssertTrue(
                OccasionCopy.knownCategories.contains(option.id),
                "\(option.id) is offered in the form but unknown to OccasionCopy"
            )
        }
    }

    /// The stored `milestone_type` has a CHECK constraint on exactly four
    /// values — an option storing anything else would 400 on write.
    func testEveryOptionStoresALegalMilestoneType() {
        let legal: Set<String> = ["birthday", "anniversary", "holiday", "custom"]
        for option in MilestoneOccasionOption.holidays + MilestoneOccasionOption.lifeEvents {
            XCTAssertTrue(legal.contains(option.milestoneType), "\(option.id) → \(option.milestoneType)")
        }
    }

    func testHolidaysThatMoveAreMarkedComputed() {
        let computed = Set(
            MilestoneOccasionOption.holidays.filter(\.hasComputedDate).map(\.id)
        )
        XCTAssertEqual(
            computed,
            [
                "lunar_new_year", "eid", "easter", "mothers_day",
                "fathers_day", "diwali", "thanksgiving", "hanukkah",
            ]
        )
    }

    func testFixedDateHolidaysAreNotMarkedComputed() {
        for id in ["valentines_day", "halloween", "christmas", "new_years"] {
            XCTAssertEqual(MilestoneOccasionOption.option(id: id)?.hasComputedDate, false, id)
        }
    }
}

final class MilestoneOccasionOptionLookupTests: XCTestCase {

    func testOptionsForHolidayReturnsTheHolidayCatalogue() {
        XCTAssertEqual(
            MilestoneOccasionOption.options(for: "holiday").map(\.id),
            MilestoneOccasionOption.holidays.map(\.id)
        )
    }

    func testOptionsForCustomReturnsLifeEvents() {
        XCTAssertEqual(
            MilestoneOccasionOption.options(for: "custom").map(\.id),
            MilestoneOccasionOption.lifeEvents.map(\.id)
        )
    }

    /// Birthday and anniversary are their own category, so the picker hides.
    func testOptionsForImplicitTypesAreEmpty() {
        XCTAssertTrue(MilestoneOccasionOption.options(for: "birthday").isEmpty)
        XCTAssertTrue(MilestoneOccasionOption.options(for: "anniversary").isEmpty)
    }

    func testImplicitCategoryOnlyAppliesToBirthdayAndAnniversary() {
        XCTAssertEqual(MilestoneOccasionOption.implicitCategory(for: "birthday"), "birthday")
        XCTAssertEqual(MilestoneOccasionOption.implicitCategory(for: "anniversary"), "anniversary")
        XCTAssertNil(MilestoneOccasionOption.implicitCategory(for: "holiday"))
        XCTAssertNil(MilestoneOccasionOption.implicitCategory(for: "custom"))
    }

    func testLookupByIDFindsAcrossBothLists() {
        XCTAssertEqual(MilestoneOccasionOption.option(id: "diwali")?.displayName, "Diwali")
        XCTAssertEqual(MilestoneOccasionOption.option(id: "new_home")?.displayName, "New Home")
        XCTAssertNil(MilestoneOccasionOption.option(id: "not_a_category"))
    }
}

final class MilestoneOccasionSelectionPreservationTests: XCTestCase {

    /// A legacy holiday that matched no name resolves to `default`, which isn't
    /// in the holiday list — the picker must still be able to show it.
    func testUnlistedSelectionIsAppendedSoThePickerHasAMatchingTag() {
        let options = MilestoneOccasionOption.options(for: "holiday", including: "default")

        XCTAssertEqual(options.count, MilestoneOccasionOption.holidays.count + 1)
        XCTAssertTrue(options.contains { $0.id == "default" })
    }

    func testListedSelectionIsNotDuplicated() {
        let options = MilestoneOccasionOption.options(for: "holiday", including: "christmas")

        XCTAssertEqual(options.count, MilestoneOccasionOption.holidays.count)
        XCTAssertEqual(options.filter { $0.id == "christmas" }.count, 1)
    }

    func testUnknownSelectionGetsAReadableFallbackLabel() {
        let options = MilestoneOccasionOption.options(for: "holiday", including: "wildcard_key")

        XCTAssertEqual(options.last?.id, "wildcard_key")
        XCTAssertEqual(options.last?.displayName, "Other")
    }

    /// Types with no picker stay empty even when a selection is passed —
    /// otherwise a birthday would sprout a one-item control.
    func testEmptyCatalogueStaysEmpty() {
        XCTAssertTrue(MilestoneOccasionOption.options(for: "birthday", including: "birthday").isEmpty)
    }
}

@MainActor
final class MilestoneFormOccasionStateTests: XCTestCase {

    func testPrepareAddResetsToTheDefaultCategory() {
        let viewModel = MilestonesViewModel()
        viewModel.formOccasionCategory = "christmas"

        viewModel.prepareAdd()

        XCTAssertEqual(viewModel.formOccasionCategory, MilestoneOccasionOption.defaultCategory)
        XCTAssertEqual(viewModel.formType, "custom")
    }

    func testPrepareEditHydratesTheStoredCategory() {
        let viewModel = MilestonesViewModel()
        let milestone = MilestoneItemResponse(
            id: "m-1",
            milestoneType: "holiday",
            milestoneName: "Thanksgiving",
            milestoneDate: "2000-11-26",
            recurrence: "yearly",
            budgetTier: "minor_occasion",
            daysUntil: 40,
            createdAt: "2026-08-01T00:00:00Z",
            occasionCategory: "thanksgiving"
        )

        viewModel.prepareEdit(milestone)

        XCTAssertEqual(viewModel.formOccasionCategory, "thanksgiving")
        XCTAssertEqual(viewModel.formType, "holiday")
    }
}
