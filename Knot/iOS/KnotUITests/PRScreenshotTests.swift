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
        // The change repoints the Terms of Service and Privacy Policy links at
        // the Google Drive PDFs. Two of the four call sites are the About rows
        // in Settings (the other two are the paywall fine print, which opens
        // the same two URLs). Settings sits behind an authenticated session, so
        // render it standalone via the DEBUG harness added in Step 19.12.
        app.launchArguments += ["-uiTestScreenshot", "settings"]
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

        // Wait on a row that proves Settings rendered, then scroll the two
        // changed rows into view.
        //
        // These ASSERT rather than discard their result. A discarded
        // `waitForExistence` lets the test pass while the target screen never
        // appeared — and `app.screenshot()` then captures whatever is on
        // screen (a stale snapshot, a system alert), so a wrong image ships
        // with a green test. Failing here is the only thing that makes the
        // captured screenshot trustworthy.
        XCTAssertTrue(
            app.buttons["Sign Out"].waitForExistence(timeout: 10),
            "Settings harness never rendered — the captured screenshot would not show the change"
        )

        // Scroll the About section into view. Drive this on `isHittable`, not
        // `exists`: a row still scrolled off-screen inside a ScrollView reports
        // `exists == true`, so an `exists` loop exits immediately and the shot
        // captures the top of the list.
        //
        // About is NOT the bottom of the scroll view — the DEBUG-only Developer
        // section renders below it, and DEBUG is the only configuration this
        // harness exists in. So a momentum `swipeUp()` can carry the rows past
        // the top of the screen, which a purely upward loop can never undo.
        // Hence the second pass: overshoot is recoverable, and only a genuine
        // failure to find the rows reaches the assert.
        let terms = app.buttons["Terms of Service"]
        let privacy = app.buttons["Privacy Policy"]
        var bothVisible: Bool { terms.isHittable && privacy.isHittable }

        var scrolls = 0
        while !bothVisible && scrolls < 8 {
            app.swipeUp()
            scrolls += 1
        }
        // Recover from an overshoot.
        scrolls = 0
        while !bothVisible && scrolls < 4 {
            app.swipeDown()
            scrolls += 1
        }

        XCTAssertTrue(
            bothVisible,
            "About rows never became visible — the shot would not show the changed links"
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
