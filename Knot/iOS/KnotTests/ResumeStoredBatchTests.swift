//
//  ResumeStoredBatchTests.swift
//  KnotTests
//
//  Resuming a stored recommendation batch on re-entry instead of regenerating.
//
//  Every generation run is persisted server-side before it responds, so a user
//  who generated picks from the Journal, backed out, and came back should see
//  the same picks — not a second ~25s wait. `RecommendationsViewModel.resumeFreshBatch`
//  reads the newest stored batch for the surface's context (a milestone, or
//  just-because) and publishes it when it is younger than
//  `resumableBatchWindow`; anything else means "generate".
//
//  Sibling of `LostGenerationRecoveryTests`, which covers the 15-minute recovery
//  read the same seam backs. The rules differ on purpose: recovery must reject
//  the batch that was on screen when a run started, resume *wants* it.
//

import XCTest
import UIKit
@testable import Knot

// MARK: - Fixtures

@MainActor
private func makeItem(
    id: String = "rec-1",
    title: String = "Hand-thrown Mug",
    createdAt: String
) -> MilestoneRecommendationItemResponse {
    MilestoneRecommendationItemResponse(
        id: id,
        recommendationType: "gift",
        title: title,
        description: "A speckled stoneware mug.",
        externalUrl: "https://example.com/mug",
        priceCents: 4200,
        merchantName: "Clay Co.",
        imageUrl: "https://example.com/mug.jpg",
        createdAt: createdAt,
        personalizationNote: "She has been taking pottery classes.",
        isIdea: false,
        contentSections: nil,
        headline: "Small Luxuries"
    )
}

@MainActor
private func makeResponse(
    itemCount: Int = 3,
    createdAt: String,
    milestoneId: String? = nil,
    briefingText: String? = nil
) -> MilestoneRecommendationsResponse {
    let items = (0..<itemCount).map {
        makeItem(id: "rec-\($0)", title: "Pick \($0)", createdAt: createdAt)
    }
    return MilestoneRecommendationsResponse(
        recommendations: items,
        count: items.count,
        milestoneId: milestoneId,
        briefingText: briefingText
    )
}

/// ISO 8601 without fractional seconds. The window tests compare against a
/// fixed `now`, and `ISO8601DateFormatter` emits milliseconds at most, so a
/// sub-second `Date()` round-trip would land the boundary case on either side
/// at random (Step 19.54). Whole seconds only.
private func isoTimestamp(for date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.string(from: date)
}

/// A whole-second reference "now" so `secondsBefore` arithmetic is exact.
private let referenceNow = Date(timeIntervalSince1970: 1_790_000_000)

private func isoTimestamp(secondsBefore seconds: TimeInterval) -> String {
    isoTimestamp(for: referenceNow.addingTimeInterval(-seconds))
}

/// Fetcher seam that records which read was made, and with what argument,
/// and serves a canned response (or throws) for each.
@MainActor
private final class RecordingFetcher: MilestoneRecommendationsFetching {
    enum Behavior {
        case success(MilestoneRecommendationsResponse)
        case failure(Error)
    }

    var milestoneBehavior: Behavior
    var latestBehavior: Behavior

    private(set) var requestedMilestoneIds: [String] = []
    private(set) var latestJustBecauseArgs: [Bool] = []

    init(milestone: Behavior, latest: Behavior) {
        self.milestoneBehavior = milestone
        self.latestBehavior = latest
    }

    /// One behavior for whichever read the code under test makes.
    convenience init(_ behavior: Behavior) {
        self.init(milestone: behavior, latest: behavior)
    }

    func fetchMilestoneRecommendations(
        milestoneId: String
    ) async throws -> MilestoneRecommendationsResponse {
        requestedMilestoneIds.append(milestoneId)
        return try resolve(milestoneBehavior)
    }

    func fetchLatestRecommendations(justBecause: Bool) async throws -> MilestoneRecommendationsResponse {
        latestJustBecauseArgs.append(justBecause)
        return try resolve(latestBehavior)
    }

