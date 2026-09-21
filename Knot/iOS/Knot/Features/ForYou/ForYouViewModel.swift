//
//  ForYouViewModel.swift
//  Knot
//
//  Created on March 20, 2026.
//  Manages timeline data for the For You tab — milestone loading and partner name.
//  Step 19.63: also reads the notification history so the Journal can announce
//  a milestone push the user never tapped (`pendingPicksAlert`).
//

import Foundation

/// The milestone list read the Journal depends on, as a seam so tests can
/// drive `ForYouViewModel` without a live backend. `MilestoneService` conforms
/// with no extra code.
@MainActor
protocol MilestoneListing {
    func listMilestones() async throws -> MilestoneListResponse
}

extension MilestoneService: MilestoneListing {}

/// The vault read behind the partner name, as a seam for the same reason: a
/// test that drives `loadData()` must not reach a live session. `VaultService`
/// conforms with no extra code.
@MainActor
protocol VaultReading {
    func getVault() async throws -> VaultGetResponse
}

extension VaultService: VaultReading {}

/// The notification-history operations behind the "New picks" alert: the read
/// that finds an untapped push, the mark-viewed that retires it, and the ids
/// any surface in this process has already asked to mark viewed — the push
/// tap-through cover included — so a history read racing that PATCH cannot
/// announce a push the user just opened. `NotificationHistoryService`
/// conforms with one property (its `fetchHistory` has defaulted parameters,
/// which still satisfies the full signature).
@MainActor
protocol NotificationHistoryReading {
    func fetchHistory(limit: Int, offset: Int) async throws -> NotificationHistoryResponse
    func markViewed(notificationId: String) async
    var locallyViewedNotificationIds: Set<String> { get }
}

extension NotificationHistoryService: NotificationHistoryReading {
    var locallyViewedNotificationIds: Set<String> { Self.locallyViewedNotificationIds }
}

@MainActor
@Observable
final class ForYouViewModel {

    // MARK: - State

    /// All milestones sorted by days until next occurrence (from backend).
    var milestones: [MilestoneItemResponse] = []

    /// Partner name from the vault, used for milestone display.
    var partnerName: String = "Your Partner"

    /// Whether milestone data is currently loading.
    var isLoading = false

    /// Error message if loading fails.
    var errorMessage: String?

    /// The one untapped milestone push the Journal is announcing, or nil.
    /// Re-derived whenever either input changes (milestones or history), so an
    /// edited milestone date re-evaluates "upcoming" without a history read.
    var pendingPicksAlert: PendingPicksAlert?

    /// Whether the first load has run. The view's `.task` checks it so a view
    /// model handed in already populated (harness, tests) is not overwritten.
    var hasLoadedInitially = false

    /// The last successful history read. Kept so a milestones-only refresh can
    /// re-run the alert selection, and so a failed history read keeps the
    /// previous answer rather than blanking it.
    private var historyRows: [NotificationHistoryItemResponse] = []

    /// Pushes the user opened or dismissed this session. The mark-viewed PATCH
    /// is fire-and-forget, so a refresh racing it — or one that failed silently
    /// — would otherwise bring the alert straight back.
    private var acknowledgedNotificationIds: Set<String> = []

    // MARK: - Dependencies

    private let milestoneService: any MilestoneListing
    private let vaultService: any VaultReading
    private let historyReader: any NotificationHistoryReading

    init(milestoneService: any MilestoneListing = MilestoneService(),
         vaultService: any VaultReading = VaultService(),
         historyReader: any NotificationHistoryReading = NotificationHistoryService()) {
        self.milestoneService = milestoneService
        self.vaultService = vaultService
        self.historyReader = historyReader
    }

    // MARK: - Data Loading

    /// Loads milestones, partner name and notification history in parallel.
    func loadData() async {
        isLoading = true
        errorMessage = nil

        async let milestonesTask: () = loadMilestones()
        async let vaultTask: () = loadPartnerName()
        async let historyTask: () = loadHistory()

        await milestonesTask
        await vaultTask
        await historyTask

        hasLoadedInitially = true
        isLoading = false
    }

    /// Reloads just the milestones (e.g., after adding/editing). The alert is
    /// re-selected against the stored history rows, so a date change is
    /// reflected without a second network read.
    func refreshMilestones() async {
        await loadMilestones()
    }

