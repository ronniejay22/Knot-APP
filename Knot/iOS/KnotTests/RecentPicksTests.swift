//
//  RecentPicksTests.swift
//  KnotTests
//
//  Step 19.62: The Journal's "Recent picks" — stored recommendation batches
//  stay reopenable for 7 days, then expire.
//
//  Covers the DTO contract, the pure label / expiry helpers on
//  `ForYouViewModel`, the best-effort batch load through the
//  `RecentRecommendationsFetching` seam, the seeded view model a reopen pushes
//  with, and render-without-crash smoke tests for the section and row. The
//  suite does no view introspection; the PR screenshot's UI test is what proves
//  a row tap actually reaches the cards.
//

import SwiftData
import SwiftUI
import XCTest
@testable import Knot

// MARK: - Fixtures

/// ISO 8601 with fractional seconds — the shape Supabase actually returns.
private func isoTimestamp(for date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: date)
}

/// A fixed instant so calendar-day arithmetic is deterministic: 14:00 UTC,
/// far from any midnight in the calendars the tests use.
private let fixedNow: Date = {
    var components = DateComponents()
    components.year = 2026
    components.month = 9
    components.day = 13
    components.hour = 14
    components.timeZone = TimeZone(identifier: "UTC")
    return Calendar(identifier: .gregorian).date(from: components)!
}()

private let utcCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}()

private func makeItem(
    id: String = "rec-1",
    type: String = "gift",
    title: String = "Hand-thrown Mug"
) -> MilestoneRecommendationItemResponse {
    MilestoneRecommendationItemResponse(
        id: id,
        recommendationType: type,
        title: title,
        description: "A speckled stoneware mug.",
        externalUrl: "https://example.com/mug",
        priceCents: 4200,
        merchantName: "Clay Co.",
        imageUrl: nil,
        createdAt: isoTimestamp(for: fixedNow),
        personalizationNote: "She has been taking pottery classes.",
        isIdea: type == "idea",
        contentSections: nil,
        headline: nil
    )
}

private func makeBatch(
    id: String = "batch-1",
    milestoneId: String? = nil,
    generatedAt: Date = fixedNow.addingTimeInterval(-2 * 86_400),
    expiresAt: Date = fixedNow.addingTimeInterval(5 * 86_400),
    itemCount: Int = 3
) -> RecentRecommendationBatchResponse {
    RecentRecommendationBatchResponse(
        id: id,
        milestoneId: milestoneId,
        generatedAt: isoTimestamp(for: generatedAt),
        expiresAt: isoTimestamp(for: expiresAt),
        recommendations: (0..<itemCount).map { makeItem(id: "\(id)-rec-\($0)", title: "Pick \($0)") }
    )
}

private func makeMilestone(id: String, name: String) -> MilestoneItemResponse {
    MilestoneItemResponse(
        id: id,
        milestoneType: "holiday",
        milestoneName: name,
        milestoneDate: "2000-12-25",
        recurrence: "yearly",
        budgetTier: "major_milestone",
        daysUntil: 100,
        createdAt: "2026-07-04",
        occasionCategory: "christmas"
    )
}

/// Fetcher seam that serves a canned recent-batches response.
@MainActor
private final class StubRecentFetcher: RecentRecommendationsFetching {
    enum Behavior {
        case success(RecentRecommendationsResponse)
        case failure(Error)
    }

    var behavior: Behavior
    private(set) var requestCount = 0

    init(_ behavior: Behavior) {
        self.behavior = behavior
    }

    func fetchRecentRecommendations() async throws -> RecentRecommendationsResponse {
        requestCount += 1
        switch behavior {
        case .success(let response): return response
        case .failure(let error): throw error
        }
    }
}

private func response(_ batches: [RecentRecommendationBatchResponse]) -> RecentRecommendationsResponse {
    RecentRecommendationsResponse(batches: batches, count: batches.count, windowDays: 7)
}

/// Fetcher that suspends until `release()` — for proving what the Journal
/// does *while* the recent read is still in flight.
@MainActor
private final class GatedRecentFetcher: RecentRecommendationsFetching {
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var entered = false
    private(set) var released = false

    func fetchRecentRecommendations() async throws -> RecentRecommendationsResponse {
        entered = true
        if !released {
            await withCheckedContinuation { continuation = $0 }
        }
        return response([makeBatch()])
    }