    private func resolve(_ behavior: Behavior) throws -> MilestoneRecommendationsResponse {
        switch behavior {
        case .success(let response): return response
        case .failure(let error): throw error
        }
    }
}

/// A fetcher that parks every read on a gate until the test opens it, so the
/// test can act — background the app, say — while the read is in flight.
@MainActor
private final class GatedFetcher: MilestoneRecommendationsFetching {
    private let response: MilestoneRecommendationsResponse
    private var gate: CheckedContinuation<Void, Never>?
    private(set) var isParked = false

    init(response: MilestoneRecommendationsResponse) {
        self.response = response
    }

    func fetchMilestoneRecommendations(milestoneId: String) async throws -> MilestoneRecommendationsResponse {
        await park()
        return response
    }

    func fetchLatestRecommendations(justBecause: Bool) async throws -> MilestoneRecommendationsResponse {
        await park()
        return response
    }

    private func park() async {
        isParked = true
        await withCheckedContinuation { gate = $0 }
    }

    func open() {
        gate?.resume()
        gate = nil
    }
}

private struct StubError: LocalizedError {
    var errorDescription: String? { "Network unavailable." }
}

// MARK: - The freshness rule

@MainActor
final class ResumableBatchWindowTests: XCTestCase {

    private let oneDay: TimeInterval = 24 * 60 * 60

    func testWindowIsSevenDays() {
        XCTAssertEqual(RecommendationsViewModel.resumableBatchWindow, 7 * oneDay)
    }

    func testABatchFromYesterdayIsResumable() {
        let response = makeResponse(createdAt: isoTimestamp(secondsBefore: oneDay))
        XCTAssertTrue(
            RecommendationsViewModel.isResumableBatch(response, milestoneId: nil, now: referenceNow)
        )
    }

    /// The window is inclusive at its edge: a batch exactly seven days old
    /// still resumes.
    func testABatchExactlyAtTheWindowIsResumable() {
        let response = makeResponse(
            createdAt: isoTimestamp(secondsBefore: RecommendationsViewModel.resumableBatchWindow)
        )
        XCTAssertTrue(
            RecommendationsViewModel.isResumableBatch(response, milestoneId: nil, now: referenceNow)
        )
    }

    func testABatchOneSecondPastTheWindowIsNotResumable() {
        let response = makeResponse(
            createdAt: isoTimestamp(secondsBefore: RecommendationsViewModel.resumableBatchWindow + 1)
        )
        XCTAssertFalse(
            RecommendationsViewModel.isResumableBatch(response, milestoneId: nil, now: referenceNow)
        )
    }

    // MARK: Context

    func testAMilestoneBatchResumesForItsOwnMilestone() {
        let response = makeResponse(createdAt: isoTimestamp(secondsBefore: 60), milestoneId: "ms-1")
        XCTAssertTrue(
            RecommendationsViewModel.isResumableBatch(response, milestoneId: "ms-1", now: referenceNow)
        )
    }

    /// A milestone's screen must not show another milestone's picks, however
    /// fresh — saving one would file it under the wrong event.
    func testAMilestoneBatchDoesNotResumeForADifferentMilestone() {
        let response = makeResponse(createdAt: isoTimestamp(secondsBefore: 60), milestoneId: "ms-1")
        XCTAssertFalse(
            RecommendationsViewModel.isResumableBatch(response, milestoneId: "ms-2", now: referenceNow)
        )
    }

    /// The just-because surface has no milestone; a milestone batch is the
    /// wrong context for it even though `/latest` could hand one back.
    func testAMilestoneBatchDoesNotResumeAsJustBecause() {
        let response = makeResponse(createdAt: isoTimestamp(secondsBefore: 60), milestoneId: "ms-1")
        XCTAssertFalse(
            RecommendationsViewModel.isResumableBatch(response, milestoneId: nil, now: referenceNow)
        )
    }

