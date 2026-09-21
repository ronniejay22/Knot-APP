//
//  RecentPicksSheetTests.swift
//  KnotTests
//
//  Step 19.63 — the Journal's handling of an untapped milestone push: how
//  `ForYouViewModel` finds, keeps and retires the alert, and that the sheet
//  behind it renders in each of its states.
//
//  The view model's three services are driven through their seams
//  (`MilestoneListing`, `VaultReading`, `NotificationHistoryReading`), so
//  nothing here reaches a network or a session.
//

import XCTest
import SwiftUI
import SwiftData
@testable import Knot

// MARK: - Fixtures

private func isoTimestamp(secondsAgo seconds: TimeInterval) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.string(from: Date().addingTimeInterval(-seconds))
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
    sentAt: String = isoTimestamp(secondsAgo: 3600),
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
        status: "sent",
        sentAt: sentAt,
        viewedAt: viewedAt,
        createdAt: sentAt,
        recommendationsCount: 3
    )
}

private struct StubError: LocalizedError {
    var errorDescription: String? { "Network unavailable." }
}

@MainActor
private final class StubMilestoneLister: MilestoneListing {
    var result: Result<[MilestoneItemResponse], Error>

    init(_ milestones: [MilestoneItemResponse]) {
        result = .success(milestones)
    }

    func listMilestones() async throws -> MilestoneListResponse {
        let milestones = try result.get()
        return MilestoneListResponse(milestones: milestones, count: milestones.count)
    }
}

/// Always fails: `loadPartnerName` is best-effort and keeps its default, which
/// is all these tests need from it.
@MainActor
private struct FailingVaultReader: VaultReading {
    func getVault() async throws -> VaultGetResponse { throw StubError() }
}

@MainActor
private final class StubHistoryReader: NotificationHistoryReading {
    var result: Result<[NotificationHistoryItemResponse], Error>
    private(set) var viewedIds: [String] = []
    /// Ids some *other* surface (the push tap-through cover) has marked
    /// viewed this session — the production registry, seeded per test.
    var locallyViewedNotificationIds: Set<String> = []

    init(_ rows: [NotificationHistoryItemResponse]) {
        result = .success(rows)
    }

    func fetchHistory(limit: Int, offset: Int) async throws -> NotificationHistoryResponse {
        let rows = try result.get()
        return NotificationHistoryResponse(notifications: rows, total: rows.count)
    }

    func markViewed(notificationId: String) async {
        viewedIds.append(notificationId)
    }
}

@MainActor
private func makeViewModel(
    milestones: [MilestoneItemResponse] = [makeMilestone()],
    history: [NotificationHistoryItemResponse] = [makeRow()]
) -> (ForYouViewModel, StubMilestoneLister, StubHistoryReader) {
    let lister = StubMilestoneLister(milestones)
    let reader = StubHistoryReader(history)
    let viewModel = ForYouViewModel(
        milestoneService: lister,
        vaultService: FailingVaultReader(),
        historyReader: reader
    )
    return (viewModel, lister, reader)
}

// MARK: - View model

@MainActor
final class ForYouPendingPicksViewModelTests: XCTestCase {

    func testLoadDataAnnouncesAnUntappedPush() async {
        let (viewModel, _, _) = makeViewModel()

        await viewModel.loadData()

        XCTAssertEqual(viewModel.pendingPicksAlert?.id, "n1")
        XCTAssertEqual(viewModel.milestones.count, 1)
        XCTAssertTrue(viewModel.hasLoadedInitially)
        XCTAssertFalse(viewModel.isLoading)
    }

    func testNoUntappedPushMeansNoAlert() async {
        let (viewModel, _, _) = makeViewModel(history: [makeRow(viewedAt: isoTimestamp(secondsAgo: 60))])

        await viewModel.loadData()

        XCTAssertNil(viewModel.pendingPicksAlert)
    }