    func release() {
        released = true
        continuation?.resume()
        continuation = nil
    }
}

// MARK: - DTO decoding

final class RecentPicksDTOTests: XCTestCase {

    /// The wire shape is the backend's snake_case; `batch_id` lands on `id`.
    func testDecodesRecentResponse() throws {
        let json = """
        {
          "batches": [
            {
              "batch_id": "1f9c7f5e-0000-4000-8000-000000000001",
              "milestone_id": "ms-123",
              "generated_at": "2026-09-11T14:02:11.123456+00:00",
              "expires_at": "2026-09-18T14:02:11.123456+00:00",
              "recommendations": [
                {
                  "id": "rec-1",
                  "recommendation_type": "gift",
                  "title": "Hand-thrown Mug",
                  "description": "A speckled stoneware mug.",
                  "external_url": "https://example.com/mug",
                  "price_cents": 4200,
                  "merchant_name": "Clay Co.",
                  "image_url": "https://example.com/mug.jpg",
                  "created_at": "2026-09-11T14:02:11.123456+00:00",
                  "personalization_note": "She loves pottery.",
                  "is_idea": false,
                  "content_sections": null
                }
              ]
            },
            {
              "batch_id": "1f9c7f5e-0000-4000-8000-000000000002",
              "milestone_id": null,
              "generated_at": "2026-09-10T09:00:00+00:00",
              "expires_at": "2026-09-17T09:00:00+00:00",
              "recommendations": []
            }
          ],
          "count": 2,
          "window_days": 7
        }
        """

        let decoded = try JSONDecoder().decode(RecentRecommendationsResponse.self, from: Data(json.utf8))

        XCTAssertEqual(decoded.count, 2)
        XCTAssertEqual(decoded.windowDays, 7)
        XCTAssertEqual(decoded.batches.count, 2)
        XCTAssertEqual(decoded.batches[0].id, "1f9c7f5e-0000-4000-8000-000000000001")
        XCTAssertEqual(decoded.batches[0].milestoneId, "ms-123")
        XCTAssertEqual(decoded.batches[0].generatedAt, "2026-09-11T14:02:11.123456+00:00")
        XCTAssertEqual(decoded.batches[0].expiresAt, "2026-09-18T14:02:11.123456+00:00")
        XCTAssertEqual(decoded.batches[0].recommendations.first?.title, "Hand-thrown Mug")
        XCTAssertNil(decoded.batches[1].milestoneId)
        XCTAssertTrue(decoded.batches[1].recommendations.isEmpty)
    }

    func testBatchIsIdentifiableByBatchId() {
        let batch = makeBatch(id: "batch-xyz")
        XCTAssertEqual(batch.id, "batch-xyz")
    }
}

// MARK: - Expiry & label helpers

@MainActor
final class RecentPicksExpiryHelperTests: XCTestCase {

    func testIsExpiredBeforeAtAndAfterExpiry() {
        let future = isoTimestamp(for: fixedNow.addingTimeInterval(60))
        let exact = isoTimestamp(for: fixedNow)
        let past = isoTimestamp(for: fixedNow.addingTimeInterval(-60))

        XCTAssertFalse(ForYouViewModel.isExpired(expiresAt: future, now: fixedNow))
        XCTAssertTrue(ForYouViewModel.isExpired(expiresAt: exact, now: fixedNow), "expiry instant counts as expired")
        XCTAssertTrue(ForYouViewModel.isExpired(expiresAt: past, now: fixedNow))
    }

    /// A batch with no usable expiry must never sit on the Journal forever.
    func testUnparseableExpiryCountsAsExpired() {
        XCTAssertTrue(ForYouViewModel.isExpired(expiresAt: "not-a-timestamp", now: fixedNow))
    }

    func testIsExpiringSoonIsUnder24Hours() {
        let in23h = isoTimestamp(for: fixedNow.addingTimeInterval(23 * 3_600))
        let in25h = isoTimestamp(for: fixedNow.addingTimeInterval(25 * 3_600))
        let past = isoTimestamp(for: fixedNow.addingTimeInterval(-3_600))

        XCTAssertTrue(ForYouViewModel.isExpiringSoon(expiresAt: in23h, now: fixedNow))
        XCTAssertFalse(ForYouViewModel.isExpiringSoon(expiresAt: in25h, now: fixedNow))
        XCTAssertFalse(ForYouViewModel.isExpiringSoon(expiresAt: past, now: fixedNow), "already expired is not 'soon'")
        XCTAssertFalse(ForYouViewModel.isExpiringSoon(expiresAt: "garbage", now: fixedNow))
    }

