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
        // The change shrinks the headline inside each Journal `MilestoneCard`
        // from 28pt to 20pt. The real `ForYouView` sits behind an authenticated
        // session and a live milestone fetch, which a cold screenshot launch
        // can't reach — so render the same card feed via the DEBUG harness,
        // whose three seeded entries show the retyped headline against the
        // unchanged 32pt partner name and the card's meta/footer labels.
        app.launchArguments += ["-uiTestScreenshot", "journal"]
        app.launch()

        // Give the view a moment to render (fonts, gradient, async layout).
        _ = app.wait(for: .runningForeground, timeout: 10)

        // Let the harness draw before any accessibility query. Every query that
        // misses makes XCTest collect a full accessibility snapshot for failure
        // triage, and a burst of those is expensive enough to destabilise the
        // runner — so it is worth settling first and then asking once.
        Thread.sleep(forTimeInterval: 2.0)

        // Dismiss any transient SpringBoard system alert (e.g. the simulator's
        // "Apple Account Verification" iCloud prompt) so it doesn't cover the shot.
        dismissSystemAlerts()

        // Wait on the header eyebrow and the first card's headline — the
        // element this change retypes.
        //
        // These ASSERT rather than discard their result. A discarded
        // `waitForExistence` lets the test pass while the target screen never
        // appeared — and `app.screenshot()` then captures whatever is on
        // screen (a stale snapshot, a system alert), so a wrong image ships
        // with a green test. Failing here is the only thing that makes the
        // captured screenshot trustworthy.
        XCTAssertTrue(
            app.staticTexts["YOUR JOURNAL"].waitForExistence(timeout: 10),
            "Journal harness never rendered — the captured screenshot would not show the change"
        )
        XCTAssertTrue(
            app.staticTexts["Christmas"].waitForExistence(timeout: 5),
            "The first milestone card's headline never rendered — the shot would not show the retyped title"
        )

        // Let the screen settle so the shot isn't caught mid-transition.
        Thread.sleep(forTimeInterval: 1.0)

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
