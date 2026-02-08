//
//  HomeViewModel.swift
//  Knot
//
//  Created on February 8, 2026.
//  Step 4.1: Home screen data management — vault loading, milestone countdowns, hints preview.
//  Step 4.2: Added hint submission (submitHint), recent hints loading (loadRecentHints),
//            success/error state for hint capture, ISO 8601 date parsing for hint timestamps.
//

import Foundation

/// Manages data for the Home screen.
///
/// Loads the partner vault from the backend via `VaultService.getVault()` and provides
/// computed properties for the UI: partner name, upcoming milestones with countdown,
/// recent hints preview, and vibes summary.
///
/// Handles hint submission via `HintService.createHint()` and loads recent hints
/// from `HintService.listHints()`.
///
/// Refreshes data automatically on appear and when returning from Edit Profile.
@Observable
@MainActor
final class HomeViewModel {

    // MARK: - State

    /// `true` while loading vault data from the backend.
    var isLoading = false

    /// Error message if vault loading fails.
    var errorMessage: String?

    /// The full vault data from the backend.
    var vault: VaultGetResponse?

    /// Recent hints (last 3), loaded from the backend.
    var recentHints: [HintPreview] = []

    /// `true` while a hint is being submitted to the backend.
    var isSubmittingHint = false

    /// `true` briefly after a hint is successfully submitted (drives checkmark animation).
    var showHintSuccess = false

    /// Error message if hint submission fails.
    var hintErrorMessage: String?

    // MARK: - Computed Properties

    /// The partner's name from the vault, or a placeholder if not loaded.
    var partnerName: String {
        vault?.partnerName ?? "Your Partner"
    }

    /// The upcoming milestones (next 1-2), sorted by days until occurrence.
    var upcomingMilestones: [UpcomingMilestone] {
        guard let vault = vault else { return [] }

        let today = Date()
        let calendar = Calendar.current

        let milestones: [UpcomingMilestone] = vault.milestones.compactMap { milestone in
            guard let (month, day) = parseMilestoneDate(milestone.milestoneDate) else {
                return nil
            }

            let daysUntil = daysUntilNextOccurrence(month: month, day: day, from: today, calendar: calendar)

            return UpcomingMilestone(
                id: milestone.id,
                name: milestone.milestoneName,
                type: milestone.milestoneType,
                month: month,
                day: day,
                daysUntil: daysUntil,
                budgetTier: milestone.budgetTier
            )
        }

        return Array(milestones.sorted { $0.daysUntil < $1.daysUntil }.prefix(2))
    }

    /// The single next upcoming milestone (for the header countdown).
    var nextMilestone: UpcomingMilestone? {
        upcomingMilestones.first
    }

    /// Vibes selected by the user, for display as tags.
    var vibes: [String] {
        vault?.vibes ?? []
    }

    // MARK: - Actions

    /// Loads (or refreshes) the vault data from the backend.
    func loadVault() async {
        isLoading = true
        errorMessage = nil

        do {
            let service = VaultService()
            vault = try await service.getVault()
        } catch {
            errorMessage = error.localizedDescription
            print("[Knot] HomeViewModel: Failed to load vault — \(error)")
        }

        isLoading = false
    }

    /// Loads recent hints from the backend (last 3, for Home screen preview).
    func loadRecentHints() async {
        do {
            let service = HintService()
            let response = try await service.listHints(limit: 3, offset: 0)
            recentHints = response.hints.map { hint in
                HintPreview(
                    id: hint.id,
                    text: hint.hintText,
                    source: hint.source,
                    createdAt: Self.parseISO8601(hint.createdAt) ?? Date()
                )
            }
        } catch {
            // Don't block the UI for hints loading failure — just log it.
            print("[Knot] HomeViewModel: Failed to load recent hints — \(error)")
        }
    }

