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
        // The change adds two screens' worth of UI, so this one test produces
        // two captures, chosen by the `KNOT_PR_SHOT` environment variable
        // (`xcodebuild` forwards `TEST_RUNNER_KNOT_PR_SHOT=…` to the runner):
        //
        //   (default) `journalPicksAlert` — the Journal with the "New picks for
        //   Jas's Birthday" `KnotAlertBanner` between the header and "Surprise
        //   them today", above the real timeline, inside the real `KnotTabBar`.
        //   This is the alert shown when a milestone push was sent but never
        //   tapped.
        //
        //   `sheet` → `recentPicksSheet` — the sheet the banner's "View recent
        //   recommendations" raises: the event's artwork hero, its DATE /
        //   COUNTDOWN / RECIPIENT card, then the stored picks as the feed's
        //   headline + photo cards.
        //
        // Both screens sit behind an authenticated session, a milestone fetch
        // and a notification-history read; the harnesses render the real
        // `ForYouView` / `RecentPicksSheet` with seeded view models whose
        // services are static stubs. The selection of *which* push to announce
        // is a pure function proven by `PendingPicksAlertTests`, not by these
        // still images.
        let wantsSheet = ProcessInfo.processInfo.environment["KNOT_PR_SHOT"] == "sheet"
        app.launchArguments += ["-uiTestScreenshot", wantsSheet ? "recentPicksSheet" : "journalPicksAlert"]
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
        if wantsSheet {
            assertRecentPicksSheet(in: app)
        } else {
            assertJournalPicksAlert(in: app)
        }

        // Let the feed's `.revealIn` and the sheet's presentation settle, so
        // the capture isn't taken mid-animation.
        Thread.sleep(forTimeInterval: 1.0)

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "PR Screenshot"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// The banner is the element this change adds to the Journal. Its title
    /// proves the alert rendered; the body is matched on "3 days ago" (the
    /// harness stamps the push three calendar days old) so the capture proves
    /// the age is computed from the push's timestamp rather than defaulting to
    /// "just now"; the button and ✕ are asserted by label so a renamed or
    /// missing control fails here, not in review. "Upcoming" proves the real
    /// timeline rendered under the banner rather than a bare header.
    private func assertJournalPicksAlert(in app: XCUIApplication) {
        XCTAssertTrue(
            app.staticTexts["New picks for Jas's Birthday"].waitForExistence(timeout: 15),
            "The Journal alert never appeared — the journalPicksAlert harness did not seed pendingPicksAlert, or ForYouView did not render it"
        )
        XCTAssertTrue(
            app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS %@", "3 days ago")
            ).firstMatch.waitForExistence(timeout: 5),
            "The alert body does not say how old the push is — the message is not derived from sentAt"
        )
        XCTAssertTrue(
            app.buttons["View recent recommendations"].waitForExistence(timeout: 5),
            "The \"View recent recommendations\" button is missing from the alert"
        )
        XCTAssertTrue(
            app.buttons["Dismiss"].waitForExistence(timeout: 5),
            "The alert's ✕ is missing"
        )
        XCTAssertTrue(
            app.staticTexts["Upcoming"].waitForExistence(timeout: 5),
            "The milestone timeline did not render under the alert"
        )
    }

    /// The sheet mirrors the event detail screen and then lists the picks.
    /// The milestone name + "COUNTDOWN" prove the event framing (hero + meta
    /// card) rendered; "Picks for Jas" is the section this sheet adds; the two
    /// headlines — the second asserted `isHittable`, since an offscreen element
    /// in a scroll view still exists in the tree — prove the picks are a list
    /// on screen and not a single card; the card predicate proves each pick is
    /// the same pressable feed card carrying its type.
    private func assertRecentPicksSheet(in app: XCUIApplication) {
        XCTAssertTrue(
            app.staticTexts["Jas's Birthday"].waitForExistence(timeout: 15),
            "The sheet never appeared — the recentPicksSheet harness did not present it, or its header did not render"
        )
        XCTAssertTrue(
            app.staticTexts["COUNTDOWN"].waitForExistence(timeout: 5),
            "The event meta card is missing from the sheet"
        )
        XCTAssertTrue(
            app.staticTexts["Picks for Jas"].waitForExistence(timeout: 5),
            "The picks section header is missing — the seeded batch did not resolve to the loaded phase"
        )
        XCTAssertTrue(
            app.staticTexts["Weekend Curations"].waitForExistence(timeout: 5),
            "The first headline never appeared — the feed did not render in the sheet, or it fell back to the type heading"
        )
        let secondHeading = app.staticTexts["Small Luxuries"]
        XCTAssertTrue(
            secondHeading.waitForExistence(timeout: 5),
            "Only one headline rendered — the picks are not a list, or the second pick fell back to the type heading"
        )
        XCTAssertTrue(
            secondHeading.isHittable,
            "The second headline exists but is not on screen — the capture would show a single card"
        )
        let firstCard = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Experience for Alex, Experience")
        ).firstMatch
        XCTAssertTrue(
            firstCard.waitForExistence(timeout: 5),
            "The first pick is not exposed as a pressable feed card carrying its type"
        )
        XCTAssertTrue(
            app.buttons["Close"].waitForExistence(timeout: 5),
            "The sheet's close button is missing"
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
