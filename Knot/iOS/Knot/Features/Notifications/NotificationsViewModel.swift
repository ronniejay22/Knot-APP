//
//  NotificationsViewModel.swift
//  Knot
//
//  Created on February 12, 2026.
//  Step 7.7: ViewModel for the Notification History screen.
//

import Foundation

/// ViewModel for the Notification History screen.
///
/// Manages loading notification history, selecting a notification to view
/// its recommendations, and marking notifications as viewed.
@Observable
@MainActor
final class NotificationsViewModel {

    // MARK: - History State

    /// Whether the initial history is loading.
    var isLoading = false

    /// The list of notification history items.
    var notifications: [NotificationHistoryItemResponse] = []

    /// Error message to display if loading fails.
    var errorMessage: String?

    // MARK: - Recommendation Detail State

    /// The notification currently selected for viewing recommendations.
    var selectedNotification: NotificationHistoryItemResponse?

    /// Whether milestone recommendations are loading.
    var isLoadingRecommendations = false

    /// The recommendations loaded for the selected notification's milestone.
    var milestoneRecommendations: [MilestoneRecommendationItemResponse] = []

    /// Controls the recommendations sheet presentation.
    var showRecommendationsSheet = false

    /// Error message for recommendation loading.
    var recommendationsError: String?

    // MARK: - Dependencies

    private let service: NotificationHistoryService

    init(service: NotificationHistoryService = NotificationHistoryService()) {
        self.service = service
    }

    // MARK: - Actions

    /// Loads the user's notification history from the backend.
    func loadHistory() async {
        isLoading = true
        errorMessage = nil

        do {
            let response = try await service.fetchHistory()
            notifications = response.notifications
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    /// Selects a notification and loads its associated recommendations.
    ///
    /// Flow:
    /// 1. Set selected notification and show the recommendations sheet
    /// 2. Load recommendations for the notification's milestone
    /// 3. Mark the notification as viewed (fire-and-forget)
    /// 4. Update the local notification's viewedAt for immediate UI feedback
    func selectNotification(_ notification: NotificationHistoryItemResponse) async {
        selectedNotification = notification
        showRecommendationsSheet = true
        isLoadingRecommendations = true
        recommendationsError = nil
        milestoneRecommendations = []

        // Load recommendations for this milestone
        do {
            let response = try await service.fetchMilestoneRecommendations(
                milestoneId: notification.milestoneId
            )
            milestoneRecommendations = response.recommendations
        } catch {
            recommendationsError = error.localizedDescription
        }

        isLoadingRecommendations = false

        // Mark as viewed (fire-and-forget) if not already viewed
        if notification.viewedAt == nil {
            await service.markViewed(notificationId: notification.id)

            // Update the local array for immediate UI feedback
            if let index = notifications.firstIndex(where: { $0.id == notification.id }) {
                let existing = notifications[index]
                let updated = NotificationHistoryItemResponse(
                    id: existing.id,
                    milestoneId: existing.milestoneId,
                    milestoneName: existing.milestoneName,
                    milestoneType: existing.milestoneType,
                    milestoneDate: existing.milestoneDate,
                    daysBefore: existing.daysBefore,
                    status: existing.status,
                    sentAt: existing.sentAt,
                    viewedAt: ISO8601DateFormatter().string(from: Date()),
                    createdAt: existing.createdAt,
                    recommendationsCount: existing.recommendationsCount
                )
                notifications[index] = updated
            }
        }
    }

    /// Dismisses the recommendations sheet and resets detail state.
    func dismissRecommendations() {
        showRecommendationsSheet = false
        selectedNotification = nil
        milestoneRecommendations = []
        recommendationsError = nil
    }

    // MARK: - Helpers

    /// Formats a sent_at ISO 8601 string into a user-friendly display string.
    func formattedDate(_ isoString: String?) -> String {
        guard let isoString else { return "Unknown date" }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        // Try with fractional seconds first, then without
        var date = formatter.date(from: isoString)
        if date == nil {
            formatter.formatOptions = [.withInternetDateTime]
            date = formatter.date(from: isoString)
        }

        guard let parsedDate = date else { return "Unknown date" }

        let displayFormatter = DateFormatter()
        displayFormatter.dateStyle = .medium
        displayFormatter.timeStyle = .short
        return displayFormatter.string(from: parsedDate)
    }

    /// Returns a human-readable label for the days-before value.
    func daysBeforeLabel(_ daysBefore: Int) -> String {
        "\(daysBefore) days before"
    }

    /// Returns an SF Symbol name for the milestone type.
    func milestoneTypeIcon(_ type: String) -> String {
        switch type {
        case "birthday": return "gift.fill"
        case "anniversary": return "heart.fill"
        case "holiday": return "star.fill"
        default: return "calendar.badge.clock"
        }
    }

    /// Formats price from cents to a display string.
    func formattedPrice(cents: Int?, currency: String = "USD") -> String? {
        guard let cents else { return nil }
        let amount = Double(cents) / 100.0
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        return formatter.string(from: NSNumber(value: amount))
    }
}
