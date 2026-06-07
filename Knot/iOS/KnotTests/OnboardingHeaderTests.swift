//
//  OnboardingHeaderTests.swift
//  KnotTests
//
//  Step 18.30: Render smoke tests for the shared left-aligned onboarding
//  header used across the standard onboarding form steps.
//

import XCTest
import SwiftUI
@testable import Knot

@MainActor
final class OnboardingHeaderTests: XCTestCase {

    func testRendersWithTitleAndSubtitle() {
        let view = OnboardingHeader(
            title: "Do you celebrate an anniversary?",
            subtitle: "Optional — flip the toggle if you want a reminder."
        )
        let hostingController = UIHostingController(rootView: view)
        XCTAssertNotNil(hostingController.view, "OnboardingHeader should render with a title and subtitle")
    }

    func testRendersTitleOnly() {
        // The Cohabitation step uses a title with no subtitle.
        let view = OnboardingHeader(title: "Do you live together?")
        let hostingController = UIHostingController(rootView: view)
        XCTAssertNotNil(hostingController.view, "OnboardingHeader should render with a title only")
    }

    func testRendersDark() {
        let view = OnboardingHeader(
            title: "When is your partner's birthday?",
            subtitle: "We'll remind you so you never forget."
        )
        .preferredColorScheme(.dark)
        let hostingController = UIHostingController(rootView: view)
        XCTAssertNotNil(hostingController.view, "OnboardingHeader should render in dark mode")
    }

    /// The convenience initializer should default the subtitle to nil.
    func testSubtitleDefaultsToNil() {
        let header = OnboardingHeader(title: "Where do you live?")
        XCTAssertNil(header.subtitle, "subtitle should default to nil when omitted")
        XCTAssertEqual(header.title, "Where do you live?")
    }
}