    /// Calendar days, not 24-hour spans: a set generated minutes ago with a
    /// 7-day window must read "7 days", not "6".
    func testExpiryLabelCountsCalendarDays() {
        func label(daysAhead: Double, hourOffset: Double = 0) -> String {
            let expiry = fixedNow.addingTimeInterval(daysAhead * 86_400 + hourOffset * 3_600)
            return ForYouViewModel.expiryLabel(
                expiresAt: isoTimestamp(for: expiry), now: fixedNow, calendar: utcCalendar
            )
        }

        XCTAssertEqual(label(daysAhead: 7, hourOffset: -0.1), "Expires in 7 days")
        XCTAssertEqual(label(daysAhead: 2), "Expires in 2 days")
        XCTAssertEqual(label(daysAhead: 1), "Expires tomorrow")
        XCTAssertEqual(label(daysAhead: 0, hourOffset: 3), "Expires today")
        XCTAssertEqual(label(daysAhead: -1), "Expired")
        XCTAssertEqual(
            ForYouViewModel.expiryLabel(expiresAt: "garbage", now: fixedNow, calendar: utcCalendar),
            "Expired"
        )
    }

    func testGeneratedLabelCountsCalendarDays() {
        func label(daysAgo: Double, hourOffset: Double = 0) -> String {
            let generated = fixedNow.addingTimeInterval(-daysAgo * 86_400 + hourOffset * 3_600)
            return ForYouViewModel.generatedLabel(
                generatedAt: isoTimestamp(for: generated), now: fixedNow, calendar: utcCalendar
            )
        }

        XCTAssertEqual(label(daysAgo: 0, hourOffset: -2), "Today")
        XCTAssertEqual(label(daysAgo: 1), "Yesterday")
        XCTAssertEqual(label(daysAgo: 4), "4 days ago")
        XCTAssertEqual(
            ForYouViewModel.generatedLabel(generatedAt: "garbage", now: fixedNow, calendar: utcCalendar),
            "Recently"
        )
    }

    func testPicksCountLabel() {
        XCTAssertEqual(ForYouViewModel.picksCountLabel(1), "1 pick")
        XCTAssertEqual(ForYouViewModel.picksCountLabel(3), "3 picks")
    }
}

// MARK: - View model

@MainActor
final class RecentPicksViewModelTests: XCTestCase {

    func testLoadRecentBatchesPopulatesFromTheFetcher() async {
        let fetcher = StubRecentFetcher(.success(response([makeBatch(id: "b1"), makeBatch(id: "b2")])))
        let vm = ForYouViewModel(recentFetcher: fetcher)

        await vm.loadRecentBatches()

        XCTAssertEqual(vm.recentBatches.map(\.id), ["b1", "b2"])
        XCTAssertEqual(fetcher.requestCount, 1)
    }

    /// The hint copy reads the served window, so the backend can change it
    /// without the client contradicting its own expiry badges.
    func testLoadRecentBatchesAdoptsTheServedWindow() async {
        let served = RecentRecommendationsResponse(batches: [makeBatch()], count: 1, windowDays: 10)
        let vm = ForYouViewModel(recentFetcher: StubRecentFetcher(.success(served)))
        XCTAssertEqual(vm.recentWindowDays, 7, "default until the first read")

        await vm.loadRecentBatches()

        XCTAssertEqual(vm.recentWindowDays, 10)
    }

    /// The section is secondary to the milestone feed: a failed read keeps
    /// what was showing and never raises the Journal's error alert.
    func testLoadFailureKeepsPreviousBatchesAndNoError() async {
        let fetcher = StubRecentFetcher(.success(response([makeBatch(id: "b1")])))
        let vm = ForYouViewModel(recentFetcher: fetcher)
        await vm.loadRecentBatches()

        fetcher.behavior = .failure(NotificationHistoryServiceError.networkError("offline"))
        await vm.loadRecentBatches()

        XCTAssertEqual(vm.recentBatches.map(\.id), ["b1"])
        XCTAssertNil(vm.errorMessage)
    }

