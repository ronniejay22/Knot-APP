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
        // The change renames the first tab "Journal" → "Home" (eyebrow now
        // "WELCOME HOME") and replaces every icon in the app with MUI glyphs.
        // The capture is the Home tab with the real `KnotTabBar` underneath —
        // Home selected (filled glyph), Saved and Profile outlined — plus the
        // feed's MUI icons (the Recent picks rows, the cards' action buttons).
        //
        // Home sits behind an authenticated session and live backend fetches,
        // neither of which a cold screenshot launch can reach; the `journal`
        // harness renders it standalone with seeded data and mounts the tab
        // bar exactly as `MainTabView` does.
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
        XCTAssertTrue(
            app.staticTexts["WELCOME HOME"].waitForExistence(timeout: 15),
            "The \"WELCOME HOME\" eyebrow never appeared — the Home harness did not render"
        )

        // The tab bar's buttons carry their titles as accessibility labels.
        let homeTab = app.buttons["Home"]
        XCTAssertTrue(homeTab.waitForExistence(timeout: 5), "The Home tab is missing from the tab bar")
        XCTAssertTrue(homeTab.isSelected, "Home should be the selected tab")
        XCTAssertTrue(app.buttons["Saved"].exists, "The Saved tab is missing from the tab bar")
        XCTAssertTrue(app.buttons["Profile"].exists, "The Profile tab is missing from the tab bar")
        XCTAssertFalse(app.buttons["Journal"].exists, "A tab is still labelled \"Journal\"")

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "PR Screenshot"
        attachment.lifetime = .keepAlways
        add(attachment)

        // Kept from Step 19.62 — the only UI coverage of the Recent picks
        // reopen path: tapping a row pushes `RecommendationsView` seeded with
        // the stored batch, so its first pick (which exists nowhere on Home
        // itself) must appear with no generation run. The row is a `Button`
        // labelled with its full accessibility sentence (timestamps are
        // relative to launch, so the label is deterministic); feed cards are
        // single merged elements whose label starts with the title.
        let christmasRow = app.buttons["Christmas, 3 picks, generated 2 days ago, expires in 5 days"]
        XCTAssertTrue(
            christmasRow.waitForExistence(timeout: 5),
            "The seeded Christmas batch row is missing from the Recent picks section"
        )
        christmasRow.tap()
        let reopenedPick = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Candlelit Pottery Class")
        ).firstMatch
        XCTAssertTrue(
            reopenedPick.waitForExistence(timeout: 10),
            "Tapping the Recent picks row did not reopen its cards"
        )
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
    /// of the labels this helper originally knew about. It is listed with both
    /// apostrophes: iOS renders the button as "Don’t Allow" (U+2019), which a
    /// straight-quote label never matches — so the prompt stayed up over the
    /// Home harness and hid every element behind it.
    private func dismissSystemAlerts() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let alert = springboard.alerts.firstMatch
        guard alert.exists else { return }

        for label in ["Not Now", "Don’t Allow", "Don't Allow", "Cancel", "Dismiss", "Later", "OK"] {
            let button = alert.buttons[label]
            if button.exists {
                button.tap()
                return
            }
        }
    }
}