    /// `/history` being down must not degrade the Journal: the milestones
    /// still load and no error is shown.
    func testAFailedHistoryReadKeepsTheJournalWorking() async {
        let (viewModel, _, reader) = makeViewModel()
        reader.result = .failure(StubError())

        await viewModel.loadData()

        XCTAssertEqual(viewModel.milestones.count, 1)
        XCTAssertNil(viewModel.errorMessage, "A history failure is never surfaced")
        XCTAssertNil(viewModel.pendingPicksAlert)
        XCTAssertTrue(viewModel.hasLoadedInitially)
        XCTAssertFalse(viewModel.isLoading)
    }

    /// Tapping a push from the background makes the tap-through cover PATCH
    /// viewed at the same moment the Journal's foreground refresh GETs the
    /// history. If the GET wins, the row still reads unviewed — and the push
    /// the user just opened must not be announced. The service records every
    /// id it was asked to mark viewed before its PATCH goes out; the Journal
    /// honours that registry. (Review finding, Step 19.63.)
    func testAPushAlreadyMarkedViewedByAnotherSurfaceIsNotAnnounced() async {
        let (viewModel, _, reader) = makeViewModel()
        reader.locallyViewedNotificationIds = ["n1"]

        await viewModel.loadData()

        XCTAssertNil(viewModel.pendingPicksAlert)
    }

    /// The real service records the id synchronously, before its first await
    /// (the token lookup), and its `NotificationHistoryReading` conformance
    /// reads the same registry. The task is cancelled rather than awaited so
    /// the test never waits on a session lookup or a socket.
    func testTheServiceRecordsAnIdBeforeItsPatch() async {
        NotificationHistoryService.locallyViewedNotificationIds.remove("service-test-id")
        let service = NotificationHistoryService(baseURL: "http://127.0.0.1:1")

        let marking = Task { await service.markViewed(notificationId: "service-test-id") }
        await Task.yield()

        XCTAssertTrue(NotificationHistoryService.locallyViewedNotificationIds.contains("service-test-id"))
        XCTAssertTrue(service.locallyViewedNotificationIds.contains("service-test-id"))

        marking.cancel()
        NotificationHistoryService.locallyViewedNotificationIds.remove("service-test-id")
    }

    /// A refresh whose history read fails keeps the previous answer rather
    /// than blanking the alert.
    func testAFailedRefreshKeepsTheExistingAlert() async {
        let (viewModel, _, reader) = makeViewModel()
        await viewModel.loadData()
        XCTAssertNotNil(viewModel.pendingPicksAlert)

        reader.result = .failure(StubError())
        await viewModel.refresh()

        XCTAssertEqual(viewModel.pendingPicksAlert?.id, "n1")
    }

    // MARK: Acknowledge

    func testAcknowledgeMarksEveryPushViewedAndClearsTheAlert() async {
        let rows = [
            makeRow(id: "n14", sentAt: isoTimestamp(secondsAgo: 7 * 86_400), daysBefore: 14),
            makeRow(id: "n7", sentAt: isoTimestamp(secondsAgo: 3600), daysBefore: 7),
        ]
        let (viewModel, _, reader) = makeViewModel(milestones: [makeMilestone(daysUntil: 7)], history: rows)
        await viewModel.loadData()
        guard let alert = viewModel.pendingPicksAlert else { return XCTFail("No alert to acknowledge") }

        await viewModel.acknowledge(alert)

        XCTAssertNil(viewModel.pendingPicksAlert)
        XCTAssertEqual(reader.viewedIds, ["n7", "n14"], "Both pushes are retired, newest first")
    }

    /// Two events with untapped pushes: dismissing the first announces the
    /// second at once, not on the next refresh. (Review finding, Step 19.63.)
    func testAcknowledgingOneAlertAnnouncesTheNextMilestonesPush() async {
        let rows = [
            makeRow(id: "older", milestoneId: "m1", sentAt: isoTimestamp(secondsAgo: 2 * 86_400)),
            makeRow(id: "newer", milestoneId: "m2", sentAt: isoTimestamp(secondsAgo: 3600)),
        ]
        let (viewModel, _, reader) = makeViewModel(
            milestones: [makeMilestone(id: "m1"), makeMilestone(id: "m2", name: "Anniversary")],
            history: rows
        )
        await viewModel.loadData()
        guard let first = viewModel.pendingPicksAlert else { return XCTFail("No alert") }
        XCTAssertEqual(first.id, "newer")

        await viewModel.acknowledge(first)

        XCTAssertEqual(viewModel.pendingPicksAlert?.id, "older", "The other event's push is next in line")
        XCTAssertEqual(reader.viewedIds, ["newer"], "Only the acknowledged push was marked viewed")
    }