    /// The milestone feed's spinner must not wait on `/recent`: `isLoading`
    /// clears once milestones and partner name are in, while the recent read
    /// is still suspended.
    func testLoadDataClearsIsLoadingBeforeTheRecentFetchFinishes() async {
        let fetcher = GatedRecentFetcher()
        let vm = ForYouViewModel(recentFetcher: fetcher)

        let load = Task { await vm.loadData() }

        // Wait for the recent read to be in flight, then for the spinner to
        // clear while it still is. Before the fix `isLoading` stayed true
        // until the fetcher returned, so this loop ran out its deadline.
        let deadline = ContinuousClock.now + .seconds(20)
        while !(fetcher.entered && !vm.isLoading), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }

        XCTAssertTrue(fetcher.entered)
        XCTAssertFalse(vm.isLoading, "isLoading stayed true while the recent read was still in flight")
        XCTAssertFalse(fetcher.released)
        XCTAssertTrue(vm.recentBatches.isEmpty, "no batches can have landed yet")

        fetcher.release()
        await load.value
        XCTAssertEqual(vm.recentBatches.count, 1)
    }

    func testRefreshJournalHitsTheFetcher() async {
        let fetcher = StubRecentFetcher(.success(response([])))
        let vm = ForYouViewModel(recentFetcher: fetcher)

        await vm.refreshJournal()

        XCTAssertEqual(fetcher.requestCount, 1)
    }

    func testVisibleBatchesDropExpiredAndPreserveOrder() async {
        let live = makeBatch(id: "live", expiresAt: Date().addingTimeInterval(3 * 86_400))
        let expired = makeBatch(id: "expired", expiresAt: Date().addingTimeInterval(-60))
        let alsoLive = makeBatch(id: "also-live", expiresAt: Date().addingTimeInterval(86_400))
        let fetcher = StubRecentFetcher(.success(response([live, expired, alsoLive])))
        let vm = ForYouViewModel(recentFetcher: fetcher)

        await vm.loadRecentBatches()

        XCTAssertEqual(vm.visibleRecentBatches.map(\.id), ["live", "also-live"])
    }

    func testOccasionLabelResolution() {
        let vm = ForYouViewModel(recentFetcher: StubRecentFetcher(.success(response([]))))
        vm.milestones = [makeMilestone(id: "ms-christmas", name: "Christmas")]

        XCTAssertEqual(vm.occasionLabel(for: makeBatch(milestoneId: nil)), "Just because")
        XCTAssertEqual(vm.occasionLabel(for: makeBatch(milestoneId: "ms-christmas")), "Christmas")
        XCTAssertEqual(vm.occasionLabel(for: makeBatch(milestoneId: "ms-gone")), "Special occasion")
    }

    func testMilestoneLookup() {
        let vm = ForYouViewModel(recentFetcher: StubRecentFetcher(.success(response([]))))
        let christmas = makeMilestone(id: "ms-christmas", name: "Christmas")
        vm.milestones = [christmas]

        XCTAssertEqual(vm.milestone(for: makeBatch(milestoneId: "ms-christmas"))?.id, christmas.id)
        XCTAssertNil(vm.milestone(for: makeBatch(milestoneId: nil)))
        XCTAssertNil(vm.milestone(for: makeBatch(milestoneId: "ms-gone")))
    }

    /// The reopen push must show cards at once and run no pipeline —
    /// `hasLoadedInitially` is what short-circuits `RecommendationsView`'s
    /// `.task`, and `partnerName` is what stops `configure` fetching the vault.
    func testSeededRecommendationsViewModel() {
        let batch = makeBatch(itemCount: 3)

        let seeded = ForYouViewModel.seededRecommendationsViewModel(for: batch, partnerName: "Jas")

        XCTAssertTrue(seeded.hasLoadedInitially)
        XCTAssertEqual(seeded.recommendations.count, 3)
        XCTAssertEqual(seeded.recommendations.map(\.title), ["Pick 0", "Pick 1", "Pick 2"])
        XCTAssertEqual(seeded.partnerName, "Jas")
        XCTAssertFalse(seeded.isLoading)
    }
}

// MARK: - Rendering

@MainActor
final class RecentPicksRenderingTests: XCTestCase {

    func testSectionRendersEmpty() {
        let view = RecentPicksSection(batches: [], occasionLabel: { _ in "" }, onOpen: { _ in })
        let host = UIHostingController(rootView: view)
        XCTAssertNotNil(host.view)
    }

