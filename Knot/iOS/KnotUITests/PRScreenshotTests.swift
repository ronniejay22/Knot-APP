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
        // The change restyles the Saved tab as a single "Saved recommendations"
        // list: a large header with an accent "N saved" count under it, over
        // photo cards (title, note, a SAVED tag opposite a bookmark) shared
        // with a Home event's detail screen. The Moments section and its
        // "We did this" action are gone.
        //
        // Saved items live in SwiftData behind an authenticated session, so the
        // `saved` harness renders `SavedView` standalone over an in-memory store
        // seeded with three saved recommendations (photos fall back to the
        // bundled per-type images).
        app.launchArguments += ["-uiTestScreenshot", "saved"]
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
        // The header is a merged accessibility element whose label carries the
        // count ("Saved recommendations, 3 saved"), so match on the label across
        // element types rather than assuming a `staticText`.
        let header = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", "Saved recommendations, 3 saved"))
            .firstMatch
        XCTAssertTrue(
            header.waitForExistence(timeout: 15),
            "The \"Saved recommendations\" header never appeared — the Saved tab did not render the new design"
        )

        // The card keeps its children as separate elements, so the title is a
        // `staticText` of its own.
        XCTAssertTrue(
            app.staticTexts["Cooking Class: Thai Cuisine"].waitForExistence(timeout: 5),
            "The seeded purchasable's card is missing"
        )

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "PR Screenshot"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