    /// Submits a new hint to the backend via `HintService.createHint()`.
    ///
    /// On success:
    /// 1. Sets `showHintSuccess = true` (drives the checkmark animation)
    /// 2. Refreshes the recent hints list
    /// 3. Resets `showHintSuccess` after a short delay
    ///
    /// - Parameters:
    ///   - text: The hint text to submit
    ///   - source: The source of the hint ("text_input" or "voice_transcription")
    /// - Returns: `true` if the hint was submitted successfully, `false` otherwise
    @discardableResult
    func submitHint(text: String, source: String = "text_input") async -> Bool {
        isSubmittingHint = true
        hintErrorMessage = nil

        do {
            let service = HintService()
            _ = try await service.createHint(text: text, source: source)

            // Success — show the checkmark animation
            showHintSuccess = true

            // Refresh recent hints to include the new one
            await loadRecentHints()

            // Auto-dismiss the success indicator after 1.5 seconds
            try? await Task.sleep(for: .seconds(1.5))
            showHintSuccess = false

            isSubmittingHint = false
            return true
        } catch {
            hintErrorMessage = error.localizedDescription
            print("[Knot] HomeViewModel: Failed to submit hint — \(error)")
            isSubmittingHint = false
            return false
        }
    }

    // MARK: - Date Helpers

    /// Parses a milestone date string ("2000-MM-DD") into (month, day).
    private func parseMilestoneDate(_ dateString: String) -> (month: Int, day: Int)? {
        let parts = dateString.split(separator: "-")
        guard parts.count == 3,
              let month = Int(parts[1]),
              let day = Int(parts[2]) else {
            return nil
        }
        return (month, day)
    }

    /// Computes the number of days until the next occurrence of a month/day date.
    ///
    /// For yearly milestones: if the date has already passed this year, computes
    /// days until next year's occurrence.
    private func daysUntilNextOccurrence(month: Int, day: Int, from date: Date, calendar: Calendar) -> Int {
        let currentYear = calendar.component(.year, from: date)

        // Try this year first
        var components = DateComponents()
        components.year = currentYear
        components.month = month
        components.day = day

        if let thisYear = calendar.date(from: components) {
            let daysUntil = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: thisYear)).day ?? 0
            if daysUntil >= 0 {
                return daysUntil
            }
        }

        // Already passed this year — try next year
        components.year = currentYear + 1
        if let nextYear = calendar.date(from: components) {
            return calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: nextYear)).day ?? 365
        }

        return 365
    }

    /// Parses an ISO 8601 timestamp string into a `Date`.
    ///
    /// Handles Supabase-style timestamps like "2026-02-08T12:34:56.789012+00:00"
    /// and also simpler formats without fractional seconds.
    static func parseISO8601(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) {
            return date
        }

        // Fallback without fractional seconds
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }
}

// MARK: - Supporting Types

/// An upcoming milestone with countdown information.
struct UpcomingMilestone: Identifiable, Sendable {
    let id: String
    let name: String
    let type: String  // birthday, anniversary, holiday, custom
    let month: Int
    let day: Int
    let daysUntil: Int
    let budgetTier: String?

    /// Human-readable date string (e.g., "Feb 14").
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        var components = DateComponents()
        components.month = month
        components.day = day
        components.year = Calendar.current.component(.year, from: Date())
        if let date = Calendar.current.date(from: components) {
            return formatter.string(from: date)
        }
        return "\(month)/\(day)"
    }

    /// Countdown text (e.g., "in 14 days", "Tomorrow", "Today!").
    var countdownText: String {
        switch daysUntil {
        case 0: return "Today!"
        case 1: return "Tomorrow"
        default: return "in \(daysUntil) days"
        }
    }

    /// SF Symbol name for the milestone type icon.
    var iconName: String {
        switch type {
        case "birthday": return "birthday.cake"
        case "anniversary": return "heart.fill"
        case "holiday": return "star.fill"
        case "custom": return "calendar.badge.plus"
        default: return "calendar"
        }
    }

    /// Urgency color: red if <=3 days, orange if <=7, yellow if <=14, default otherwise.
    var urgencyLevel: UrgencyLevel {
        switch daysUntil {
        case 0...3: return .critical
        case 4...7: return .soon
        case 8...14: return .upcoming
        default: return .distant
        }
    }

    enum UrgencyLevel {
        case critical, soon, upcoming, distant
    }
}

/// Preview model for a recent hint displayed on the Home screen.
/// Full implementation in Step 4.5 when the Hints API is connected.
struct HintPreview: Identifiable, Sendable {
    let id: String
    let text: String
    let source: String  // "text_input" or "voice_transcription"
    let createdAt: Date
}
