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

    func testStatusTokensExist() {
        _ = Theme.statusError
        _ = Theme.statusErrorTint
        _ = Theme.statusSuccess
        _ = Theme.statusSuccessTint
        _ = Theme.statusWarning
        _ = Theme.statusWarningTint
        _ = Theme.statusInfo
        _ = Theme.statusInfoTint
    }

    func testShadowScaleIsMonotonic() {
        let radii: [CGFloat] = [
            Theme.Shadow.sm.radius,
            Theme.Shadow.md.radius,
            Theme.Shadow.lg.radius
        ]
        for (a, b) in zip(radii, radii.dropFirst()) {
            XCTAssertLessThan(a, b, "Shadow radius scale must be strictly increasing")
        }
        let yOffsets: [CGFloat] = [
            Theme.Shadow.sm.y,
            Theme.Shadow.md.y,
            Theme.Shadow.lg.y
        ]
        for (a, b) in zip(yOffsets, yOffsets.dropFirst()) {
            XCTAssertLessThanOrEqual(a, b, "Shadow y-offset scale must be non-decreasing")
        }
    }

    func testShadowTokensExist() {
        _ = Theme.Shadow.sm
        _ = Theme.Shadow.md
        _ = Theme.Shadow.lg
        _ = Theme.Shadow.accentGlow
    }

    func testShadowViewExtensionApplies() {
        let view = Color.clear.shadow(Theme.Shadow.md)
        let host = UIHostingController(rootView: view)
        XCTAssertNotNil(host.view)
    }

    func testWeightTokensExist() {
        _ = Theme.Weight.regular
        _ = Theme.Weight.medium
        _ = Theme.Weight.semibold
        _ = Theme.Weight.bold
        _ = Theme.Weight.heavy
    }
}
