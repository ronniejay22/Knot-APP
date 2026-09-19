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
        // The change replaces the one-card-at-a-time recommendation carousel
        // with a vertical feed: a type heading over each fixed-height photo
        // card. The capture must show more than one heading + card pair on
        // screen at once (the whole point of the layout), plus the real
        // navigation bar above and the real `KnotTabBar` below.
        //
        // The screen sits behind an authenticated session and a ~25s
        // generation run; the `recsFeed` harness renders the real
        // `RecommendationsView` with a seeded, already-loaded view model —
        // inside the same reproduction of production chrome the `recsLoading`
        // harness uses (a real push from a root that hides its own bar, and the
        // tab bar mounted via `safeAreaInset`), so the shot proves the bottom
        // clearance and the bar restore, not just the cards.
        app.launchArguments += ["-uiTestScreenshot", "recsFeed"]
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
        // Two headings, not one: a single heading could be satisfied by a
        // one-card layout. Two different ones ON SCREEN is what proves the
        // feed is a list — `exists` alone is not enough, since an offscreen
        // element in a scroll view still exists in the accessibility tree, so
        // the second heading is also asserted `isHittable`. The fixture seeds
        // experience → gift → idea, and the headings are
        // `RecommendationFeedList.sectionLabel(for:)`.
        XCTAssertTrue(
            app.staticTexts["Experience"].waitForExistence(timeout: 15),
            "The first section heading never appeared — the recsFeed harness did not render the feed"
        )
        let secondHeading = app.staticTexts["Gift"]
        XCTAssertTrue(
            secondHeading.waitForExistence(timeout: 5),
            "Only one section rendered — the feed is not a vertical list"
        )
        XCTAssertTrue(
            secondHeading.isHittable,
            "The second section heading exists but is not on screen — the capture would show a single card"
        )

        // Each card is a single `Button` whose accessibility label starts with
        // its title (`RecommendationFeedCard.accessibilityLabel`), so a prefix
        // match finds the card without depending on the description text.
        let firstCard = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Experience for Alex")
        ).firstMatch
        XCTAssertTrue(
            firstCard.waitForExistence(timeout: 5),
            "The first feed card is not exposed as a pressable button"
        )

        // Let the loader's recede (0.42s) and the feed's `.revealIn` (0.5s)
        // finish, and the navigation/tab bars settle after the hand-off, so
        // the capture isn't taken mid-animation.
        Thread.sleep(forTimeInterval: 1.0)

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
