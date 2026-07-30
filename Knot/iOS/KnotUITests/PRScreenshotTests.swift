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
        // This change makes the end-of-onboarding paywall entitlement-aware. To
        // actually show what changed, render the paywall in its already-subscribed
        // state via the DEBUG screenshot harness (`onboardingPaywallSubscribed`,
        // backed by a `SubscriptionManager(debugSubscribed:)`): the CTA reads
        // "Continue" and the sub-line reads "You already have Knot Premium." — the
        // state that previously showed a misleading "Start Free Trial" and silently
        // proceeded. (The unchanged fresh-user "Start Free Trial" state is available
        // via the `onboardingPaywall` key.)
        app.launchArguments += ["-uiTestScreenshot", "onboardingPaywallSubscribed"]
        app.launch()

        // Give the view a moment to render (fonts, gradient, async layout).
        _ = app.wait(for: .runningForeground, timeout: 10)

        // Dismiss any transient SpringBoard system alert (e.g. the simulator's
        // "Apple Account Verification" iCloud prompt) so it doesn't cover the shot.
        dismissSystemAlerts()

        // Wait for the entitlement-aware sub-line so the screenshot captures the
        // fully-rendered "Continue" state (present only once the paywall's `.task`
        // has refreshed the forced entitlement).
        _ = app.staticTexts["You already have Knot Premium."].waitForExistence(timeout: 10)

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
