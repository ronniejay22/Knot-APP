//
//  ForYouViewModel.swift
//  Knot
//
//  Created on March 20, 2026.
//  Manages timeline data for the For You tab — milestone loading and partner name.
//

import Foundation

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

    // MARK: - Dependencies

    private let milestoneService: MilestoneService
    private let vaultService: VaultService

    init(milestoneService: MilestoneService = MilestoneService(),
         vaultService: VaultService = VaultService()) {
        self.milestoneService = milestoneService
        self.vaultService = vaultService
    }

    // MARK: - Data Loading

    /// Loads milestones and partner name in parallel.
    func loadData() async {
        isLoading = true
        errorMessage = nil

        async let milestonesTask: () = loadMilestones()
        async let vaultTask: () = loadPartnerName()

        await milestonesTask
        await vaultTask

        isLoading = false
    }

    /// Reloads just the milestones (e.g., after adding/editing).
    func refreshMilestones() async {
        await loadMilestones()
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
