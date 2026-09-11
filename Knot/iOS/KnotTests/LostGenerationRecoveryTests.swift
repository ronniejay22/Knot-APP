//
//  LostGenerationRecoveryTests.swift
//  KnotTests
//
//  Recovering a generation whose HTTP response never reached the app.
//
//  The pipeline runs server-side and stores its picks *before* responding, so a
//  request killed by app suspension (iOS grants ~30s of background execution
//  against a ~20-30s pipeline) or by a client timeout leaves finished work in
//  the database that the app has no way to reach. Without recovery, the
//  "your picks are ready ✨" push announced picks and then dropped the user on
//  an error screen whose Try Again burned another ~25s regenerating what
//  already existed.
//

import XCTest
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
        contentSections: nil
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

/// ISO 8601 with fractional seconds — the shape Supabase actually returns.
private func isoTimestamp(for date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: date)
}

private func isoTimestamp(secondsAgo: TimeInterval) -> String {
    isoTimestamp(for: Date().addingTimeInterval(-secondsAgo))
}

/// Fetcher seam that serves a canned latest-batch response.
@MainActor
private final class StubLatestFetcher: MilestoneRecommendationsFetching {
    enum Behavior {
        case success(MilestoneRecommendationsResponse)
        case failure(Error)
    }

    var behavior: Behavior
    private(set) var latestRequestCount = 0

    init(behavior: Behavior) {
        self.behavior = behavior
    }

    func fetchMilestoneRecommendations(
        milestoneId: String
    ) async throws -> MilestoneRecommendationsResponse {
        throw NotificationHistoryServiceError.networkError("not used in these tests")
    }

    func fetchLatestRecommendations() async throws -> MilestoneRecommendationsResponse {
        latestRequestCount += 1
        switch behavior {
        case .success(let response):
            return response
        case .failure(let error):
            throw error
        }
    }
}

// MARK: - The recency rule

@MainActor
final class RecoverableBatchWindowTests: XCTestCase {

    /// The ordinary case: a first generate (nothing on screen) whose batch was
    /// stored seconds ago.
    func testAcceptsTheBatchThisRunStored() {
        let response = makeResponse(createdAt: isoTimestamp(secondsAgo: 25))
        XCTAssertTrue(RecommendationsViewModel.isRecoverableBatch(
            response, replacing: [], milestoneId: nil
        ))
    }

    /// Wide enough to cover an app suspended for a few minutes after the run.
    func testAcceptsABatchStoredMinutesAgo() {
        let response = makeResponse(createdAt: isoTimestamp(secondsAgo: 5 * 60))
        XCTAssertTrue(RecommendationsViewModel.isRecoverableBatch(
            response, replacing: [], milestoneId: nil
        ))
    }

    /// **The guard that matters most.** A failed re-roll must not "recover" the
    /// batch it was replacing: the user would wait ~25s, watch the cards
    /// animate out and back, and get the identical three with no error to
    /// explain it. Recency alone would have let this through, and so would any
    /// clock comparison — an eager user re-rolls seconds after the previous
    /// batch was stored.
    func testRejectsTheBatchItWasReplacing() {
        let response = makeResponse(createdAt: isoTimestamp(secondsAgo: 25))
        let onScreen = response.recommendations.map(\.id)

        XCTAssertFalse(RecommendationsViewModel.isRecoverableBatch(
            response, replacing: onScreen, milestoneId: nil
        ))
    }

    /// Even a partial overlap is disqualifying: a genuine replacement shares no
    /// rows, because every run inserts new ones and `/refresh` excludes the ids
    /// it was given.
    func testRejectsABatchOverlappingTheOneOnScreen() {
        let response = makeResponse(createdAt: isoTimestamp(secondsAgo: 25))
        let oneSharedId = [response.recommendations[1].id]

        XCTAssertFalse(RecommendationsViewModel.isRecoverableBatch(
            response, replacing: oneSharedId, milestoneId: nil
        ))
    }

    /// A wholly different batch is the replacement this run produced.
    func testAcceptsABatchSharingNothingWithTheOneOnScreen() {
        let response = makeResponse(createdAt: isoTimestamp(secondsAgo: 25))

        XCTAssertTrue(RecommendationsViewModel.isRecoverableBatch(
            response,
            replacing: ["old-1", "old-2", "old-3"],
            milestoneId: nil
        ))
    }

