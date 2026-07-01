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
        // The onboarding flow lives behind a Supabase session, so the DEBUG-only
        // `-uiTestOnboarding` launch argument (see KnotApp.rootView) boots straight
        // into it. From the Welcome step, "Get Started" advances to Partner Name —
        // the screen whose field label was removed.
        app.launchArguments += ["-uiTestOnboarding"]
        app.launch()

        let getStarted = app.buttons["Get Started"]
        if getStarted.waitForExistence(timeout: 10) {
            getStarted.tap()
        }
        // Let the step transition settle before capturing.
        _ = app.textFields["Their first name"].waitForExistence(timeout: 5)

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "PR Screenshot"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