    func testAJustBecauseBatchDoesNotResumeForAMilestone() {
        let response = makeResponse(createdAt: isoTimestamp(secondsBefore: 60), milestoneId: nil)
        XCTAssertFalse(
            RecommendationsViewModel.isResumableBatch(response, milestoneId: "ms-1", now: referenceNow)
        )
    }

    // MARK: Degenerate input

    func testAnEmptyBatchIsNotResumable() {
        let response = makeResponse(itemCount: 0, createdAt: isoTimestamp(secondsBefore: 60))
        XCTAssertFalse(
            RecommendationsViewModel.isResumableBatch(response, milestoneId: nil, now: referenceNow)
        )
    }

    /// Fails closed: a timestamp that does not parse cannot be judged fresh.
    func testAnUnparseableTimestampIsNotResumable() {
        let response = makeResponse(createdAt: "yesterday")
        XCTAssertFalse(
            RecommendationsViewModel.isResumableBatch(response, milestoneId: nil, now: referenceNow)
        )
    }

    /// Supabase timestamps carry microseconds; those parse and are judged too.
    func testAFractionalSecondTimestampIsResumable() {
        let response = makeResponse(createdAt: "2026-09-19T12:00:00.123456Z")
        let now = RecommendationsViewModel.parseTimestamp("2026-09-20T12:00:00Z")!
        XCTAssertTrue(
            RecommendationsViewModel.isResumableBatch(response, milestoneId: nil, now: now)
        )
    }

    // MARK: Batch timestamp

    func testBatchTimestampIsTheNewestRows() {
        let response = makeResponse(createdAt: "2026-09-18T09:30:00Z")
        XCTAssertEqual(
            RecommendationsViewModel.batchTimestamp(of: response),
            RecommendationsViewModel.parseTimestamp("2026-09-18T09:30:00Z")
        )
    }

    func testBatchTimestampIsNilForAnEmptyBatch() {
        let response = makeResponse(itemCount: 0, createdAt: "2026-09-18T09:30:00Z")
        XCTAssertNil(RecommendationsViewModel.batchTimestamp(of: response))
    }
}

// MARK: - The resume itself

@MainActor
final class ResumeFreshBatchTests: XCTestCase {

    private func makeViewModel(_ fetcher: RecordingFetcher) -> RecommendationsViewModel {
        RecommendationsViewModel(milestoneFetcher: fetcher)
    }

    /// The whole-second timestamp of a batch made a minute ago, against the
    /// real clock: `resumeFreshBatch` uses `Date()` and a minute is far inside
    /// the window whichever way the second rounds.
    private func freshTimestamp() -> String {
        isoTimestamp(for: Date().addingTimeInterval(-60))
    }

    // MARK: Which read

    func testAMilestoneSurfaceReadsItsMilestone() async {
        let fetcher = RecordingFetcher(
            .success(makeResponse(createdAt: freshTimestamp(), milestoneId: "ms-1"))
        )
        let viewModel = makeViewModel(fetcher)

        let resumed = await viewModel.resumeFreshBatch(milestoneId: "ms-1")

        XCTAssertTrue(resumed)
        XCTAssertEqual(fetcher.requestedMilestoneIds, ["ms-1"])
        XCTAssertTrue(fetcher.latestJustBecauseArgs.isEmpty, "A milestone surface never reads /latest")
    }

    /// The just-because surface reads `/latest` *scoped*. Unscoped, the newest
    /// batch for the vault could be one a push webhook generated for a
    /// milestone, and the "Surprise them today" screen would show it as its own.
    func testAJustBecauseSurfaceReadsLatestScopedToJustBecause() async {
        let fetcher = RecordingFetcher(
            .success(makeResponse(createdAt: freshTimestamp(), milestoneId: nil))
        )
        let viewModel = makeViewModel(fetcher)

        let resumed = await viewModel.resumeFreshBatch(milestoneId: nil)

        XCTAssertTrue(resumed)
        XCTAssertEqual(fetcher.latestJustBecauseArgs, [true])
        XCTAssertTrue(fetcher.requestedMilestoneIds.isEmpty, "A just-because surface never reads by milestone")
    }

