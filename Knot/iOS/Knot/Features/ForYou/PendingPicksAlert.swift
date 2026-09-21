//
//  PendingPicksAlert.swift
//  Knot
//
//  Step 19.63 — the one untapped milestone push the Journal announces.
//
//  A milestone push stores its three picks before it is sent. Tapping the push
//  shows them and marks the notification viewed; ignoring the push leaves the
//  picks stored, viewable, and invisible — a foreground-delivered push leaves
//  no trace in the app, and nothing on the Journal knew about notifications.
//  This type is the Journal's answer: from the notification history it picks
//  the newest push that was sent, never viewed, and still ahead of its event,
//  and carries what the alert and the sheet need to show it.
//

import Foundation

/// An untapped milestone push whose stored picks the Journal can surface.
struct PendingPicksAlert: Identifiable, Equatable, Sendable {

    /// Every unviewed push for this milestone, newest first — all of them are
    /// marked viewed together when the user opens or dismisses the alert, so a
    /// 14-day push cannot resurface after the 7-day one was seen. Never empty.
    let notificationIds: [String]

    /// The Journal's own row for the event. The sheet's hero, meta card and
    /// "Get ideas" all read it, so a push whose milestone is no longer in the
    /// list produces no alert at all rather than a half-rendered one.
    let milestone: MilestoneItemResponse

    /// When the newest push was sent.
    let sentAt: Date

    /// The newest push's id. A newer push for the same milestone is therefore a
    /// *different* alert — which is what lets the Journal animate the swap and
    /// lets `acknowledge` tell a stale alert from the current one.
    var id: String { notificationIds[0] }

    // MARK: - Selection

