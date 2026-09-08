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
        // The change is to the app icon as it appears on a **notification
        // banner** — the home screen rendered the icon correctly while every
        // banner showed the generic placeholder, so a home-screen shot proves
        // nothing here. The `notificationBanner` harness requests notification
        // permission, then schedules the real "Still working on it…" local
        // notification when the app is backgrounded, as production does. This
        // test accepts the prompt, presses Home so SpringBoard draws the banner
        // exactly as a user sees it, waits for it, and screenshots the whole
        // screen (the app is in the background, so `app.screenshot()` would
        // miss it).
        app.launchArguments += ["-uiTestScreenshot", "notificationBanner"]
        app.launch()

        _ = app.wait(for: .runningForeground, timeout: 10)

        // Let the harness draw and fire its permission request before any
        // accessibility query — every miss costs a full hierarchy snapshot.
        Thread.sleep(forTimeInterval: 2.0)

        // Accept the permission prompt. Deliberately NOT `dismissSystemAlerts()`
        // unconditionally: that helper taps "Don't Allow", which would deny the
        // very permission this shot depends on. But an unrelated SpringBoard
        // alert (the simulator's iCloud prompt) would otherwise BE
        // `alerts.firstMatch`, so the prompt is never found and that alert also
        // lands in the screenshot — so dismiss a non-permission alert first,
        // then look again. When permission is already granted no prompt appears
        // at all, which is fine; the gate is the ready-status wait below.
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        if !acceptNotificationPrompt(on: springboard) {
            dismissSystemAlerts()
            _ = acceptNotificationPrompt(on: springboard)
        }

        // ASSERT the harness is armed before backgrounding. The harness
        // schedules the notification *from* the background transition, so
        // pressing Home while the permission prompt is still up would arm
        // nothing and the banner assertion below would then blame the wrong
        // thing. This is also what proves permission was granted.
        XCTAssertTrue(
            app.staticTexts
                .matching(NSPredicate(format: "label BEGINSWITH %@", "Ready"))
                .firstMatch
                .waitForExistence(timeout: 15),
            "Harness never became ready — notification permission was denied, so the shot cannot show the notification icon"
        )

        // Background the app. This is both what makes SpringBoard (not the
        // app's own foreground presenter) draw the banner, and what triggers
        // the harness to schedule it — the same order as production, where the
        // notification is scheduled by the backgrounding that starts the
        // background task.
        XCUIDevice.shared.press(.home)

        // ASSERT the banner appeared (see Step 19.31 — a discarded wait lets a
        // wrong screenshot ship green).
        let banner = springboard.staticTexts
            .matching(NSPredicate(format: "label CONTAINS %@", "Still working on it"))
            .firstMatch
        XCTAssertTrue(
            banner.waitForExistence(timeout: 20),
            "No \"Still working on it…\" banner appeared on SpringBoard — the shot cannot show the notification icon. On a real device, check that Focus / Do Not Disturb is off; it suppresses the banner entirely."
        )

        // Let the banner's entrance animation finish.
        Thread.sleep(forTimeInterval: 1.0)

        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "PR Screenshot"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Tap "Allow" if the frontmost SpringBoard alert is the notification
    /// permission prompt. Returns whether it did.
    ///
    /// A single non-retrying `exists`, not a timed wait: the caller has already
    /// let the screen settle, and a timed wait here would burn the harness's
    /// fire delay in the common case where permission is already granted and no
    /// prompt is coming.
    private func acceptNotificationPrompt(on springboard: XCUIApplication) -> Bool {
        let allow = springboard.alerts.firstMatch.buttons["Allow"]
        guard allow.exists else { return false }
        allow.tap()
        return true
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