    // MARK: Publishing

    func testAFreshBatchIsPublished() async {
        let createdAt = freshTimestamp()
        let fetcher = RecordingFetcher(
            .success(makeResponse(createdAt: createdAt, milestoneId: nil, briefingText: "Knot's take."))
        )
        let viewModel = makeViewModel(fetcher)
        let tokenBefore = viewModel.deckResetToken

        let resumed = await viewModel.resumeFreshBatch(milestoneId: nil)

        XCTAssertTrue(resumed)
        XCTAssertEqual(viewModel.recommendations.count, 3)
        XCTAssertEqual(viewModel.recommendations.first?.title, "Pick 0")
        XCTAssertEqual(viewModel.recommendations.first?.headline, "Small Luxuries")
        XCTAssertEqual(viewModel.briefingText, "Knot's take.")
        XCTAssertTrue(viewModel.hasLoadedInitially)
        XCTAssertTrue(viewModel.isResumedBatch, "A resumed batch is what the banner announces")
        XCTAssertEqual(viewModel.deckResetToken, tokenBefore + 1)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.isLoading)
    }

    /// The banner exists only for a resumed batch. The next batch published by
    /// any other path — here the push tap-through's read, the one other stored
    /// read this seam serves without networking — retires it.
    func testALaterNonResumePublishClearsTheResumedFlag() async {
        let fetcher = RecordingFetcher(
            .success(makeResponse(createdAt: freshTimestamp(), milestoneId: "ms-1"))
        )
        let viewModel = makeViewModel(fetcher)
        _ = await viewModel.resumeFreshBatch(milestoneId: "ms-1")
        XCTAssertTrue(viewModel.isResumedBatch)

        _ = await viewModel.loadPregeneratedRecommendations(milestoneId: "ms-1")

        XCTAssertFalse(viewModel.isResumedBatch)
    }

    /// The banner reads the stored row's own timestamp, not the moment the
    /// screen was opened — that is what makes "2 days ago" true.
    func testTheBatchTimestampIsTheStoredRows() async {
        let createdAt = freshTimestamp()
        let fetcher = RecordingFetcher(.success(makeResponse(createdAt: createdAt)))
        let viewModel = makeViewModel(fetcher)

        _ = await viewModel.resumeFreshBatch(milestoneId: nil)

        XCTAssertEqual(
            viewModel.batchGeneratedAt,
            RecommendationsViewModel.parseTimestamp(createdAt)
        )
    }

    /// `/latest` never carries a briefing. A milestone surface that had one
    /// must not have it blanked by a read that simply does not return one.
    func testANilBriefingLeavesTheExistingBriefingAlone() async {
        let fetcher = RecordingFetcher(
            .success(makeResponse(createdAt: freshTimestamp(), milestoneId: "ms-1", briefingText: nil))
        )
        let viewModel = makeViewModel(fetcher)
        viewModel.briefingText = "Already here."

        _ = await viewModel.resumeFreshBatch(milestoneId: "ms-1")

        XCTAssertEqual(viewModel.briefingText, "Already here.")
    }

    // MARK: Not resumable → generate

    func testAStaleBatchIsNotPublished() async {
        let stale = isoTimestamp(
            for: Date().addingTimeInterval(-(RecommendationsViewModel.resumableBatchWindow + 3600))
        )
        let fetcher = RecordingFetcher(.success(makeResponse(createdAt: stale)))
        let viewModel = makeViewModel(fetcher)

        let resumed = await viewModel.resumeFreshBatch(milestoneId: nil)

        XCTAssertFalse(resumed)
        XCTAssertTrue(viewModel.recommendations.isEmpty)
        XCTAssertFalse(viewModel.hasLoadedInitially)
        XCTAssertFalse(viewModel.isResumedBatch)
        XCTAssertNil(viewModel.batchGeneratedAt)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.isLoading)
    }

    func testAnEmptyBatchIsNotPublished() async {
        let fetcher = RecordingFetcher(.success(makeResponse(itemCount: 0, createdAt: freshTimestamp())))
        let viewModel = makeViewModel(fetcher)

        let resumed = await viewModel.resumeFreshBatch(milestoneId: nil)

        XCTAssertFalse(resumed)
        XCTAssertTrue(viewModel.recommendations.isEmpty)
        XCTAssertFalse(viewModel.hasLoadedInitially)
    }

    func testAWrongContextBatchIsNotPublished() async {
        // `/by-milestone/{id}` echoes the id it was asked for, so this only
        // happens if the seam misbehaves — but the rule is on the response,
        // and a mismatch must never reach the screen.
        let fetcher = RecordingFetcher(
            .success(makeResponse(createdAt: freshTimestamp(), milestoneId: "ms-other"))
        )
        let viewModel = makeViewModel(fetcher)

        let resumed = await viewModel.resumeFreshBatch(milestoneId: "ms-1")

        XCTAssertFalse(resumed)
        XCTAssertTrue(viewModel.recommendations.isEmpty)
    }

    /// Best-effort by contract: a failed read is "nothing to resume", never an
    /// error state. The caller's next move is to generate, and the push path's
    /// Try-Again-re-reads semantics (`loadPregeneratedRecommendations`) would
    /// be wrong here — a retry must retry the thing that failed.
    func testAFailedReadIsSwallowedAndReportsNothingToResume() async {
        let fetcher = RecordingFetcher(.failure(StubError()))
        let viewModel = makeViewModel(fetcher)

        let resumed = await viewModel.resumeFreshBatch(milestoneId: nil)

        XCTAssertFalse(resumed)
        XCTAssertNil(viewModel.errorMessage, "A failed resume must not surface as an error")
        XCTAssertTrue(viewModel.recommendations.isEmpty)
        XCTAssertFalse(viewModel.isLoading)
    }

    func testAFailedMilestoneReadIsSwallowedToo() async {
        let fetcher = RecordingFetcher(.failure(StubError()))
        let viewModel = makeViewModel(fetcher)

        let resumed = await viewModel.resumeFreshBatch(milestoneId: "ms-1")

        XCTAssertFalse(resumed)
        XCTAssertNil(viewModel.errorMessage)
    }

    // MARK: Backgrounding mid-read

    /// The scene-phase handler keys off `isLoading`, so backgrounding during
    /// this sub-second read takes the same background window (and schedules
    /// the same "Still working on it…" notice) as a ~25s generation. The read
    /// must hand the window back when it finishes; a leaked assertion makes
    /// the *next* backgrounded generation bail at `guard backgroundTaskID ==
    /// .invalid` and send no notice at all (review finding, Step 19.62).
    func testAReadInterruptedByBackgroundingHandsTheWindowBack() async {
        let fetcher = GatedFetcher(response: makeResponse(createdAt: freshTimestamp()))
        let viewModel = RecommendationsViewModel(milestoneFetcher: fetcher)

        let resume = Task { await viewModel.resumeFreshBatch(milestoneId: nil) }
        for _ in 0..<50 where !fetcher.isParked { await Task.yield() }
        XCTAssertTrue(fetcher.isParked, "The read never reached the gate")
        XCTAssertTrue(viewModel.isLoading)

        viewModel.handleAppBackgroundedWhileLoading()
        // The simulator's test host is a real app, so a window is granted;
        // without one this test would prove nothing, so say so rather than
        // pass vacuously.
        XCTAssertNotEqual(viewModel.backgroundTaskID, UIBackgroundTaskIdentifier.invalid, "No background window was taken")

        fetcher.open()
        let resumed = await resume.value

        XCTAssertTrue(resumed)
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertEqual(viewModel.backgroundTaskID, UIBackgroundTaskIdentifier.invalid, "The resume read leaked the background window")
    }

    // MARK: Guards

    func testResumeIsSkippedWhileAnotherLoadIsInFlight() async {
        let fetcher = RecordingFetcher(.success(makeResponse(createdAt: freshTimestamp())))
        let viewModel = makeViewModel(fetcher)
        viewModel.isLoading = true

        let resumed = await viewModel.resumeFreshBatch(milestoneId: nil)

        XCTAssertFalse(resumed)
        XCTAssertTrue(fetcher.latestJustBecauseArgs.isEmpty, "No read is made while a load is in flight")
        XCTAssertTrue(viewModel.isLoading, "The in-flight load's flag is not disturbed")
    }
}