    /// The mark-viewed PATCH is fire-and-forget; a refresh that still sees the
    /// row unviewed (racing it, or after it failed) must not bring the alert back.
    func testARefreshAfterAcknowledgeDoesNotResurrectTheAlert() async {
        let (viewModel, _, _) = makeViewModel()
        await viewModel.loadData()
        guard let alert = viewModel.pendingPicksAlert else { return XCTFail("No alert") }

        await viewModel.acknowledge(alert)
        await viewModel.refresh()

        XCTAssertNil(viewModel.pendingPicksAlert)
    }

    /// A newer push for the same event is a new alert; acknowledging the stale
    /// one leaves it in place.
    func testANewerPushReplacesTheAlertAndAStaleAcknowledgeLeavesIt() async {
        let (viewModel, _, reader) = makeViewModel(
            milestones: [makeMilestone(daysUntil: 7)],
            history: [makeRow(id: "n14", sentAt: isoTimestamp(secondsAgo: 7 * 86_400), daysBefore: 14)]
        )
        await viewModel.loadData()
        guard let stale = viewModel.pendingPicksAlert else { return XCTFail("No alert") }
        XCTAssertEqual(stale.id, "n14")

        reader.result = .success([
            makeRow(id: "n14", sentAt: isoTimestamp(secondsAgo: 7 * 86_400), daysBefore: 14),
            makeRow(id: "n7", sentAt: isoTimestamp(secondsAgo: 3600), daysBefore: 7),
        ])
        await viewModel.refresh()
        XCTAssertEqual(viewModel.pendingPicksAlert?.id, "n7")
        XCTAssertEqual(viewModel.pendingPicksAlert?.notificationIds, ["n7", "n14"])

        await viewModel.acknowledge(stale)

        XCTAssertEqual(viewModel.pendingPicksAlert?.id, "n7", "Acknowledging a replaced alert leaves the current one")
        XCTAssertEqual(reader.viewedIds, ["n14"])
    }

    // MARK: Refresh paths

    func testRefreshOnForegroundIsANoOpBeforeTheFirstLoad() async {
        let (viewModel, _, _) = makeViewModel()

        await viewModel.refreshOnForeground()

        XCTAssertNil(viewModel.pendingPicksAlert)
        XCTAssertFalse(viewModel.hasLoadedInitially)
    }

    func testRefreshOnForegroundPicksUpAPushThatArrivedWhileAway() async {
        let (viewModel, _, reader) = makeViewModel(history: [])
        await viewModel.loadData()
        XCTAssertNil(viewModel.pendingPicksAlert)

        reader.result = .success([makeRow()])
        await viewModel.refreshOnForeground()

        XCTAssertEqual(viewModel.pendingPicksAlert?.id, "n1")
    }

    /// A milestones-only reload re-runs the selection against the stored
    /// history rows, so an event moved out of its push window drops the alert
    /// without a second history read.
    func testRefreshMilestonesReEvaluatesUpcomingWithTheStoredHistory() async {
        let (viewModel, lister, _) = makeViewModel()
        await viewModel.loadData()
        XCTAssertNotNil(viewModel.pendingPicksAlert)

        lister.result = .success([makeMilestone(daysUntil: 30)])
        await viewModel.refreshMilestones()

        XCTAssertNil(viewModel.pendingPicksAlert)
    }
}

// MARK: - The sheet

@MainActor
private func makeContext() throws -> ModelContext {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(for: SavedRecommendation.self, configurations: config)
    return ModelContext(container)
}

@MainActor
private func makeAlert() -> PendingPicksAlert {
    PendingPicksAlert(notificationIds: ["n1"], milestone: makeMilestone(), sentAt: Date().addingTimeInterval(-3600))
}

