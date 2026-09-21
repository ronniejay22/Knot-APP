//
//  PendingPicksAlertTests.swift
//  KnotTests
//
//  The Journal's "New picks for …" alert for a milestone push the user never
//  tapped (Step 19.63): which push `PendingPicksAlert.select` announces, and
//  the copy it renders.
//
//  Sibling of `ResumeStoredBatchTests` in style: whole-second timestamps
//  against a fixed reference "now", so no boundary case lands on either side
//  of a sub-second round-trip at random (Step 19.54).
//

import XCTest
@testable import Knot

// MARK: - Fixtures

/// A whole-second reference "now" so `secondsBefore` arithmetic is exact.
private let referenceNow = Date(timeIntervalSince1970: 1_790_000_000)

private func isoTimestamp(for date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.string(from: date)
}

private func isoTimestamp(secondsBefore seconds: TimeInterval) -> String {
    isoTimestamp(for: referenceNow.addingTimeInterval(-seconds))
}

private func makeMilestone(
    id: String = "m1",
    name: String = "Jas's Birthday",
    daysUntil: Int? = 4
) -> MilestoneItemResponse {
    MilestoneItemResponse(
        id: id,
        milestoneType: "birthday",
        milestoneName: name,
        milestoneDate: "2000-10-12",
        recurrence: "yearly",
        budgetTier: "major_milestone",
        daysUntil: daysUntil,
        createdAt: "2026-07-04",
        occasionCategory: "birthday"
    )
}

private func makeRow(
    id: String = "n1",
    milestoneId: String = "m1",
    status: String = "sent",
    sentAt: String? = isoTimestamp(secondsBefore: 3600),
    viewedAt: String? = nil,
    daysBefore: Int = 7
) -> NotificationHistoryItemResponse {
    NotificationHistoryItemResponse(
        id: id,
        milestoneId: milestoneId,
        milestoneName: "Jas's Birthday",
        milestoneType: "birthday",
        milestoneDate: "2000-10-12",
        daysBefore: daysBefore,
        status: status,
        sentAt: sentAt,
        viewedAt: viewedAt,
        createdAt: sentAt ?? "",
        recommendationsCount: 3
    )
}

// MARK: - Selection

final class PendingPicksSelectionTests: XCTestCase {

    private let milestone = makeMilestone()

    func testASentUnviewedPushForAnUpcomingEventIsSelected() {
        let alert = PendingPicksAlert.select(from: [makeRow()], milestones: [milestone])

        XCTAssertEqual(alert?.id, "n1")
        XCTAssertEqual(alert?.notificationIds, ["n1"])
        XCTAssertEqual(alert?.milestone, milestone)
        XCTAssertEqual(alert?.sentAt, RecommendationsViewModel.parseTimestamp(isoTimestamp(secondsBefore: 3600)))
    }

    // MARK: Status / viewed

    func testAFailedPushIsNotSelected() {
        XCTAssertNil(PendingPicksAlert.select(from: [makeRow(status: "failed")], milestones: [milestone]))
    }

    func testAViewedPushIsNotSelected() {
        let row = makeRow(viewedAt: isoTimestamp(secondsBefore: 60))
        XCTAssertNil(PendingPicksAlert.select(from: [row], milestones: [milestone]))
    }

    // MARK: Upcoming

    /// On the day a push is sent the server reports `daysUntil == daysBefore`.
    func testPushDayCounts() {
        let row = makeRow(daysBefore: 7)
        XCTAssertNotNil(PendingPicksAlert.select(from: [row], milestones: [makeMilestone(daysUntil: 7)]))
    }

    /// The event day itself still counts — the picks are for today.
    func testTheEventDayCounts() {
        XCTAssertNotNil(PendingPicksAlert.select(from: [makeRow()], milestones: [makeMilestone(daysUntil: 0)]))
    }

    /// A yearly event's `daysUntil` jumps to ~364 the day after; a milestone
    /// moved to a later date reads `> daysBefore` — both are stale picks.
    func testAnEventPastItsPushWindowDoesNotCount() {
        XCTAssertNil(PendingPicksAlert.select(from: [makeRow(daysBefore: 7)], milestones: [makeMilestone(daysUntil: 8)]))
        XCTAssertNil(PendingPicksAlert.select(from: [makeRow(daysBefore: 7)], milestones: [makeMilestone(daysUntil: 364)]))
    }

    /// A one-time milestone that has passed reports no countdown at all.
    func testANilCountdownDoesNotCount() {
        XCTAssertNil(PendingPicksAlert.select(from: [makeRow()], milestones: [makeMilestone(daysUntil: nil)]))
    }

    func testANegativeCountdownDoesNotCount() {
        XCTAssertNil(PendingPicksAlert.select(from: [makeRow()], milestones: [makeMilestone(daysUntil: -1)]))
    }