    /// The absolute ceiling: a batch this old is a previous session's, whatever
    /// its ids.
    ///
    /// `now` is anchored to a whole second on purpose: ISO8601DateFormatter
    /// emits only milliseconds, so a `Date()` carrying sub-millisecond
    /// precision does not survive the round-trip through the string and the
    /// boundary lands on either side at random.
    func testRejectsABatchOlderThanTheWindow() {
        let now = Date(timeIntervalSince1970: 1_789_000_000)
        let createdAt = now.addingTimeInterval(
            -RecommendationsViewModel.recoverableBatchWindow - 60
        )

        let response = makeResponse(createdAt: isoTimestamp(for: createdAt))
        XCTAssertFalse(RecommendationsViewModel.isRecoverableBatch(
            response, replacing: [], milestoneId: nil, now: now
        ))
    }

    /// Exactly at the window is still inside it (the comparison is `<=`).
    func testAcceptsABatchExactlyAtTheWindow() {
        let now = Date(timeIntervalSince1970: 1_789_000_000)
        let createdAt = now.addingTimeInterval(-RecommendationsViewModel.recoverableBatchWindow)

        let response = makeResponse(createdAt: isoTimestamp(for: createdAt))
        XCTAssertTrue(RecommendationsViewModel.isRecoverableBatch(
            response, replacing: [], milestoneId: nil, now: now
        ))
    }

    /// Server/device clock skew can date a batch slightly ahead of the device.
    func testAcceptsABatchDatedSlightlyInTheFuture() {
        let response = makeResponse(createdAt: isoTimestamp(secondsAgo: -30))
        XCTAssertTrue(RecommendationsViewModel.isRecoverableBatch(
            response, replacing: [], milestoneId: nil
        ))
    }

    /// Nothing stored means nothing to recover — a user who has never generated.
    func testRejectsAnEmptyBatch() {
        let response = MilestoneRecommendationsResponse(
            recommendations: [],
            count: 0,
            milestoneId: nil,
            briefingText: nil
        )
        XCTAssertFalse(RecommendationsViewModel.isRecoverableBatch(
            response, replacing: [], milestoneId: nil
        ))
    }

    /// An unparseable timestamp must fail closed — showing an unknown-age batch
    /// as "your picks are ready" is worse than showing the error.
    func testRejectsAnUnparseableTimestamp() {
        let response = makeResponse(createdAt: "not a timestamp")
        XCTAssertFalse(RecommendationsViewModel.isRecoverableBatch(
            response, replacing: [], milestoneId: nil
        ))
    }
}

// MARK: - Milestone context

@MainActor
final class RecoveryMilestoneContextTests: XCTestCase {

    private func check(
        batchMilestone: String?,
        requestedMilestone: String?
    ) -> Bool {
        let response = makeResponse(
            createdAt: isoTimestamp(secondsAgo: 25),
            milestoneId: batchMilestone
        )
        return RecommendationsViewModel.isRecoverableBatch(
            response,
            replacing: [],
            milestoneId: requestedMilestone
        )
    }

    func testAcceptsAMatchingMilestone() {
        XCTAssertTrue(check(batchMilestone: "ms-1", requestedMilestone: "ms-1"))
    }

    func testAcceptsAJustBecauseBatchForAJustBecauseRun() {
        XCTAssertTrue(check(batchMilestone: nil, requestedMilestone: nil))
    }

    /// `/latest` serves whatever is newest for the vault, which can be another
    /// surface's batch. Publishing it here would show unrelated picks as this
    /// milestone's — and saving one would file it under the wrong event.
    func testRejectsAJustBecauseBatchForAMilestoneRun() {
        XCTAssertFalse(check(batchMilestone: nil, requestedMilestone: "ms-1"))
    }

    func testRejectsAMilestoneBatchForAJustBecauseRun() {
        XCTAssertFalse(check(batchMilestone: "ms-1", requestedMilestone: nil))
    }

    func testRejectsADifferentMilestonesBatch() {
        XCTAssertFalse(check(batchMilestone: "ms-2", requestedMilestone: "ms-1"))
    }
}

// MARK: - Timestamp parsing

@MainActor
final class RecoveryTimestampParsingTests: XCTestCase {

    /// Supabase timestamps carry fractional seconds; the default
    /// ISO8601DateFormatter rejects them outright.
    func testParsesFractionalSeconds() {
        let parsed = RecommendationsViewModel.parseTimestamp("2026-09-10T12:00:00.123456Z")
        XCTAssertNotNil(parsed)
    }

