//
//  RecentPicksUITests.swift
//  KnotUITests
//
//  The Home tab's "Recent picks" reopen path, end to end. Step 19.62 wrote
//  this check into the PR screenshot test's navigation slot, and it went with
//  the slot whenever a later change moved it to another screen. Its own class
//  keeps it out of `capture-ui-screenshot.sh`, which runs only
//  `PRScreenshotTests`, so a Recent-picks failure can't cost an unrelated PR
//  its screenshot either.
//

import XCTest

final class RecentPicksUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Tapping a row pushes `RecommendationsView` seeded with the stored
    /// batch, so its first pick (which exists nowhere on Home itself) must
    /// appear with no generation run. The row is a `Button` labelled with its
    /// full accessibility sentence (timestamps are relative to launch, so the
    /// label is deterministic); feed cards are single merged elements whose
    /// label starts with the title.
    func testRecentPicksRowReopensItsBatch() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTestScreenshot", "journal"]
        app.launch()

        _ = app.wait(for: .runningForeground, timeout: 10)

        // Let the screen settle before any accessibility query — every miss
        // costs a full hierarchy snapshot for XCTest's failure triage, and a
        // burst of them has crashed the runner before (Step 19.31).
        Thread.sleep(forTimeInterval: 2.0)
        dismissSystemAlerts()

        let christmasRow = app.buttons["Christmas, 3 picks, generated 2 days ago, expires in 5 days"]
        XCTAssertTrue(
            christmasRow.waitForExistence(timeout: 15),
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
}
