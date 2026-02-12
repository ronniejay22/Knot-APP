//
//  RecommendationsViewModel.swift
//  Knot
//
//  Created on February 10, 2026.
//  Step 6.2: State management for the Choice-of-Three recommendation UI.
//  Step 6.3: Card selection flow with confirmation sheet and feedback recording.
//  Step 6.4: Refresh flow with reason selection and card exit/entry animations.
//

import Foundation
import UIKit

/// State container for the recommendations screen.
///
/// Manages loading, displaying, refreshing, and selecting the Choice-of-Three
/// recommendation cards. Communicates with the backend via `RecommendationService`.
@MainActor
@Observable
final class RecommendationsViewModel {

    // MARK: - State

    /// The current set of recommendations (up to 3).
    var recommendations: [RecommendationItemResponse] = []

    /// Whether recommendations are currently being fetched.
    var isLoading = false

    /// Whether a refresh is in progress (shows different loading UI).
    var isRefreshing = false

    /// Error message to display.
    var errorMessage: String?

    /// The currently selected page index in the horizontal scroll.
    var currentPage = 0

    // MARK: - Selection State (Step 6.3)

    /// The recommendation the user tapped "Select" on. Non-nil triggers the confirmation sheet.
    var selectedRecommendation: RecommendationItemResponse?

    /// Whether the confirmation bottom sheet is presented.
    var showConfirmationSheet = false

    // MARK: - Refresh Reason State (Step 6.4)

    /// Whether the refresh reason selection sheet is presented.
    var showRefreshReasonSheet = false

    /// Controls card visibility for entry/exit animations during refresh.
    var cardsVisible = true

    // MARK: - Dependencies

    private let service: RecommendationService

    init(service: RecommendationService = RecommendationService()) {
        self.service = service
    }

    // MARK: - Generate

    /// Generates a fresh set of recommendations from the AI pipeline.
    ///
    /// - Parameters:
    ///   - occasionType: The occasion type ("just_because", "minor_occasion", "major_milestone")
    ///   - milestoneId: Optional milestone ID for targeted recommendations
    func generateRecommendations(
        occasionType: String = "just_because",
        milestoneId: String? = nil
    ) async {
        guard !isLoading else { return }

        isLoading = true
        errorMessage = nil
        currentPage = 0

        do {
            let response = try await service.generateRecommendations(
                occasionType: occasionType,
                milestoneId: milestoneId
            )
            recommendations = response.recommendations
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    // MARK: - Refresh

    /// Shows the refresh reason selection sheet.
    /// Guarded against duplicate calls during active refresh or animation.
    func requestRefresh() {
        guard !isRefreshing && cardsVisible else { return }
        showRefreshReasonSheet = true
    }

    /// Handles the user's selected refresh reason.
    /// Orchestrates: sheet dismissal → card exit animation → API refresh → card entry animation.
    func handleRefreshReason(_ reason: String) async {
        // Dismiss the reason sheet
        showRefreshReasonSheet = false

        // Haptic feedback on sheet dismissal
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        // Wait for sheet dismissal animation
        try? await Task.sleep(for: .milliseconds(300))

        // Animate cards out (view reacts via .animation modifier)
        cardsVisible = false

        // Wait for exit animation to complete
        try? await Task.sleep(for: .milliseconds(350))

        // Call the refresh API
        await refreshRecommendations(reason: reason)

        // Animate new cards in
        cardsVisible = true

        // Haptic feedback for new cards appearing
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    /// Refreshes recommendations by rejecting the current set with a reason.
    ///
    /// The backend applies exclusion filters based on the rejection reason
    /// and returns a new set of 3 recommendations.
    ///
    /// - Parameter reason: The rejection reason for filtering
    func refreshRecommendations(reason: String) async {
        guard !isRefreshing else { return }

        let rejectedIds = recommendations.map(\.id)
        guard !rejectedIds.isEmpty else { return }

        isRefreshing = true
        errorMessage = nil
        currentPage = 0

        do {
            let response = try await service.refreshRecommendations(
                rejectedIds: rejectedIds,
                reason: reason
            )
            recommendations = response.recommendations
        } catch {
            errorMessage = error.localizedDescription
        }

        isRefreshing = false
    }

    // MARK: - Selection (Step 6.3)

    /// Called when the user taps "Select" on a recommendation card.
    /// Stores the selected item and presents the confirmation sheet.
    func selectRecommendation(_ item: RecommendationItemResponse) {
        selectedRecommendation = item
        showConfirmationSheet = true
    }

    /// Called when the user confirms their selection in the bottom sheet.
    /// Records feedback (fire-and-forget) and immediately opens the external URL.
    func confirmSelection() async {
        guard let item = selectedRecommendation else { return }

        // Record feedback (fire-and-forget — don't block the user)
        Task {
            try? await service.recordFeedback(
                recommendationId: item.id,
                action: "selected"
            )
        }

        // Open the external merchant URL immediately
        if let url = URL(string: item.externalUrl) {
            await UIApplication.shared.open(url)
        }

        // Dismiss the sheet
        showConfirmationSheet = false
        selectedRecommendation = nil
    }

    /// Dismisses the confirmation sheet without confirming.
    func dismissSelection() {
        showConfirmationSheet = false
        selectedRecommendation = nil
    }
}
