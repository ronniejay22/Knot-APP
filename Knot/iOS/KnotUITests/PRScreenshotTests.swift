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
        // The change is a typography swap — Fraunces is gone and every heading
        // token now resolves to a DM Sans cut. Login is the screen to capture:
        // its "Create Account" title is `sectionHeader`, the most-used of the
        // three tokens backed by `DMSans-Light.ttf` — the one face here that
        // was hand-instanced from the variable font rather than shipped by
        // Google, so it is the one needing proof it *renders* and not merely
        // registers (the other four cuts already shipped on main).
        //
        // Sign-in shows two Light tokens and was tried first, but it runs
        // `PhotoGridSection`'s continuously-redrawing 40-tile grid, which kept
        // the app busy enough for the test runner to kill it at teardown.
        app.launchArguments += ["-uiTestScreenshot", "login"]
        app.launch()

        // Give the view a moment to render (fonts, gradient, async layout).
        _ = app.wait(for: .runningForeground, timeout: 10)

        // Dismiss any transient SpringBoard system alert (e.g. the simulator's
        // "Apple Account Verification" iCloud prompt) so it doesn't cover the shot.
        dismissSystemAlerts()

        // Wait on the title — the `sectionHeader` (DMSans-Light 28) evidence.
        //
        // Asserted rather than discarded: a discarded wait lets the test pass
        // on whatever screen happens to be up, which is how an earlier run that
        // landed on For You behind a system alert still reported success and
        // produced a screenshot showing none of the change.
        XCTAssertTrue(
            app.staticTexts["Create Account"].waitForExistence(timeout: 15),
            "Login title never appeared — the screenshot would not show the change"
        )

        // Let the screen settle so the shot isn't caught mid-transition.
        Thread.sleep(forTimeInterval: 1.0)

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
