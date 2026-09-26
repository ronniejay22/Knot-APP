//
//  ForYouViewModel.swift
//  Knot
//
//  Created on March 20, 2026.
//  Manages timeline data for the Home tab — milestone loading, partner name,
//  and (Step 19.62) the "Recent picks" batches generated in the last few days.
//

import Foundation

// MARK: - Recent Batches Seam

/// The single read the Journal's "Recent picks" section depends on, so the
/// view model can be exercised in tests without a live backend.
///
/// Deliberately its own protocol rather than a third method on
/// `MilestoneRecommendationsFetching`: widening that seam would force every
/// existing conformer (the push tap-through's test mocks and the screenshot
/// harness stub) to implement a read they never make.
@MainActor
protocol RecentRecommendationsFetching {
    func fetchRecentRecommendations() async throws -> RecentRecommendationsResponse
}

extension NotificationHistoryService: RecentRecommendationsFetching {}

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

    /// Every batch the backend generated inside its recency window, newest
    /// first, exactly as served. Read through `visibleRecentBatches`.
    var recentBatches: [RecentRecommendationBatchResponse] = []

    /// The backend's recency window, as served with the batches, so the
    /// section's hint copy can never disagree with the expiry badges. The
    /// default only stands until the first successful read.
    var recentWindowDays: Int = 7

    /// The batches the Journal actually shows: `recentBatches` minus anything
    /// past its `expiresAt`.
    ///
    /// The backend already filters by the same window, so this is belt and
    /// suspenders — it covers a batch that expires while the app sits open,
    /// and a clock skew between the two. A batch that cannot be parsed counts
    /// as expired, since one with no expiry would otherwise never leave.
    var visibleRecentBatches: [RecentRecommendationBatchResponse] {
        recentBatches.filter { !Self.isExpired(expiresAt: $0.expiresAt) }
    }

    // MARK: - Dependencies

    private let milestoneService: MilestoneService
    private let vaultService: VaultService
    private let recentFetcher: any RecentRecommendationsFetching

    init(milestoneService: MilestoneService = MilestoneService(),
         vaultService: VaultService = VaultService(),
         recentFetcher: any RecentRecommendationsFetching = NotificationHistoryService()) {
        self.milestoneService = milestoneService
        self.vaultService = vaultService
        self.recentFetcher = recentFetcher
    }

    // MARK: - Data Loading

    /// Loads milestones, partner name, and recent batches in parallel.
    ///
    /// `isLoading` gates the milestone feed's spinner, so it clears as soon as
    /// the milestones and partner name are in — the recent batches keep
    /// loading behind it. Gating on them too would let a slow `/recent` hold
    /// the milestone empty state (and its CTA) hostage for up to its timeout.
    func loadData() async {
        isLoading = true
        errorMessage = nil

        async let milestonesTask: () = loadMilestones()
        async let vaultTask: () = loadPartnerName()
        async let recentTask: () = loadRecentBatches()

        await milestonesTask
        await vaultTask
        isLoading = false

        await recentTask
    }

    /// Reloads just the milestones (e.g., after adding/editing).
    func refreshMilestones() async {
        await loadMilestones()
    }

    /// Pull-to-refresh: everything the Journal shows that can have changed
    /// behind it — milestones and the recent batches.
    func refreshJournal() async {
        async let milestonesTask: () = loadMilestones()
        async let recentTask: () = loadRecentBatches()
        await milestonesTask
        await recentTask
    }

    /// Reloads the "Recent picks" batches. Best-effort: a failure keeps
    /// whatever was already showing and never surfaces an error — the section
    /// is secondary to the milestone feed, and an empty or stale Recent list is
    /// a far smaller cost than an error alert over the whole Journal.
    func loadRecentBatches() async {
        do {
            let response = try await recentFetcher.fetchRecentRecommendations()
            recentBatches = response.batches
            recentWindowDays = response.windowDays
        } catch {
            // Non-critical — keep the previous value.
        }
    }

    // MARK: - Recent Picks Helpers

    /// The milestone a batch was generated for, when the Journal has it loaded.
    func milestone(for batch: RecentRecommendationBatchResponse) -> MilestoneItemResponse? {
        guard let milestoneId = batch.milestoneId else { return nil }
        return milestones.first { $0.id == milestoneId }
    }

    /// The row title for a batch.
    ///
    /// A nil `milestoneId` is a just-because run — and also a batch whose
    /// milestone has since been deleted, since the FK is `ON DELETE SET NULL`.
    /// A milestone id that is not in `milestones` therefore only means the
    /// milestones have not loaded yet (the label updates in place when they
    /// do) or a one-time milestone that has already passed; "Special occasion"
    /// is the honest neutral for that.
    func occasionLabel(for batch: RecentRecommendationBatchResponse) -> String {
        guard batch.milestoneId != nil else { return "Just because" }
        return milestone(for: batch)?.milestoneName ?? "Special occasion"
    }

    /// Whether a batch is past its expiry. Unparseable → expired, so a batch
    /// with no usable expiry can never sit on the Journal indefinitely.
    static func isExpired(expiresAt: String, now: Date = Date()) -> Bool {
        guard let expiry = RecommendationsViewModel.parseTimestamp(expiresAt) else { return true }
        return expiry <= now
    }

    /// Whether a batch expires within the next 24 hours — the row's badge turns
    /// destructive so "save it now" reads as urgent.
    static func isExpiringSoon(expiresAt: String, now: Date = Date()) -> Bool {
        guard let expiry = RecommendationsViewModel.parseTimestamp(expiresAt) else { return false }
        let remaining = expiry.timeIntervalSince(now)
        return remaining > 0 && remaining < 24 * 60 * 60
    }

    /// "Expires today" / "Expires tomorrow" / "Expires in N days".
    ///
    /// Counted in calendar days rather than 24-hour spans, so a batch generated
    /// five minutes ago with a 7-day window reads "Expires in 7 days" — not
    /// "6", which is what a floor over the raw interval would give.
    static func expiryLabel(
        expiresAt: String,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> String {
        guard let expiry = RecommendationsViewModel.parseTimestamp(expiresAt) else {
            return "Expired"
        }
        let days = calendarDays(from: now, to: expiry, calendar: calendar)
        switch days {
        case ..<0: return "Expired"
        case 0: return "Expires today"
        case 1: return "Expires tomorrow"
        default: return "Expires in \(days) days"
        }
    }

    /// "Today" / "Yesterday" / "N days ago", by calendar day.
    static func generatedLabel(
        generatedAt: String,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> String {
        guard let generated = RecommendationsViewModel.parseTimestamp(generatedAt) else {
            return "Recently"
        }
        let days = calendarDays(from: generated, to: now, calendar: calendar)
        switch days {
        case ..<1: return "Today"
        case 1: return "Yesterday"
        default: return "\(days) days ago"
        }
    }

    /// "1 pick" / "3 picks".
    static func picksCountLabel(_ count: Int) -> String {
        count == 1 ? "1 pick" : "\(count) picks"
    }

    /// A `RecommendationsViewModel` already holding a stored batch, so pushing
    /// `RecommendationsView` with it shows the cards immediately and runs no
    /// pipeline (`hasLoadedInitially` short-circuits its `.task`).
    static func seededRecommendationsViewModel(
        for batch: RecentRecommendationBatchResponse,
        partnerName: String
    ) -> RecommendationsViewModel {
        let viewModel = RecommendationsViewModel()
        viewModel.recommendations = batch.recommendations.map { $0.toRecommendationItem() }
        viewModel.partnerName = partnerName
        viewModel.hasLoadedInitially = true
        return viewModel
    }

    /// Whole calendar days between two instants, in the given calendar.
    private static func calendarDays(from start: Date, to end: Date, calendar: Calendar) -> Int {
        let startDay = calendar.startOfDay(for: start)
        let endDay = calendar.startOfDay(for: end)
        return calendar.dateComponents([.day], from: startDay, to: endDay).day ?? 0
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
}

// MARK: - Supporting Types

enum MilestoneUrgency: Equatable {
    case critical   // 0-3 days — red
    case soon       // 4-7 days — orange
    case upcoming   // 8-14 days — yellow
    case planning   // 15-30 days — accent
    case distant    // 31+ days — tertiary
}
