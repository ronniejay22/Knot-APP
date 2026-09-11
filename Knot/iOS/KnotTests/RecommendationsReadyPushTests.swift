//
//  RecommendationsReadyPushTests.swift
//  KnotTests
//
//  Foreground presentation of the backend's "your picks are ready" push.
//
//  The backend fires that push on every generation run, because it cannot know
//  whether the user stayed on the loading screen or left. The client is what
//  decides: a banner announcing the picks must never cover the picks.
//

import XCTest
import UserNotifications
@testable import Knot

@MainActor
final class RecommendationsReadyPresentationTests: XCTestCase {

    /// The whole point. A user watching the ~25s loading screen is about to be
    /// shown their picks by the app itself — a banner saying so would land on
    /// top of them.
    func testRecommendationsReadyIsSuppressedInTheForeground() {
        let options = AppDelegate.presentationOptions(
            forCategory: AppDelegate.recommendationsReadyCategory
        )

        XCTAssertTrue(
            options.isEmpty,
            "The recommendations-ready push must not present while the app is "
            + "in the foreground — it would cover the picks it announces."
        )
    }

    /// Everything else keeps the opt-in from Step 7.4. A milestone reminder is
    /// still worth seeing mid-session.
    func testMilestoneReminderStillPresentsInTheForeground() {
        let options = AppDelegate.presentationOptions(forCategory: "MILESTONE_REMINDER")

        XCTAssertTrue(options.contains(.banner))
        XCTAssertTrue(options.contains(.sound))
    }

    /// Local notifications — the "Still working on it…" one — carry no
    /// category, so the default branch is the one they take.
    func testUncategorizedNotificationStillPresents() {
        let options = AppDelegate.presentationOptions(forCategory: "")

        XCTAssertTrue(options.contains(.banner))
        XCTAssertTrue(options.contains(.sound))
    }

    func testUnknownCategoryStillPresents() {
        let options = AppDelegate.presentationOptions(forCategory: "SOMETHING_NEW")

        XCTAssertTrue(options.contains(.banner))
        XCTAssertTrue(options.contains(.sound))
    }

    /// Contract guard. This string is compared against
    /// `RECOMMENDATIONS_READY_CATEGORY` in `backend/app/services/apns.py`; if
    /// either side is renamed alone, the push stops being suppressed and starts
    /// interrupting users mid-reveal — silently, with nothing failing.
    func testCategoryMatchesTheBackendLiteral() {
        XCTAssertEqual(AppDelegate.recommendationsReadyCategory, "RECOMMENDATIONS_READY")
    }
}