    /// Older rows have no fractional part — the fallback path.
    func testParsesPlainInternetDateTime() {
        let parsed = RecommendationsViewModel.parseTimestamp("2026-09-10T12:00:00Z")
        XCTAssertNotNil(parsed)
    }

    func testParsesAnOffsetTimezone() {
        let parsed = RecommendationsViewModel.parseTimestamp("2026-09-10T08:00:00-04:00")
        XCTAssertNotNil(parsed)
    }

    func testReturnsNilForGarbage() {
        XCTAssertNil(RecommendationsViewModel.parseTimestamp(""))
        XCTAssertNil(RecommendationsViewModel.parseTimestamp("2026-09-10"))
        XCTAssertNil(RecommendationsViewModel.parseTimestamp("yesterday"))
    }
}

// MARK: - The recovery itself

@MainActor
final class RecoverRecentlyStoredBatchTests: XCTestCase {

    private func makeViewModel(
        _ behavior: StubLatestFetcher.Behavior
    ) -> (RecommendationsViewModel, StubLatestFetcher) {
        let fetcher = StubLatestFetcher(behavior: behavior)
        let viewModel = RecommendationsViewModel(milestoneFetcher: fetcher)
        return (viewModel, fetcher)
    }


    /// The core case: the picks the push announced are published to the screen.
    func testPublishesThisRunsBatch() async {
        let (viewModel, fetcher) = makeViewModel(
            .success(makeResponse(createdAt: isoTimestamp(secondsAgo: 30)))
        )

        let recovered = await viewModel.recoverRecentlyStoredBatch(
            replacing: [], milestoneId: nil
        )

        XCTAssertTrue(recovered)
        XCTAssertEqual(fetcher.latestRequestCount, 1)
        XCTAssertEqual(viewModel.recommendations.count, 3)
        XCTAssertEqual(viewModel.recommendations.first?.title, "Pick 0")
        XCTAssertTrue(viewModel.hasLoadedInitially)
    }

    /// The deck must be reset, or the recovered picks render behind whatever
    /// card state the failed run left on screen.
    func testResetsTheDeck() async {
        let (viewModel, _) = makeViewModel(
            .success(makeResponse(createdAt: isoTimestamp(secondsAgo: 30)))
        )
        let before = viewModel.deckResetToken

        _ = await viewModel.recoverRecentlyStoredBatch(
            replacing: [], milestoneId: nil
        )

        XCTAssertGreaterThan(viewModel.deckResetToken, before)
    }

    /// A just-because batch has no milestone — the case /by-milestone could
    /// never serve, and the whole reason /latest exists.
    func testRecoversAJustBecauseBatchWithNoMilestone() async {
        let (viewModel, _) = makeViewModel(
            .success(makeResponse(createdAt: isoTimestamp(secondsAgo: 30), milestoneId: nil))
        )

        let recovered = await viewModel.recoverRecentlyStoredBatch(
            replacing: [], milestoneId: nil
        )

        XCTAssertTrue(recovered)
        XCTAssertEqual(viewModel.recommendations.count, 3)
    }

    /// A batch older than the window belongs to a previous session.
    func testDoesNotPublishAStaleBatch() async {
        let stale = RecommendationsViewModel.recoverableBatchWindow + 60
        let (viewModel, _) = makeViewModel(
            .success(makeResponse(createdAt: isoTimestamp(secondsAgo: stale)))
        )

        let recovered = await viewModel.recoverRecentlyStoredBatch(
            replacing: [], milestoneId: nil
        )

        XCTAssertFalse(recovered)
        XCTAssertTrue(viewModel.recommendations.isEmpty)
        XCTAssertFalse(viewModel.hasLoadedInitially)
    }

    /// The failed-re-roll case, end to end: the batch on screen is exactly what
    /// `/latest` returns, and recovery must leave the error standing rather
    /// than republish the same three cards.
    func testDoesNotRepublishTheBatchItWasReplacing() async {
        let response = makeResponse(createdAt: isoTimestamp(secondsAgo: 25))
        let (viewModel, _) = makeViewModel(.success(response))

        let recovered = await viewModel.recoverRecentlyStoredBatch(
            replacing: response.recommendations.map(\.id),
            milestoneId: nil
        )

        XCTAssertFalse(recovered)
        XCTAssertTrue(viewModel.recommendations.isEmpty)
        XCTAssertFalse(viewModel.hasLoadedInitially)
    }

