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
        // This change makes the end-of-onboarding paywall entitlement-aware.
        // Render the paywall standalone via the DEBUG screenshot harness
        // (`onboardingPaywall`) — it normally appears only after a full
        // authenticated onboarding run — so the reviewer can see the CTA + trial
        // copy. A fresh (unsubscribed) `SubscriptionManager` shows the standard
        // "Start Free Trial" state; the already-subscribed "Continue" variant
        // needs SKTestSession state the harness can't seed.
        app.launchArguments += ["-uiTestScreenshot", "onboardingPaywall"]
        app.launch()

        // Give the view a moment to render (fonts, gradient, async layout).
        _ = app.wait(for: .runningForeground, timeout: 10)

        // Dismiss any transient SpringBoard system alert (e.g. the simulator's
        // "Apple Account Verification" iCloud prompt) so it doesn't cover the shot.
        dismissSystemAlerts()

        // Wait for a stable paywall element so the screenshot captures the
        // fully-rendered screen. The "Cancel anytime…" note is always present,
        // independent of whether StoreKit products have loaded.
        _ = app.staticTexts["Cancel anytime in your subscription settings."].waitForExistence(timeout: 10)

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
