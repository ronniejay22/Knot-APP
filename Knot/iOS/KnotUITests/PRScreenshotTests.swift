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
        // The change restyles the Saved tab as "Saved ideas": a large header
        // with an accent "N saved" count over photo cards (title, note, a
        // SAVED tag opposite a bookmark), shared with a Journal event's detail
        // screen. Date plans carry a "We did this" pill in the card footer.
        //
        // Saved items live in SwiftData behind an authenticated session, so the
        // `savedMoments` harness renders `SavedView` standalone over an
        // in-memory store seeded with a purchasable, a doable date plan and a
        // completed moment (photos fall back to the bundled per-type images).
        app.launchArguments += ["-uiTestScreenshot", "savedMoments"]
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
        // The section header is a merged accessibility element whose label
        // carries the count ("Saved ideas, 2 saved" — the moment is counted
        // separately), so match on the label across element types rather than
        // assuming a `staticText`.
        let sectionHeader = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", "Saved ideas, 2 saved"))
            .firstMatch
        XCTAssertTrue(
            sectionHeader.waitForExistence(timeout: 15),
            "The \"Saved ideas\" header never appeared — the Saved tab did not render the new design"
        )

        // The card keeps its children as separate elements, so the title is a
        // `staticText` of its own.
        XCTAssertTrue(
            app.staticTexts["Sunset Picnic in the Park"].waitForExistence(timeout: 5),
            "The seeded date plan's card is missing"
        )

        // The date plan is doable, so its footer carries the "We did this" pill.
        XCTAssertTrue(
            app.buttons["Mark Sunset Picnic in the Park as done"].waitForExistence(timeout: 5),
            "The date plan's card is missing its \"We did this\" footer action"
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
