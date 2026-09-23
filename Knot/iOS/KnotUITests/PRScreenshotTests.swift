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
        // The change adds a "Recent picks" section to the Journal: every set of
        // recommendations generated in the last 7 days, each row reopening its
        // cards until the set expires. The capture is the Journal itself with
        // that section between the header and "Upcoming" — one milestone-named
        // row ("Christmas") and one just-because row inside its last day, so
        // the destructive expiry badge is in the shot too.
        //
        // The Journal sits behind an authenticated session and live backend
        // fetches, neither of which a cold screenshot launch can reach; the
        // `journal` harness renders it standalone with two seeded batches and
        // three seeded cards, inside a `NavigationStack` that mirrors
        // `ForYouView`'s push seam.
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
        // The section header is a merged accessibility element whose label
        // carries the count ("Recent picks, 2 sets"), so match on the label
        // across element types rather than assuming a `staticText`.
        let sectionHeader = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", "Recent picks, 2 sets"))
            .firstMatch
        XCTAssertTrue(
            sectionHeader.waitForExistence(timeout: 15),
            "The \"Recent picks\" header never appeared — the section did not render on the Journal harness"
        )

        // The row is a `Button` whose label is the row's full accessibility
        // sentence, built from the seeded batch (generated 2 days ago, expires
        // in 5 days — both relative to launch, so the label is deterministic).
        let christmasRow = app.buttons["Christmas, 3 picks, generated 2 days ago, expires in 5 days"]
        XCTAssertTrue(
            christmasRow.waitForExistence(timeout: 5),
            "The seeded Christmas batch row is missing from the Recent picks section"
        )

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "PR Screenshot"
        attachment.lifetime = .keepAlways
        add(attachment)

        // Then prove the row actually reopens the set: tapping pushes
        // `RecommendationsView` seeded with the stored batch, so the first
        // pick — which exists nowhere on the Journal itself — must appear,
        // with no generation run.
        //
        // Matched as a `Button` by label prefix, NOT as a `staticText`: since
        // Step 19.59 each feed card is a single merged accessibility element
        // (`RecommendationFeedCard.accessibilityLabel` → "Title, Type. …"), so
        // the title is no longer exposed on its own. The title staying first in
        // that label is exactly what keeps a prefix match working.
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
