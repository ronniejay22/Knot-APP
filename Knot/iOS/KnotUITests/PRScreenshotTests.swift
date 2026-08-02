//
//  PRScreenshotTests.swift
//  KnotUITests
//
//  Captures a screenshot of the screen affected by a change so the autonomous
//  workflow can attach it to the PR (see Knot/CLAUDE.md and
//  iOS/scripts/capture-ui-screenshot.sh). The attachment MUST be named
//  "PR Screenshot" — the capture script looks it up by that name.
//
//  When a change touches a specific screen, edit the navigation slot below to
//  drive the app there before the screenshot is taken. With no edits this
//  captures the app's first screen, which is still a valid image.
//

import XCTest

final class PRScreenshotTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testCaptureChangedScreen() throws {
        let app = XCUIApplication()

        // >>> NAVIGATE TO THE CHANGED SCREEN HERE <<<
        // Step 19.22 adds two rows to Settings' DEBUG-only Developer section: "Show
        // Paywall (DEV)", which opens the subscription paywall without replaying the
        // whole onboarding flow, and "Reset Premium (DEV)", which explains how to clear
        // persisted StoreKit purchases. Render Settings via the DEBUG harness and scroll
        // to the bottom, where the Developer section lives.
        //
        // Deliberately NOT screenshotting the paywall itself: whether it shows "Start
        // Free Trial" or "Try Again" depends on whether a local StoreKit catalog has
        // been registered on that machine, which is exactly the environment-dependent
        // behaviour this change documents — it would make the shot non-reproducible.
        app.launchArguments += ["-uiTestScreenshot", "settings"]
        app.launch()

        // Give the view a moment to render (fonts, gradient, async layout).
        _ = app.wait(for: .runningForeground, timeout: 10)

        // Dismiss any transient SpringBoard system alert (e.g. the simulator's
        // "Apple Account Verification" iCloud prompt) so it doesn't cover the shot.
        dismissSystemAlerts()

        // Scroll to the Developer section at the bottom of the settings list.
        // `KnotListRow.action` wraps title AND subtitle in one Button, so its
        // accessibility label is the two concatenated — match on a substring, not ==.
        let showPaywall = app.buttons
            .matching(NSPredicate(format: "label CONTAINS[c] 'Show Paywall'"))
            .firstMatch
        XCTAssertTrue(
            showPaywall.waitForExistence(timeout: 10),
            "Developer section is missing the Show Paywall (DEV) row"
        )
        // `exists` is true for elements still scrolled off-screen, so drive on
        // `isHittable` — otherwise the shot captures the top of the list.
        for _ in 0..<8 where !showPaywall.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(showPaywall.isHittable, "could not scroll the Developer section into view")
        // Let the scroll settle so the shot isn't captured mid-deceleration.
        Thread.sleep(forTimeInterval: 1)

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "PR Screenshot"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Tap the dismissive button on any SpringBoard system alert covering the app.
    private func dismissSystemAlerts() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for label in ["Not Now", "Cancel", "Dismiss", "Later", "OK"] {
            let button = springboard.buttons[label]
            if button.waitForExistence(timeout: 2) {
                button.tap()
                return
            }
        }
    }
}
