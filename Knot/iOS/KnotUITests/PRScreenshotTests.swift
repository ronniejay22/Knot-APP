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
        // The change pairs each loading illustration 1:1 with its emphasis
        // phrase, so a phrase always arrives with its own picture. Previously
        // nine illustrations rotated against four phrases and the pairing
        // drifted.
        //
        // Reaching the screen for real means a live session, a vault, and
        // waiting out a ~25-second pipeline run, none of which a cold
        // screenshot launch can do; the `recsLoading` harness renders it
        // standalone. It needs no seeding — the screen takes no arguments and
        // drives itself.
        app.launchArguments += ["-uiTestScreenshot", "recsLoading"]
        app.launch()

        _ = app.wait(for: .runningForeground, timeout: 10)

        // Let the screen settle before any accessibility query — every miss
        // costs a full hierarchy snapshot for XCTest's failure triage, and a
        // burst of them has crashed the runner before (Step 19.31).
        Thread.sleep(forTimeInterval: 2.0)
        dismissSystemAlerts()

        // ASSERT every wait. A discarded wait lets a screenshot of an entirely
        // different screen ship green — that is exactly how a wrong image
        // shipped in Step 19.31.
        //
        // The headline is the one element unique to this screen, so it is what
        // proves the harness landed here and not on some other surface.
        XCTAssertTrue(
            app.staticTexts["Finding ways to make them smile"].waitForExistence(timeout: 15),
            "The loading headline never appeared — the loading screen did not render"
        )

        // Wait past the first illustration swap (2.5s) so the capture lands on
        // a settled crossfade rather than on frame one, and far enough into the
        // 28s progress ramp that the bar and the match counter have both moved.
        //
        // WHICH step it lands on is not controllable from here. The rotation
        // clock starts when the screen appears, and how long the app takes to
        // get there varies by several seconds run to run — an earlier version
        // of this comment claimed a specific step and was wrong on the very
        // first capture. So the image shows *a* paired scene, not a chosen one.
        //
        // That is fine, because the image is not what proves the pairing:
        // `RecommendationsLoadingHelperTests.testEachPhraseAlwaysArrivesWithTheSameIllustration`
        // is. Introspection-free SwiftUI tests cannot assert on rendered
        // output, so the screenshot's job here is the usual one — showing a
        // reviewer that the screen still renders correctly, with the phrase and
        // the illustration on it belonging together.
        Thread.sleep(forTimeInterval: 4.0)

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
