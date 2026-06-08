//
//  BudgetRangeSliderMathTests.swift
//  KnotTests
//
//  Unit tests for the pure snapping / position math behind BudgetRangeSlider.
//

import XCTest
@testable import Knot

final class BudgetRangeSliderMathTests: XCTestCase {

    // Just Because tier bounds: $5–$200, $5 step.
    private let lower = 500
    private let upper = 20000
    private let step = 500

    // MARK: - snapBudgetCents

    func testSnapClampsBelowFloor() {
        XCTAssertEqual(BudgetSliderMath.snap(300, step: step, lower: lower, upper: upper), 500)
        XCTAssertEqual(BudgetSliderMath.snap(-1000, step: step, lower: lower, upper: upper), 500)
    }

    func testSnapClampsAboveCeiling() {
        XCTAssertEqual(BudgetSliderMath.snap(99_999, step: step, lower: lower, upper: upper), 20000)
        // The unlimited sentinel clamps to the ceiling.
        XCTAssertEqual(
            BudgetSliderMath.snap(BudgetTierConfig.unlimitedMaxCents, step: step, lower: lower, upper: upper),
            20000
        )
    }

    func testSnapRoundsToNearestStep() {
        // 740 is closer to 500 than to 1000 → 500.
        XCTAssertEqual(BudgetSliderMath.snap(740, step: step, lower: lower, upper: upper), 500)
        // 760 is closer to 1000 → 1000.
        XCTAssertEqual(BudgetSliderMath.snap(760, step: step, lower: lower, upper: upper), 1000)
        // Exact midpoint (750) rounds up.
        XCTAssertEqual(BudgetSliderMath.snap(750, step: step, lower: lower, upper: upper), 1000)
        // Already on a step stays put.
        XCTAssertEqual(BudgetSliderMath.snap(10500, step: step, lower: lower, upper: upper), 10500)
    }

    // MARK: - x(forCents:) / cents(forX:)

    func testSentinelPositionsThumbAtCeiling() {
        let trackWidth: CGFloat = 200
        let atCeiling = BudgetSliderMath.x(forCents: upper, trackWidth: trackWidth, lower: lower, upper: upper)
        let atSentinel = BudgetSliderMath.x(
            forCents: BudgetTierConfig.unlimitedMaxCents,
            trackWidth: trackWidth, lower: lower, upper: upper
        )
        XCTAssertEqual(atSentinel, trackWidth, accuracy: 0.001)
        XCTAssertEqual(atSentinel, atCeiling, accuracy: 0.001)
    }

    func testFloorPositionsThumbAtOrigin() {
        XCTAssertEqual(
            BudgetSliderMath.x(forCents: lower, trackWidth: 200, lower: lower, upper: upper),
            0, accuracy: 0.001
        )
    }

    func testPositionCentsRoundTrip() {
        let trackWidth: CGFloat = 200
        let original = 10500  // on a step
        let px = BudgetSliderMath.x(forCents: original, trackWidth: trackWidth, lower: lower, upper: upper)
        let back = BudgetSliderMath.cents(forX: px, trackWidth: trackWidth, lower: lower, upper: upper, step: step)
        XCTAssertEqual(back, original)
    }

    func testCentsForXClampsOutOfRange() {
        XCTAssertEqual(BudgetSliderMath.cents(forX: -50, trackWidth: 200, lower: lower, upper: upper, step: step), lower)
        XCTAssertEqual(BudgetSliderMath.cents(forX: 9999, trackWidth: 200, lower: lower, upper: upper, step: step), upper)
    }
}
