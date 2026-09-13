//
//  KnotPressableStyleTests.swift
//  KnotTests
//

import XCTest
import SwiftUI
@testable import Knot

@MainActor
final class KnotPressableStyleTests: XCTestCase {

    // MARK: - Rendering

    func testStyledButtonRenders() {
        let button = Button(action: {}) {
            KnotCard { Text("Pressable") }
        }
        .buttonStyle(KnotPressableStyle())
        XCTAssertNotNil(UIHostingController(rootView: button).view)
    }

    /// The style must coexist with inner buttons that pin their own style —
    /// the exact composition `MilestoneCard` ships.
    func testStyledButtonRendersWithNestedButtons() {
        let button = Button(action: {}) {
            KnotCard {
                VStack {
                    Text("Card")
                    KnotButton("Inner", variant: .outline, size: .sm, shape: .pill, action: {})
                    Button(action: {}) { Text("Icon") }.buttonStyle(.plain)
                }
            }
        }
        .buttonStyle(KnotPressableStyle())
        XCTAssertNotNil(UIHostingController(rootView: button).view)
    }

    // MARK: - Press invariants

    /// The pressed treatment is a *settle*, not a collapse: the surface shrinks
    /// and dims, but never so far that it reads as disabled or disappears. These
    /// bounds are what stop a future "tweak" from turning a subtle press into a
    /// jarring one — or, the other way, back into one too faint to notice.
    func testPressedTreatmentIsSubtle() {
        XCTAssertLessThan(KnotPressableStyle.pressedScale, 1)
        XCTAssertGreaterThanOrEqual(KnotPressableStyle.pressedScale, 0.9)
        XCTAssertLessThanOrEqual(KnotPressableStyle.pressedScale, 0.97)

        XCTAssertLessThan(KnotPressableStyle.pressedOpacity, 1)
        XCTAssertGreaterThanOrEqual(KnotPressableStyle.pressedOpacity, 0.8)
        XCTAssertLessThanOrEqual(KnotPressableStyle.pressedOpacity, 0.92)
    }

    // MARK: - Minimum hold

    /// A tap shorter than the hold keeps the pressed look up for the remainder,
    /// so the settle is drawn even when press and release arrive together.
    func testQuickTapReleaseWaitsForTheRestOfTheHold() {
        let hold = Duration.milliseconds(150)
        XCTAssertEqual(
            KnotPressableStyle.releaseDelay(pressedFor: .zero, hold: hold),
            hold
        )
        XCTAssertEqual(
            KnotPressableStyle.releaseDelay(pressedFor: .milliseconds(40), hold: hold),
            .milliseconds(110)
        )
    }

    /// A press that already outlasted the hold releases the moment the finger
    /// lifts — the hold is a floor, never an added lag.
    func testLongPressReleasesImmediately() {
        let hold = Duration.milliseconds(150)
        XCTAssertEqual(KnotPressableStyle.releaseDelay(pressedFor: hold, hold: hold), .zero)
        XCTAssertEqual(
            KnotPressableStyle.releaseDelay(pressedFor: .seconds(2), hold: hold),
            .zero
        )
    }

    /// The default hold is the shared token, and it is short enough that the
    /// deferred navigation built on it (`MilestoneCard.cardTapped(delay:)`)
    /// still reads as immediate — but long enough to survive the frame or two
    /// a quick tap spends pressed.
    func testDefaultHoldIsTheThemeTokenAndFeelsImmediate() {
        XCTAssertEqual(
            KnotPressableStyle.releaseDelay(pressedFor: .zero),
            Theme.Motion.pressHold
        )
        XCTAssertGreaterThanOrEqual(Theme.Motion.pressHold, .milliseconds(100))
        XCTAssertLessThanOrEqual(Theme.Motion.pressHold, .milliseconds(250))
    }

    // MARK: - Animation selection

    /// Press-down and release deliberately run different curves — a fast
    /// ease-out in, a spring out. If they ever collapse to one, the release
    /// loses its "give".
    func testPressAndReleaseUseDifferentCurves() {
        let down = KnotPressableStyle.animation(pressed: true, reduceMotion: false)
        let release = KnotPressableStyle.animation(pressed: false, reduceMotion: false)
        XCTAssertNotEqual(down, release)
        XCTAssertEqual(down, Theme.Motion.pressDown)
        XCTAssertEqual(release, Theme.Motion.pressRelease)
    }

    /// Reduce Motion drops the spring on both halves and runs the standard
    /// quick curve, so nothing bounces for a user who asked for less motion.
    func testReduceMotionUsesQuickCurveInBothDirections() {
        XCTAssertEqual(
            KnotPressableStyle.animation(pressed: true, reduceMotion: true),
            Theme.Motion.quick
        )
        XCTAssertEqual(
            KnotPressableStyle.animation(pressed: false, reduceMotion: true),
            Theme.Motion.quick
        )
    }
}
