//
//  OnboardingStepHeaderTests.swift
//  KnotTests
//
//  Covers the shared left-aligned onboarding step header (title + optional
//  subtitle) that replaced the per-screen centered header blocks. Smoke-tests
//  that it renders both with and without a subtitle.
//

import XCTest
import SwiftUI
@testable import Knot

@MainActor
final class OnboardingStepHeaderTests: XCTestCase {

    /// The header renders with both a title and a subtitle.
    func testRendersWithTitleAndSubtitle() {
        let host = UIHostingController(
            rootView: OnboardingStepHeader(
                title: "How does Ronnie feel most loved?",
                subtitle: "Pick their primary love language."
            )
        )
        XCTAssertNotNil(host.view, "OnboardingStepHeader should render with a subtitle")
    }

    /// The header renders with only a title (subtitle omitted).
    func testRendersWithTitleOnly() {
        let host = UIHostingController(
            rootView: OnboardingStepHeader(title: "Do you live together?")
        )
        XCTAssertNotNil(host.view, "OnboardingStepHeader should render without a subtitle")
    }
}