@MainActor
private func loadedPicksViewModel() -> RecommendationsViewModel {
    let viewModel = RecommendationsViewModel()
    viewModel.recommendations = [
        PreviewRecommendations.decode(type: "experience", isIdea: false, headline: "Weekend Curations"),
        PreviewRecommendations.decode(type: "gift", isIdea: false, headline: "Small Luxuries"),
        PreviewRecommendations.decode(type: "idea", isIdea: true, headline: "The Art of Pause"),
    ]
    viewModel.partnerName = "Jas"
    viewModel.hasLoadedInitially = true
    viewModel.batchGeneratedAt = Date().addingTimeInterval(-3600)
    return viewModel
}

@MainActor
final class RecentPicksSheetRenderingTests: XCTestCase {

    private func host(_ viewModel: RecommendationsViewModel, dark: Bool = false) throws -> UIHostingController<some View> {
        let context = try makeContext()
        let sheet = RecentPicksSheet(
            alert: makeAlert(),
            partnerName: "Jas",
            urgency: .soon,
            onViewed: {},
            onGetIdeas: {},
            onDismiss: {},
            viewModel: viewModel
        )
        .modelContext(context)
        .preferredColorScheme(dark ? .dark : .light)
        return UIHostingController(rootView: sheet)
    }

    func testRendersALoadedBatch() throws {
        let host = try host(loadedPicksViewModel())
        XCTAssertNotNil(host.view)
    }

    func testRendersInDarkMode() throws {
        let host = try host(loadedPicksViewModel(), dark: true)
        XCTAssertNotNil(host.view)
    }

    /// The seeded-empty case: `hasLoadedInitially` set with no picks resolves
    /// to the empty card rather than a spinner or a crash.
    func testRendersAnEmptyBatch() throws {
        let viewModel = RecommendationsViewModel()
        viewModel.hasLoadedInitially = true
        let host = try host(viewModel)
        XCTAssertNotNil(host.view)
    }

    /// The phase mapping the sheet relies on: it is always a pregenerated read,
    /// so a load is `.silent` (spinner, never the coral generation screen), a
    /// missing batch is `.missing`, an error is `.error`, and content is `.loaded`.
    func testPhaseMapping() {
        XCTAssertEqual(
            RecommendationsLoadingView.phase(isLoading: true, isPregeneratedRead: true, hasError: false, pregeneratedMissing: false, isEmpty: true),
            .silent
        )
        XCTAssertEqual(
            RecommendationsLoadingView.phase(isLoading: false, isPregeneratedRead: true, hasError: true, pregeneratedMissing: false, isEmpty: true),
            .error
        )
        XCTAssertEqual(
            RecommendationsLoadingView.phase(isLoading: false, isPregeneratedRead: true, hasError: false, pregeneratedMissing: true, isEmpty: true),
            .missing
        )
        XCTAssertEqual(
            RecommendationsLoadingView.phase(isLoading: false, isPregeneratedRead: true, hasError: false, pregeneratedMissing: false, isEmpty: false),
            .loaded
        )
    }
}

@MainActor
final class ForYouPendingPicksRenderingTests: XCTestCase {

    /// The Journal with an alert seeded renders — the banner, the sheet
    /// presentation and the scene-phase hook all mount without a network.
    func testJournalWithAnAlertRenders() async {
        let (viewModel, _, _) = makeViewModel()
        await viewModel.loadData()
        XCTAssertNotNil(viewModel.pendingPicksAlert)

        let host = UIHostingController(rootView: ForYouView(viewModel: viewModel))
        XCTAssertNotNil(host.view)
    }

    func testMetaCardRenders() {
        let card = MilestoneMetaCard(milestone: makeMilestone(), partnerName: "Jas", urgency: .soon)
        XCTAssertNotNil(UIHostingController(rootView: card).view)
    }

    func testArtworkHeroRenders() {
        let hero = MilestoneArtworkHero(milestone: makeMilestone())
        XCTAssertNotNil(UIHostingController(rootView: hero).view)
    }
}