    func testIsUpcomingSurvivesANegativeDaysBefore() {
        // `0...daysBefore` would trap here; explicit comparisons just say no.
        XCTAssertFalse(PendingPicksAlert.isUpcoming(milestone: makeMilestone(daysUntil: 0), daysBefore: -1))
    }

    // MARK: Which push

    /// The 14-day and 7-day pushes for one event both unviewed: the alert is
    /// the newer one, and it carries both ids so both are retired together.
    func testAllUnviewedPushesForTheChosenMilestoneRideAlongNewestFirst() {
        let rows = [
            makeRow(id: "n14", sentAt: isoTimestamp(secondsBefore: 7 * 86_400), daysBefore: 14),
            makeRow(id: "n7", sentAt: isoTimestamp(secondsBefore: 3600), daysBefore: 7),
        ]

        let alert = PendingPicksAlert.select(from: rows, milestones: [makeMilestone(daysUntil: 7)])

        XCTAssertEqual(alert?.id, "n7")
        XCTAssertEqual(alert?.notificationIds, ["n7", "n14"])
    }

    func testAViewedOlderPushIsLeftOutOfTheIds() {
        let rows = [
            makeRow(id: "n14", sentAt: isoTimestamp(secondsBefore: 7 * 86_400), viewedAt: isoTimestamp(secondsBefore: 86_400), daysBefore: 14),
            makeRow(id: "n7", sentAt: isoTimestamp(secondsBefore: 3600), daysBefore: 7),
        ]

        let alert = PendingPicksAlert.select(from: rows, milestones: [makeMilestone(daysUntil: 7)])

        XCTAssertEqual(alert?.notificationIds, ["n7"])
    }

    /// Two events with untapped pushes: the newest push wins, and the other
    /// event's ids are untouched (it surfaces after this one is acknowledged).
    func testTheNewestPushAcrossMilestonesWins() {
        let rows = [
            makeRow(id: "older", milestoneId: "m1", sentAt: isoTimestamp(secondsBefore: 2 * 86_400)),
            makeRow(id: "newer", milestoneId: "m2", sentAt: isoTimestamp(secondsBefore: 3600)),
        ]
        let milestones = [makeMilestone(id: "m1"), makeMilestone(id: "m2", name: "Anniversary")]

        let alert = PendingPicksAlert.select(from: rows, milestones: milestones)

        XCTAssertEqual(alert?.id, "newer")
        XCTAssertEqual(alert?.milestone.id, "m2")
        XCTAssertEqual(alert?.notificationIds, ["newer"])
    }

    /// Input order is irrelevant — the selection sorts by `sentAt`.
    func testRowOrderDoesNotMatter() {
        let rows = [
            makeRow(id: "n7", sentAt: isoTimestamp(secondsBefore: 3600), daysBefore: 7),
            makeRow(id: "n14", sentAt: isoTimestamp(secondsBefore: 7 * 86_400), daysBefore: 14),
        ]

        let alert = PendingPicksAlert.select(from: rows, milestones: [makeMilestone(daysUntil: 7)])

        XCTAssertEqual(alert?.notificationIds, ["n7", "n14"])
    }

    // MARK: Missing / malformed

    /// The sheet needs the milestone for its hero, meta card and "Get ideas",
    /// so a push whose event was deleted produces no alert rather than half of one.
    func testAPushWhoseMilestoneIsGoneIsNotSelected() {
        XCTAssertNil(PendingPicksAlert.select(from: [makeRow(milestoneId: "deleted")], milestones: [milestone]))
    }

    func testAMissingSentAtIsNotSelected() {
        XCTAssertNil(PendingPicksAlert.select(from: [makeRow(sentAt: nil)], milestones: [milestone]))
    }

    func testAnUnparseableSentAtIsNotSelected() {
        XCTAssertNil(PendingPicksAlert.select(from: [makeRow(sentAt: "yesterday")], milestones: [milestone]))
    }

    /// Supabase timestamps carry microseconds; the parser handles them.
    func testAFractionalSecondSentAtIsSelected() {
        let row = makeRow(sentAt: "2026-08-01T12:00:00.123456+00:00")
        XCTAssertNotNil(PendingPicksAlert.select(from: [row], milestones: [milestone]))
    }

    func testEmptyInputsProduceNoAlert() {
        XCTAssertNil(PendingPicksAlert.select(from: [], milestones: [milestone]))
        XCTAssertNil(PendingPicksAlert.select(from: [makeRow()], milestones: []))
    }

    func testDuplicateMilestoneIdsDoNotTrap() {
        let alert = PendingPicksAlert.select(from: [makeRow()], milestones: [milestone, milestone])
        XCTAssertEqual(alert?.id, "n1")
    }

    // MARK: Acknowledged