    /// Another surface's batch must not be published as this milestone's.
    func testDoesNotPublishAMismatchedMilestonesBatch() async {
        let (viewModel, _) = makeViewModel(
            .success(makeResponse(createdAt: isoTimestamp(secondsAgo: 30), milestoneId: nil))
        )

        let recovered = await viewModel.recoverRecentlyStoredBatch(
            replacing: [], milestoneId: "ms-1"
        )

        XCTAssertFalse(recovered)
        XCTAssertTrue(viewModel.recommendations.isEmpty)
    }

    func testDoesNotPublishAnEmptyBatch() async {
        let (viewModel, _) = makeViewModel(.success(
            MilestoneRecommendationsResponse(
                recommendations: [], count: 0, milestoneId: nil, briefingText: nil
            )
        ))

        let recovered = await viewModel.recoverRecentlyStoredBatch(
            replacing: [], milestoneId: nil
        )

        XCTAssertFalse(recovered)
        XCTAssertTrue(viewModel.recommendations.isEmpty)
    }

    /// `/latest` never carries a briefing, so a recovery on a milestone surface
    /// must leave the briefing card alone rather than blanking it.
    func testDoesNotEraseAnExistingBriefing() async {
        let (viewModel, _) = makeViewModel(
            .success(makeResponse(createdAt: isoTimestamp(secondsAgo: 30), milestoneId: "ms-1"))
        )
        viewModel.briefingText = "Her birthday is next week — she mentioned pottery."

        let recovered = await viewModel.recoverRecentlyStoredBatch(
            replacing: [], milestoneId: "ms-1"
        )

        XCTAssertTrue(recovered)
        XCTAssertEqual(
            viewModel.briefingText,
            "Her birthday is next week — she mentioned pottery."
        )
    }

    /// But a briefing that *is* returned still rides along to the screen.
    func testAdoptsAReturnedBriefing() async {
        let (viewModel, _) = makeViewModel(
            .success(makeResponse(
                createdAt: isoTimestamp(secondsAgo: 30),
                milestoneId: "ms-1",
                briefingText: "She mentioned pottery."
            ))
        )

        _ = await viewModel.recoverRecentlyStoredBatch(
            replacing: [], milestoneId: "ms-1"
        )

        XCTAssertEqual(viewModel.briefingText, "She mentioned pottery.")
    }

    /// Recovery is a best-effort second chance layered over a request that
    /// already failed. If it fails too, the user still sees the original
    /// error — it must never throw or replace one failure with another.
    func testAFailedLookupIsSwallowed() async {
        let (viewModel, _) = makeViewModel(
            .failure(NotificationHistoryServiceError.networkError("offline"))
        )

        let recovered = await viewModel.recoverRecentlyStoredBatch(
            replacing: [], milestoneId: nil
        )

        XCTAssertFalse(recovered)
        XCTAssertTrue(viewModel.recommendations.isEmpty)
    }

    /// An unauthenticated recovery attempt fails quietly for the same reason.
    func testAnAuthFailureIsSwallowed() async {
        let (viewModel, _) = makeViewModel(
            .failure(NotificationHistoryServiceError.noAuthSession)
        )

        let recovered = await viewModel.recoverRecentlyStoredBatch(
            replacing: [], milestoneId: nil
        )

        XCTAssertFalse(recovered)
    }

    /// 404 (no vault) is a real answer, not a recoverable state.
    func testANoVaultResponseIsSwallowed() async {
        let (viewModel, _) = makeViewModel(
            .failure(NotificationHistoryServiceError.serverError(
                statusCode: 404, message: "No vault found."
            ))
        )

        let recovered = await viewModel.recoverRecentlyStoredBatch(
            replacing: [], milestoneId: nil
        )

        XCTAssertFalse(recovered)
    }

    /// Recovered picks are mapped through the same path as the push
    /// tap-through, so they are tagged and sanitized identically.
    func testRecoveredItemsAreMappedLikeTheTapThrough() async {
        let (viewModel, _) = makeViewModel(
            .success(makeResponse(itemCount: 1, createdAt: isoTimestamp(secondsAgo: 30)))
        )

        _ = await viewModel.recoverRecentlyStoredBatch(
            replacing: [], milestoneId: nil
        )

        let item = viewModel.recommendations.first
        XCTAssertEqual(item?.source, "milestone_pregenerated")
        XCTAssertEqual(item?.merchantName, "Clay Co.")
        XCTAssertEqual(item?.priceCents, 4200)
    }
}
