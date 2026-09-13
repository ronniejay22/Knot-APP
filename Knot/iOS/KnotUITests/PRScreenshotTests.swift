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
        // The change makes the whole Journal milestone card tappable — pressing
        // the artwork, date, or title opens the event's detail screen, not just
        // the footer's "See details" pill.
        //
        // The Journal sits behind an authenticated session and a live milestone
        // fetch, neither of which a cold screenshot launch can reach; the
        // `journal` harness renders it standalone with three seeded cards and
        // mirrors `ForYouView`'s detail cover seam.
        app.launchArguments += ["-uiTestScreenshot", "journal"]
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
        // The first card's title is a plain `Text` inside the card body — NOT
        // the "See details" pill and NOT the recommendation icon. Tapping it is
        // what exercises the new body tap; tapping the pill would only prove
        // the pre-existing button still works.
        let cardTitle = app.staticTexts["Christmas"]
        XCTAssertTrue(
            cardTitle.waitForExistence(timeout: 15),
            "The seeded Christmas card never appeared — the Journal harness did not render"
        )
        cardTitle.tap()

        // The detail screen's "Get more ideas" CTA exists nowhere on the
        // Journal itself, so its appearance proves the body tap opened
        // `MilestoneDetailView` rather than merely being absorbed.
        //
        // Anchored on the button, not the "Saved ideas" header: that header is
        // a merged accessibility element whose label carries the count
        // ("Saved ideas, none yet"), so an exact `staticTexts` match on it is
        // brittle. The CTA is a plain `KnotButton` with a fixed label.
        XCTAssertTrue(
            app.buttons["Get more ideas"].waitForExistence(timeout: 10),
            "Tapping the card body did not open the milestone detail screen"
        )

        // Let the full-screen cover's presentation animation finish so the
        // capture isn't taken mid-slide.
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
