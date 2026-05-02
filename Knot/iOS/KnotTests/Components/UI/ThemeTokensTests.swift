//
//  ThemeTokensTests.swift
//  KnotTests
//

import XCTest
import SwiftUI
@testable import Knot

@MainActor
final class ThemeTokensTests: XCTestCase {

    func testSpacingScaleIsMonotonic() {
        let scale: [CGFloat] = [
            Theme.Spacing.xxs,
            Theme.Spacing.xs,
            Theme.Spacing.sm,
            Theme.Spacing.md,
            Theme.Spacing.lg,
            Theme.Spacing.xl,
            Theme.Spacing.xxl,
            Theme.Spacing.xxxl
        ]
        for (a, b) in zip(scale, scale.dropFirst()) {
            XCTAssertLessThan(a, b, "Spacing scale must be strictly increasing")
        }
    }

    func testRadiusScaleIsMonotonic() {
        let scale: [CGFloat] = [
            Theme.Radius.sm,
            Theme.Radius.md,
            Theme.Radius.lg,
            Theme.Radius.xl
        ]
        for (a, b) in zip(scale, scale.dropFirst()) {
            XCTAssertLessThan(a, b, "Radius scale must be strictly increasing")
        }
        XCTAssertGreaterThan(Theme.Radius.pill, Theme.Radius.xl)
    }

    func testTypographyTokensExist() {
        _ = Theme.Typography.xs
        _ = Theme.Typography.sm
        _ = Theme.Typography.base
        _ = Theme.Typography.body
        _ = Theme.Typography.lg
        _ = Theme.Typography.xl
        _ = Theme.Typography.xxl
        _ = Theme.Typography.display
    }

    func testMotionTokensExist() {
        _ = Theme.Motion.standard
        _ = Theme.Motion.quick
    }
}
