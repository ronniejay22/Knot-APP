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
        // This change touches the recommendation detail CTA: when the link is only a
        // search fallback, the button now reads "Find it online" instead of
        // "Open in <merchant>". The detail screen requires auth + a live backend to
        // reach normally, so launch straight into it via the DEBUG screenshot harness
        // (KnotApp.rootView) with a search-fallback item.
        app.launchArguments += ["recDetailSearchFallback"]
        app.launch()

        // Give the view a moment to render (fonts, gradient, async layout).
        _ = app.wait(for: .runningForeground, timeout: 10)

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "PR Screenshot"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
