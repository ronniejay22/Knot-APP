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

    func testBrandPaletteTokensExist() {
        _ = Theme.colorPrimary
        _ = Theme.colorSecondary
        _ = Theme.colorTertiary
    }

    func testOnboardingHeaderTokenExists() {
        _ = Theme.Typography.onboardingHeader
    }

    func testOnboardingSubHeaderTokenExists() {
        _ = Theme.Typography.onboardingSubHeader
    }

    func testBrandPaletteLightModeRGB() {
        let light = UITraitCollection(userInterfaceStyle: .light)
        assertRGB(Theme.colorPrimary, in: light, equals: (0.96, 0.26, 0.40), name: "colorPrimary")
        assertRGB(Theme.colorSecondary, in: light, equals: (1.0, 0.94, 0.88), name: "colorSecondary")
        assertRGB(Theme.colorTertiary, in: light, equals: (0.12, 0.10, 0.16), name: "colorTertiary")
    }

    func testBrandPaletteDarkModeRGB() {
        let dark = UITraitCollection(userInterfaceStyle: .dark)
        assertRGB(Theme.colorPrimary, in: dark, equals: (0.96, 0.26, 0.40), name: "colorPrimary")
        assertRGB(Theme.colorSecondary, in: dark, equals: (0.18, 0.13, 0.12), name: "colorSecondary")
        assertRGB(Theme.colorTertiary, in: dark, equals: (0.95, 0.93, 0.95), name: "colorTertiary")
    }

    private func assertRGB(
        _ color: Color,
        in traits: UITraitCollection,
        equals expected: (CGFloat, CGFloat, CGFloat),
        name: String,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        let resolved = UIColor(color).resolvedColor(with: traits)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        resolved.getRed(&r, green: &g, blue: &b, alpha: &a)
        XCTAssertEqual(r, expected.0, accuracy: 0.005, "\(name) red", file: file, line: line)
        XCTAssertEqual(g, expected.1, accuracy: 0.005, "\(name) green", file: file, line: line)
        XCTAssertEqual(b, expected.2, accuracy: 0.005, "\(name) blue", file: file, line: line)
    }
}