    /// Ids opened or dismissed this session are out, even before the
    /// mark-viewed PATCH has landed (or if it never does).
    func testAcknowledgedIdsAreExcluded() {
        let rows = [
            makeRow(id: "n14", sentAt: isoTimestamp(secondsBefore: 7 * 86_400), daysBefore: 14),
            makeRow(id: "n7", sentAt: isoTimestamp(secondsBefore: 3600), daysBefore: 7),
        ]

        let alert = PendingPicksAlert.select(
            from: rows,
            milestones: [makeMilestone(daysUntil: 7)],
            excluding: ["n7"]
        )

        XCTAssertEqual(alert?.id, "n14")
        XCTAssertEqual(alert?.notificationIds, ["n14"])

        XCTAssertNil(PendingPicksAlert.select(
            from: rows,
            milestones: [makeMilestone(daysUntil: 7)],
            excluding: ["n7", "n14"]
        ))
    }
}

// MARK: - Copy

final class PendingPicksCopyTests: XCTestCase {

    /// A fixed calendar so the day arithmetic does not depend on the machine's
    /// zone, and a noon reference so no case straddles midnight by accident.
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }()

    private var noon: Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: 20, hour: 12))!
    }

    private func age(secondsBefore seconds: TimeInterval) -> String {
        PendingPicksAlert.agePhrase(sentAt: noon.addingTimeInterval(-seconds), now: noon, calendar: calendar)
    }

    func testAgeWithinTheHour() {
        XCTAssertEqual(age(secondsBefore: 0), "just now")
        XCTAssertEqual(age(secondsBefore: 30), "just now")
        XCTAssertEqual(age(secondsBefore: 60), "a minute ago")
        XCTAssertEqual(age(secondsBefore: 5 * 60), "5 minutes ago")
        XCTAssertEqual(age(secondsBefore: 59 * 60), "59 minutes ago")
    }

    func testAgeInHours() {
        XCTAssertEqual(age(secondsBefore: 60 * 60), "an hour ago")
        XCTAssertEqual(age(secondsBefore: 2 * 60 * 60), "2 hours ago")
        XCTAssertEqual(age(secondsBefore: 11 * 60 * 60), "11 hours ago")
    }

    /// Calendar days, not 24-hour spans: a push at 11:30pm reads "yesterday"
    /// at 12:30am, even though only an hour has passed.
    func testLateLastNightIsYesterday() {
        let lateLastNight = calendar.date(bySettingHour: 23, minute: 30, second: 0, of: calendar.date(byAdding: .day, value: -1, to: noon)!)!
        let earlyToday = calendar.date(bySettingHour: 0, minute: 30, second: 0, of: noon)!

        XCTAssertEqual(
            PendingPicksAlert.agePhrase(sentAt: lateLastNight, now: earlyToday, calendar: calendar),
            "yesterday"
        )
    }

    func testAgeInDays() {
        let threeDaysAgo = calendar.date(byAdding: .day, value: -3, to: noon)!
        XCTAssertEqual(PendingPicksAlert.agePhrase(sentAt: threeDaysAgo, now: noon, calendar: calendar), "3 days ago")
    }

    /// Clock skew can put a server timestamp a little ahead of the device.
    func testAFutureTimestampClampsToJustNow() {
        XCTAssertEqual(
            PendingPicksAlert.agePhrase(sentAt: noon.addingTimeInterval(120), now: noon, calendar: calendar),
            "just now"
        )
    }

    func testTitle() {
        XCTAssertEqual(PendingPicksAlert.bannerTitle(milestoneName: "Jas's Birthday"), "New picks for Jas's Birthday")
        XCTAssertEqual(PendingPicksAlert.bannerTitle(milestoneName: "   "), "New picks for this event")
    }

    func testMessageComposesAgeAndTiming() {
        let twoHoursAgo = noon.addingTimeInterval(-2 * 60 * 60)

        XCTAssertEqual(
            PendingPicksAlert.bannerMessage(milestoneName: "Jas's Birthday", sentAt: twoHoursAgo, daysUntil: 4, now: noon, calendar: calendar),
            "We put these together 2 hours ago — Jas's Birthday is in 4 days."
        )
        XCTAssertEqual(
            PendingPicksAlert.bannerMessage(milestoneName: "Jas's Birthday", sentAt: twoHoursAgo, daysUntil: 7, now: noon, calendar: calendar),
            "We put these together 2 hours ago — Jas's Birthday is next week."
        )
        XCTAssertEqual(
            PendingPicksAlert.bannerMessage(milestoneName: "Jas's Birthday", sentAt: twoHoursAgo, daysUntil: 0, now: noon, calendar: calendar),
            "We put these together 2 hours ago — Jas's Birthday is today."
        )
    }

    /// No countdown → the sentence stops after the age.
    func testMessageWithoutACountdown() {
        XCTAssertEqual(
            PendingPicksAlert.bannerMessage(milestoneName: "Jas's Birthday", sentAt: noon, daysUntil: nil, now: noon, calendar: calendar),
            "We put these together just now."
        )
    }

    func testActionTitle() {
        XCTAssertEqual(PendingPicksAlert.actionTitle, "View recent recommendations")
    }
}
