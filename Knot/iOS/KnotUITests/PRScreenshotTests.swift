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
        // This change reworks the recommendation detail page: the top-right Share and
        // Save circle buttons are gone (only Back remains over the hero), and the
        // Save-to-Library CTA now runs Save → "Saved" → "Continue". Render a Knot
        // Original via the DEBUG harness (`recDetailSaveCTA`), tap Save, and wait for
        // the CTA to become "Continue" so one shot proves both changes.
        app.launchArguments += ["-uiTestScreenshot", "recDetailSaveCTA"]
        app.launch()

        // Give the view a moment to render (fonts, gradient, async layout).
        _ = app.wait(for: .runningForeground, timeout: 10)

        // Dismiss any transient SpringBoard system alert (e.g. the simulator's
        // "Apple Account Verification" iCloud prompt) so it doesn't cover the shot.
        dismissSystemAlerts()

        // Save, then wait out the ~2s "Saved" confirmation for the "Continue" CTA.
        let saveButton = app.buttons["Save to Library"]
        if saveButton.waitForExistence(timeout: 10) {
            saveButton.tap()
        }
        if app.buttons["Continue"].waitForExistence(timeout: 10) {
            // The accessibility tree flips at the start of the CTA's crossfade, so
            // let the animation settle before capturing or the shot shows "Saved".
            Thread.sleep(forTimeInterval: 1)
        }

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