    /// Pull-to-refresh and the foreground return: milestones and history
    /// together, because a push that arrived while the app was away only shows
    /// up in the history, and its "upcoming" test needs a fresh `daysUntil`.
    func refresh() async {
        async let milestonesTask: () = loadMilestones()
        async let historyTask: () = loadHistory()
        await milestonesTask
        await historyTask
    }

    /// The scene-phase hook. A no-op before the first load (which is already
    /// in flight or about to be) and while a load is running.
    func refreshOnForeground() async {
        guard hasLoadedInitially, !isLoading else { return }
        await refresh()
    }

    // MARK: - Pending Picks

    /// Marks every push behind `alert` viewed and retires it locally at once.
    ///
    /// Called when the picks sheet opens and when the alert's ✕ is tapped —
    /// both count as "seen". The local re-selection comes first so the ✕
    /// feels instant and a PATCH that fails still clears the alert (it may
    /// reappear on the next launch, exactly as the push tap-through behaves).
    /// Re-selecting rather than nil-ing means the right thing follows on its
    /// own: a newer push for the same milestone that replaced this alert
    /// meanwhile stays, and another event's untapped push — next in line —
    /// is announced without waiting for a refresh.
    func acknowledge(_ alert: PendingPicksAlert) async {
        acknowledgedNotificationIds.formUnion(alert.notificationIds)
        reselectPendingPicks()
        for id in alert.notificationIds {
            await historyReader.markViewed(notificationId: id)
        }
    }

    // MARK: - Helpers

    /// Occasion type derived from a milestone's budget tier.
    func occasionType(for milestone: MilestoneItemResponse) -> String {
        milestone.budgetTier ?? "major_milestone"
    }

    /// Urgency color for a milestone based on days until.
    func urgencyLevel(for daysUntil: Int) -> MilestoneUrgency {
        switch daysUntil {
        case 0...3: return .critical
        case 4...7: return .soon
        case 8...14: return .upcoming
        case 15...30: return .planning
        default: return .distant
        }
    }

    /// Formatted date string from a milestone date ("2000-MM-DD" → "Mar 28").
    func formattedDate(_ dateString: String) -> String {
        let components = dateString.split(separator: "-")
        guard components.count >= 3,
              let month = Int(components[1]),
              let day = Int(components[2]) else {
            return dateString
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"

        var dateComponents = DateComponents()
        dateComponents.month = month
        dateComponents.day = day
        dateComponents.year = Calendar.current.component(.year, from: Date())

        if let date = Calendar.current.date(from: dateComponents) {
            return formatter.string(from: date)
        }
        return dateString
    }

    // MARK: - Private

    private func loadMilestones() async {
        do {
            let response = try await milestoneService.listMilestones()
            milestones = response.milestones
            reselectPendingPicks()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadPartnerName() async {
        do {
            let vault = try await vaultService.getVault()
            partnerName = vault.partnerName
        } catch {
            // Non-critical — keep default "Your Partner"
        }
    }

    /// Best-effort by design: the Journal must not degrade because `/history`
    /// is down, so a failed read keeps the previous rows and never touches
    /// `errorMessage`. Rows come newest-first, so one page holds every push
    /// that could still qualify.
    private func loadHistory() async {
        guard let response = try? await historyReader.fetchHistory(limit: 50, offset: 0) else {
            return
        }
        historyRows = response.notifications
        reselectPendingPicks()
    }

    /// Runs after either input lands, so the two loads need no ordering.
    ///
    /// Excludes both this view model's own acknowledgements and every id any
    /// surface in the process has asked to mark viewed (`historyReader.
    /// locallyViewedNotificationIds`) — the latter is what keeps a push the
    /// user just tapped from being announced when the foreground refresh's
    /// GET beats the tap-through cover's PATCH.
    private func reselectPendingPicks() {
        pendingPicksAlert = PendingPicksAlert.select(
            from: historyRows,
            milestones: milestones,
            excluding: acknowledgedNotificationIds.union(historyReader.locallyViewedNotificationIds)
        )
    }
}

// MARK: - Supporting Types

enum MilestoneUrgency: Equatable {
    case critical   // 0-3 days — red
    case soon       // 4-7 days — orange
    case upcoming   // 8-14 days — yellow
    case planning   // 15-30 days — accent
    case distant    // 31+ days — tertiary
}
