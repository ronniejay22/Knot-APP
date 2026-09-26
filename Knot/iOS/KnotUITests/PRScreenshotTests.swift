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
        // The change redesigns the Profile tab: a couple hero card ("You &
        // Jas", "Together 3 yrs · Austin", Edit profile) over grouped cards
        // (Partner, Preferences, Account), quiet Sign out / Delete account
        // buttons, and a Terms · Privacy footer.
        //
        // The partner lives behind an authenticated session and the backend,
        // so the `settings` harness seeds the view model with a fixed partner
        // and mounts the tab bar the way `MainTabView` does.
        app.launchArguments += ["-uiTestScreenshot", "settings"]
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
        // The hero's text column is one accessibility element whose label is
        // the spoken sentence, so an exact match proves the seeded partner went
        // through the name, tenure, and place formatting end to end. Match
        // across element types rather than assuming a `staticText`.
        let hero = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", "You and Jas. Together 3 years, Austin"))
            .firstMatch
        XCTAssertTrue(
            hero.waitForExistence(timeout: 15),
            "The couple hero never appeared — the Profile tab did not render the new design"
        )

        for label in ["Edit profile", "Partner profile", "Milestones", "Sign out"] {
            XCTAssertTrue(
                app.buttons[label].waitForExistence(timeout: 5),
                "The \"\(label)\" button is missing from the Profile tab"
            )
        }

        XCTAssertTrue(
            app.buttons["Profile"].isSelected,
            "The tab bar is missing or Profile isn't the selected tab"
        )

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "PR Screenshot"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
