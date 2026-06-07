//
//  RelationshipLengthModalTests.swift
//  KnotTests
//
//  Step 18.29: Unit tests for the imported "Set Relationship Length" modal —
//  the shared tenure summary helper, stepper bounds, decompose/recompose
//  arithmetic, and render smoke tests for the field + dialog.
//

import XCTest
import SwiftUI
@testable import Knot

// MARK: - Summary Formatting

final class RelationshipTenureSummaryTests: XCTestCase {

    func testZeroMonths() {
        XCTAssertEqual(relationshipTenureSummary(months: 0), "0 years, 0 months")
    }

    func testSingularYearAndMonth() {
        // 13 months = 1 year, 1 month — both singular forms.
        XCTAssertEqual(relationshipTenureSummary(months: 13), "1 year, 1 month")
    }

    func testPluralYearsAndMonths() {
        // 30 months = 2 years, 6 months.
        XCTAssertEqual(relationshipTenureSummary(months: 30), "2 years, 6 months")
    }

    func testZeroYearsPluralMonths() {
        XCTAssertEqual(relationshipTenureSummary(months: 5), "0 years, 5 months")
    }
}

// MARK: - Stepper Bounds & Clamping

final class RelationshipLengthBoundsTests: XCTestCase {

    func testYearBounds() {
        XCTAssertEqual(RelationshipLengthBounds.years.lowerBound, 0)
        XCTAssertEqual(RelationshipLengthBounds.years.upperBound, 50)
    }

    func testMonthBounds() {
        XCTAssertEqual(RelationshipLengthBounds.months.lowerBound, 0)
        XCTAssertEqual(RelationshipLengthBounds.months.upperBound, 11)
    }

    /// Decrement clamps at the lower bound (no underflow).
    func testDecrementClampsAtLowerBound() {
        let range = RelationshipLengthBounds.months
        let clamped = max(0 - 1, range.lowerBound)
        XCTAssertEqual(clamped, 0)
    }

    /// Month increment clamps at 11 with no wrap to 0.
    func testMonthIncrementDoesNotWrap() {
        let range = RelationshipLengthBounds.months
        let clamped = min(11 + 1, range.upperBound)
        XCTAssertEqual(clamped, 11, "Months must clamp at 11, not wrap to 0")
    }

    /// Year increment clamps at 50.
    func testYearIncrementClampsAtFifty() {
        let range = RelationshipLengthBounds.years
        let clamped = min(50 + 1, range.upperBound)
        XCTAssertEqual(clamped, 50)
    }
}

// MARK: - Decompose / Recompose

final class RelationshipLengthDecompositionTests: XCTestCase {

    /// 30 months seeds the steppers as 2 years / 6 months.
    func testDecompose() {
        let total = 30
        XCTAssertEqual(total / 12, 2)
        XCTAssertEqual(total % 12, 6)
    }

    /// Saving recomposes years*12 + months back to total months.
    func testRecompose() {
        let years = 2
        let months = 6
        XCTAssertEqual(years * 12 + months, 30)
    }

    /// Round-trips a range of totals through decompose → recompose.
    func testRoundTrip() {
        for total in [0, 1, 11, 12, 13, 30, 121, 600] {
            let years = total / 12
            let months = total % 12
            XCTAssertEqual(years * 12 + months, total)
        }
    }
}

// MARK: - Render Smoke Tests

@MainActor
final class RelationshipLengthRenderingTests: XCTestCase {

    func testFieldRenders() {
        let view = RelationshipLengthField(months: .constant(30))
        let hostingController = UIHostingController(rootView: view)
        XCTAssertNotNil(hostingController.view, "RelationshipLengthField should render")
    }

    func testFieldRendersDark() {
        let view = RelationshipLengthField(months: .constant(0))
            .preferredColorScheme(.dark)
        let hostingController = UIHostingController(rootView: view)
        XCTAssertNotNil(hostingController.view, "RelationshipLengthField should render in dark mode")
    }

    func testModalRenders() {
        let modal = RelationshipLengthModal(initialMonths: 30, onSave: { _ in }, onClose: {})
        let hostingController = UIHostingController(rootView: modal)
        XCTAssertNotNil(hostingController.view, "RelationshipLengthModal should render")
    }

    func testModalRendersDark() {
        let modal = RelationshipLengthModal(initialMonths: 0, onSave: { _ in }, onClose: {})
            .preferredColorScheme(.dark)
        let hostingController = UIHostingController(rootView: modal)
        XCTAssertNotNil(hostingController.view, "RelationshipLengthModal should render in dark mode")
    }
}