// MARK: - The banner copy

@MainActor
final class BatchAgePhraseTests: XCTestCase {

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

    private func phrase(daysAgo: Int, hour: Int = 12) -> String {
        let generated = calendar.date(byAdding: .day, value: -daysAgo, to: noon)!
        let shifted = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: generated)!
        return RecommendationsViewModel.batchAgePhrase(generatedAt: shifted, now: noon, calendar: calendar)
    }

    func testToday() {
        XCTAssertEqual(phrase(daysAgo: 0), "earlier today")
    }

    func testYesterday() {
        XCTAssertEqual(phrase(daysAgo: 1), "yesterday")
    }

    func testDaysAgo() {
        XCTAssertEqual(phrase(daysAgo: 2), "2 days ago")
        XCTAssertEqual(phrase(daysAgo: 6), "6 days ago")
    }

    /// Calendar days, not 24-hour spans: a batch from late last night is
    /// "yesterday" this morning, even though fewer than 24 hours have passed.
    func testLateLastNightIsYesterday() {
        let lateLastNight = calendar.date(byAdding: .day, value: -1, to: noon)!
        let elevenPM = calendar.date(bySettingHour: 23, minute: 30, second: 0, of: lateLastNight)!
        let earlyToday = calendar.date(bySettingHour: 8, minute: 0, second: 0, of: noon)!
        XCTAssertEqual(
            RecommendationsViewModel.batchAgePhrase(generatedAt: elevenPM, now: earlyToday, calendar: calendar),
            "yesterday"
        )
    }

    /// Clock skew can put a server timestamp a little ahead of the device;
    /// that must never read as a negative count.
    func testAFutureTimestampClampsToToday() {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: noon)!
        XCTAssertEqual(
            RecommendationsViewModel.batchAgePhrase(generatedAt: tomorrow, now: noon, calendar: calendar),
            "earlier today"
        )
    }

    // MARK: The sentence

    private var twoDaysAgo: Date {
        calendar.date(byAdding: .day, value: -2, to: noon)!
    }

    func testTheMessageNamesThePartnerAndTheAge() {
        XCTAssertEqual(
            RecommendationsViewModel.resumeBannerMessage(
                partnerName: "Jas", generatedAt: twoDaysAgo, now: noon, calendar: calendar
            ),
            "These are the picks we found for Jas 2 days ago. Want a fresh set?"
        )
    }

    /// No name → no "for": the sentence closes up rather than reading
    /// "for  2 days ago" or naming a placeholder.
    func testTheMessageDropsTheNameWhenUnknown() {
        XCTAssertEqual(
            RecommendationsViewModel.resumeBannerMessage(
                partnerName: nil, generatedAt: twoDaysAgo, now: noon, calendar: calendar
            ),
            "These are the picks we found 2 days ago. Want a fresh set?"
        )
        XCTAssertEqual(
            RecommendationsViewModel.resumeBannerMessage(
                partnerName: "   ", generatedAt: twoDaysAgo, now: noon, calendar: calendar
            ),
            "These are the picks we found 2 days ago. Want a fresh set?"
        )
    }

    func testTheMessageReadsNaturallyForToday() {
        XCTAssertEqual(
            RecommendationsViewModel.resumeBannerMessage(
                partnerName: "Jas", generatedAt: noon, now: noon, calendar: calendar
            ),
            "These are the picks we found for Jas earlier today. Want a fresh set?"
        )
    }
}
