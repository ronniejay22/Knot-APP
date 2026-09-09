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
        // Step 19.47 restyles the recommendation detail page into the "experience"
        // layout: a category pill above the title, a one-line meta row, a
        // three-column stats strip, and the About / Where content in white cards.
        // The `recDetail` harness renders it standalone for a bookable sample
        // (the page normally sits behind auth + a live backend).
        app.launchArguments += ["-uiTestScreenshot", "recDetail"]
        app.launch()

        _ = app.wait(for: .runningForeground, timeout: 10)

        // Let the screen settle before any accessibility query — every miss
        // costs a full hierarchy snapshot.
        Thread.sleep(forTimeInterval: 1.0)
        dismissSystemAlerts()

        // ASSERT the target rendered (see Step 19.31 — a discarded wait lets a
        // wrong screenshot ship green). The title proves the detail page; the
        // strip caption proves the new layout.
        XCTAssertTrue(
            app.staticTexts["Sunset Dinner & Live Jazz at The Fonda Theatre"].waitForExistence(timeout: 15),
            "Recommendation detail title never rendered — the shot would not show the detail page"
        )
        XCTAssertTrue(
            app.staticTexts["Profile matches"].waitForExistence(timeout: 5),
            "Stats strip never rendered — the shot would not show the Step 19.47 layout"
        )

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "PR Screenshot"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Tap the dismissive button on any SpringBoard system alert covering the app.
    ///
    /// Checks **once** whether an alert exists, then looks for a dismissive
    /// button *inside it*. Nothing here polls.
    ///
    /// The previous version waited 2s on each of six labels against
    /// SpringBoard, unconditionally. With no alert present — the common case —
    /// every miss cost a wait plus a full accessibility-hierarchy snapshot for
    /// XCTest's failure triage, and that burst was enough to crash the test
    /// runner mid-test. A single non-retrying `exists` is all this needs: the
    /// caller has already let the screen settle, so an alert that is going to
    /// appear has appeared.
    ///
    /// "Don't Allow" is in the list because the push-permission prompt is the
    /// alert most likely to cover a harness screen, and its buttons match none
    /// of the labels this helper originally knew about.
    private func dismissSystemAlerts() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let alert = springboard.alerts.firstMatch
        guard alert.exists else { return }

        for label in ["Not Now", "Don't Allow", "Cancel", "Dismiss", "Later", "OK"] {
            let button = alert.buttons[label]
            if button.exists {
                button.tap()
                return
            }
        }
    }
}