    /// The one alert to show, or nil.
    ///
    /// A row qualifies when it was actually `sent`, has no `viewed_at`, is not
    /// in `acknowledged` (ids the user opened or dismissed this session — kept
    /// locally because the mark-viewed PATCH is fire-and-forget, so a refresh
    /// racing it, or one that silently failed, must not resurrect the alert),
    /// its `sent_at` parses, its milestone is in `milestones`, and the event is
    /// still `isUpcoming`. The newest qualifying row decides the milestone;
    /// every qualifying row for that milestone rides along in
    /// `notificationIds`.
    ///
    /// `recommendations_count` is deliberately ignored: it is a cumulative
    /// per-milestone total, not this push's batch. The sheet's empty state
    /// covers a `sent` row with nothing stored (local dev without APNs).
    static func select(
        from history: [NotificationHistoryItemResponse],
        milestones: [MilestoneItemResponse],
        excluding acknowledged: Set<String> = []
    ) -> PendingPicksAlert? {
        // `uniquingKeysWith`, never `uniqueKeysWithValues` — the latter traps on
        // a duplicate id, and a list is not a place to crash.
        let milestonesById = Dictionary(
            milestones.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        let candidates: [(row: NotificationHistoryItemResponse, milestone: MilestoneItemResponse, sentAt: Date)] =
            history.compactMap { row in
                guard row.status == "sent",
                      row.viewedAt == nil,
                      !acknowledged.contains(row.id),
                      let sentAtString = row.sentAt,
                      let sentAt = RecommendationsViewModel.parseTimestamp(sentAtString),
                      let milestone = milestonesById[row.milestoneId],
                      isUpcoming(milestone: milestone, daysBefore: row.daysBefore)
                else { return nil }
                return (row, milestone, sentAt)
            }

        guard let newest = candidates.max(by: { $0.sentAt < $1.sentAt }) else { return nil }

        let forMilestone = candidates
            .filter { $0.milestone.id == newest.milestone.id }
            .sorted { $0.sentAt > $1.sentAt }

        return PendingPicksAlert(
            notificationIds: forMilestone.map(\.row.id),
            milestone: newest.milestone,
            sentAt: newest.sentAt
        )
    }

    /// Whether the occurrence a push counted down to has not rolled over.
    ///
    /// Judged from the Journal's own server-computed `daysUntil`, not from
    /// dates: `milestoneDate` carries a year-2000 placeholder for yearly events,
    /// pushes fire at 00:00 UTC (a calendar compare against the device clock is
    /// off by one west of UTC), and `daysUntil` is what the card and meta card
    /// beside the alert already render, so the two can never disagree. On push
    /// day the server reports `daysUntil == daysBefore`; it counts down to `0`
    /// on the event day — which still counts — and the day after it jumps to
    /// ~364 (yearly) or `nil` (one-time), either of which hides the alert. A
    /// milestone moved to a later date (`daysUntil > daysBefore`) hides it too:
    /// those picks were for the old date.
    ///
    /// Explicit comparisons rather than `0...daysBefore`, which traps on a
    /// negative bound.
    static func isUpcoming(milestone: MilestoneItemResponse, daysBefore: Int) -> Bool {
        guard let daysUntil = milestone.daysUntil else { return false }
        return daysUntil >= 0 && daysUntil <= daysBefore
    }

    // MARK: - Copy

    static let actionTitle = "View recent recommendations"

    /// "New picks for Jas's Birthday". A blank name falls back through
    /// `MilestoneRecommendationCopy.resolvedMilestoneName` ("this event").
    static func bannerTitle(milestoneName: String) -> String {
        "New picks for \(MilestoneRecommendationCopy.resolvedMilestoneName(milestoneName))"
    }

    /// "We put these together 2 hours ago — Jas's Birthday is in 4 days."
    ///
    /// Age from `agePhrase`; timing from `OccasionCopy.timingPhrase(daysUntil:)`
    /// ("today" / "tomorrow" / "next week" / "in 4 days"), so the banner talks
    /// about time exactly the way the entry modal and the recommendation sheet
    /// do. With no countdown the sentence simply stops after the age.
    static func bannerMessage(
        milestoneName: String,
        sentAt: Date,
        daysUntil: Int?,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> String {
        let age = agePhrase(sentAt: sentAt, now: now, calendar: calendar)
        guard let daysUntil else {
            return "We put these together \(age)."
        }
        let name = MilestoneRecommendationCopy.resolvedMilestoneName(milestoneName)
        let timing = OccasionCopy.timingPhrase(daysUntil: daysUntil)
        return "We put these together \(age) — \(name) is \(timing)."
    }

    /// How long ago a push was sent, as it reads inside a sentence.
    ///
    /// Sub-day granularity while `sentAt` is on today's calendar day — "just
    /// now", "a minute ago", "5 minutes ago", "an hour ago", "2 hours ago" —
    /// then the calendar-day rule `batchAgePhrase` uses: "yesterday", "N days
    /// ago", so a push at 11pm reads "yesterday" at 1am rather than "2 hours
    /// ago". A future timestamp (clock skew) clamps to "just now".
    ///
    /// Not `RelativeDateTimeFormatter`: its day boundary is 24-hour based,
    /// which breaks the calendar-day rule, and its output is locale-dependent,
    /// so tests could not pin the strings.
    static func agePhrase(
        sentAt: Date,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> String {
        let from = calendar.startOfDay(for: sentAt)
        let to = calendar.startOfDay(for: now)
        let days = max(0, calendar.dateComponents([.day], from: from, to: to).day ?? 0)

        switch days {
        case 0:
            let seconds = max(0, now.timeIntervalSince(sentAt))
            let minutes = Int(seconds / 60)
            let hours = Int(seconds / 3600)
            switch (hours, minutes) {
            case (0, 0): return "just now"
            case (0, 1): return "a minute ago"
            case (0, _): return "\(minutes) minutes ago"
            case (1, _): return "an hour ago"
            default: return "\(hours) hours ago"
            }
        case 1:
            return "yesterday"
        default:
            return "\(days) days ago"
        }
    }
}
