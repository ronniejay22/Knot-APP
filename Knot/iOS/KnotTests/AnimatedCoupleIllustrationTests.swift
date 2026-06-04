//
//  AnimatedCoupleIllustrationTests.swift
//  KnotTests
//

import XCTest
import SwiftUI
@testable import Knot

@MainActor
final class AnimatedCoupleIllustrationTests: XCTestCase {

    /// The animated illustration should host without crashing.
    func testIllustrationRenders() throws {
        let host = UIHostingController(rootView: AnimatedCoupleIllustration())
        XCTAssertNotNil(host.view, "AnimatedCoupleIllustration should render without crashing")
    }

    /// The ported animation defines exactly six floating hearts.
    func testHasSixFloatingHearts() {
        XCTAssertEqual(AnimatedCoupleIllustration.heartConfigs.count, 6)
    }

    /// Heart timing matches the prototype: every heart has a positive duration
    /// and a non-negative staggered delay.
    func testHeartTimingIsValid() {
        for config in AnimatedCoupleIllustration.heartConfigs {
            XCTAssertGreaterThan(config.duration, 0, "Heart \(config.id) needs a positive duration")
            XCTAssertGreaterThanOrEqual(config.delay, 0, "Heart \(config.id) delay must be non-negative")
        }
    }
}