    func testSectionRendersPopulated() {
        let view = RecentPicksSection(
            batches: [makeBatch(id: "b1", milestoneId: "ms-1"), makeBatch(id: "b2")],
            occasionLabel: { $0.milestoneId == nil ? "Just because" : "Christmas" },
            onOpen: { _ in }
        )
        let host = UIHostingController(rootView: view)
        XCTAssertNotNil(host.view)
    }

    func testRowRendersExpiringSoonVariant() {
        let batch = makeBatch(expiresAt: fixedNow.addingTimeInterval(3 * 3_600))
        let view = RecentPickRow(batch: batch, occasionLabel: "Just because", onOpen: {}, now: fixedNow)
        let host = UIHostingController(rootView: view)
        XCTAssertNotNil(host.view)
    }

    func testRowRendersWithFewerThanThreePicks() {
        let view = RecentPickRow(batch: makeBatch(itemCount: 1), occasionLabel: "Christmas", onOpen: {})
        let host = UIHostingController(rootView: view)
        XCTAssertNotNil(host.view)
    }

    func testRowTapForwardsToOnOpen() {
        var opened = false
        let row = RecentPickRow(batch: makeBatch(), occasionLabel: "Christmas", onOpen: { opened = true })

        row.rowTapped(delay: .zero)

        XCTAssertTrue(opened)
    }

    /// The default path defers the open past the press hold so the surface's
    /// spring-back is seen; it must not fire synchronously, and must fire.
    func testRowTapDefersOpenPastThePressHold() async {
        let expectation = expectation(description: "opens after the hold")
        let row = RecentPickRow(batch: makeBatch(), occasionLabel: "Christmas", onOpen: { expectation.fulfill() })

        row.rowTapped()

        await fulfillment(of: [expectation], timeout: 2)
    }

    func testExpiryHintReadsTheServedWindow() {
        XCTAssertEqual(
            RecentPicksSection.expiryHint(windowDays: 7),
            "Picks disappear after 7 days — save the ones you want to keep."
        )
        XCTAssertEqual(
            RecentPicksSection.expiryHint(windowDays: 1),
            "Picks disappear after a day — save the ones you want to keep."
        )
    }

    func testSectionAndRowAccessibilityLabels() {
        XCTAssertEqual(RecentPicksSection.accessibilityLabel(count: 1), "Recent picks, 1 set")
        XCTAssertEqual(RecentPicksSection.accessibilityLabel(count: 3), "Recent picks, 3 sets")
        XCTAssertEqual(
            RecentPickRow.accessibilityLabel(
                occasion: "Christmas", picksCount: 3, generatedLabel: "2 days ago", expiryLabel: "Expires in 5 days"
            ),
            "Christmas, 3 picks, generated 2 days ago, expires in 5 days"
        )
        XCTAssertEqual(
            RecentPickRow.accessibilityLabel(
                occasion: "Just because", picksCount: 1, generatedLabel: "Today", expiryLabel: "Expires today"
            ),
            "Just because, 1 pick, generated today, expires today"
        )
    }

    /// The reopen push: a seeded VM with `preferPregenerated: true` hosts
    /// without crashing and with the cards already present.
    func testRecommendationsViewHostsWithSeededViewModel() throws {
        let seeded = ForYouViewModel.seededRecommendationsViewModel(for: makeBatch(), partnerName: "Jas")
        let container = try ModelContainer(
            for: SavedRecommendation.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let view = RecommendationsView(
            milestoneId: nil,
            milestoneContext: nil,
            preferPregenerated: true,
            viewModel: seeded
        )
        .environment(AuthViewModel())
        .modelContainer(container)

        let host = UIHostingController(rootView: view)
        XCTAssertNotNil(host.view)
        XCTAssertEqual(seeded.recommendations.count, 3)
        XCTAssertTrue(seeded.hasLoadedInitially)
    }

    func testDestinationCarriesSeededViewModel() {
        let seeded = ForYouViewModel.seededRecommendationsViewModel(for: makeBatch(), partnerName: "Jas")
        let generating = RecommendationDestination(milestoneId: nil, context: nil)
        let reopening = RecommendationDestination(milestoneId: nil, context: nil, seededViewModel: seeded)

        XCTAssertNil(generating.seededViewModel)
        XCTAssertTrue(reopening.seededViewModel === seeded)
        XCTAssertNotEqual(generating, reopening, "identity is the destination's own id, as before")
    }
}
