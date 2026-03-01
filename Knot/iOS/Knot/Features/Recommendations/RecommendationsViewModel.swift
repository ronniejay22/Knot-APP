//
//  RecommendationsViewModel.swift
//  Knot
//
//  Created on February 10, 2026.
//  Step 6.2: State management for the Choice-of-Three recommendation UI.
//  Step 6.3: Card selection flow with confirmation sheet and feedback recording.
//  Step 6.4: Refresh flow with reason selection and card exit/entry animations.
//  Step 6.5: Manual vibe override — session-scoped vibe selection and refresh.
//  Step 6.6: Save/Share actions with local persistence and feedback recording.
//  Step 9.4: Return-to-app flow — purchase confirmation and rating after merchant handoff.
//  Step 10.4: App Store review prompt after 5-star rating with 90-day rate limiting.
//  Step 15.1: Unified AI recommendations — removed ideas mode, ideas feed state/methods.
//

import Foundation
import SwiftData
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

    // MARK: - Vibe Override State (Step 6.5)

    /// Whether the vibe override sheet is presented.
    var showVibeOverrideSheet = false

    /// Temporarily overridden vibe tags for this session only.
    /// When non-nil, these vibes are sent on refresh calls instead of the vault's vibes.
    /// Cleared when the user navigates away from the recommendations screen.
    var vibeOverride: Set<String>?

    /// Whether the user has an active vibe override for this session.
    var hasVibeOverride: Bool { vibeOverride != nil }

    // MARK: - Save/Share State (Step 6.6)

    /// IDs of recommendations the user has saved in this session (for instant UI feedback).
    /// Populated on launch from SwiftData and updated when the user taps Save.
    var savedRecommendationIds: Set<String> = []

    // MARK: - Return-to-App State (Step 9.4)

    /// The recommendation that was handed off to the merchant.
    /// Set when confirmSelection() opens the merchant URL. Cleared when the
    /// purchase prompt is dismissed. Non-nil triggers the purchase prompt
    /// on foreground return.
    var pendingHandoffRecommendation: RecommendationItemResponse?

    /// Whether the purchase prompt bottom sheet is presented.
    var showPurchasePromptSheet = false

    /// Whether the rating prompt is shown after confirming a purchase.
    var showRatingPrompt = false

    // MARK: - App Review Prompt State (Step 10.4)

    /// Whether the App Store review prompt is currently shown.
    var showAppReviewPrompt = false

    // MARK: - Idea Detail State (Step 15.1: ideas now appear in the unified trio)

    /// The idea selected for detail view navigation.
    var selectedIdea: IdeaItemResponse?

    /// Whether the idea detail view is presented.
    var showIdeaDetail = false

    // MARK: - Dependencies

    private let service: RecommendationService
    private var modelContext: ModelContext?

    init(service: RecommendationService = RecommendationService()) {
        self.service = service
    }

    /// Configures the model context for local persistence. Called from the view.
    func configure(modelContext: ModelContext) {
        self.modelContext = modelContext
        loadSavedIds()
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
    /// and returns a new set of 3 recommendations. If a vibe override is active,
    /// the overridden vibes are sent to the backend instead of the vault's vibes.
    ///
    /// - Parameter reason: The rejection reason for filtering
    func refreshRecommendations(reason: String) async {
        guard !isRefreshing else { return }

        let rejectedIds = recommendations.map(\.id)
        guard !rejectedIds.isEmpty else { return }

        isRefreshing = true
        errorMessage = nil
        currentPage = 0

        // Pass vibe override as sorted array if active, nil otherwise
        let vibeOverrideArray = vibeOverride.map { Array($0).sorted() }

        do {
            let response = try await service.refreshRecommendations(
                rejectedIds: rejectedIds,
                reason: reason,
                vibeOverride: vibeOverrideArray
            )
            recommendations = response.recommendations
        } catch {
            errorMessage = error.localizedDescription
        }

        isRefreshing = false
    }

    // MARK: - Vibe Override (Step 6.5)

    /// Shows the vibe override sheet.
    func requestVibeOverride() {
        showVibeOverrideSheet = true
    }

    /// Saves the vibe override and triggers a refresh with the new vibes.
    /// Called when the user taps "Save" in the vibe override sheet.
    ///
    /// - Parameter vibes: The selected vibe tags (must have at least 1)
    func saveVibeOverride(_ vibes: Set<String>) async {
        guard !vibes.isEmpty else { return }

        // Store the override
        vibeOverride = vibes

        // Dismiss the sheet
        showVibeOverrideSheet = false

        // Haptic feedback
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        // Wait for sheet dismissal animation
        try? await Task.sleep(for: .milliseconds(300))

        // Animate cards out
        cardsVisible = false

        // Wait for exit animation
        try? await Task.sleep(for: .milliseconds(350))

        // Refresh with the new vibes using "show_different" reason
        await refreshRecommendations(reason: "show_different")

        // Animate new cards in
        cardsVisible = true

        // Success haptic
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    /// Clears the vibe override, reverting to the vault's default vibes.
    func clearVibeOverride() {
        vibeOverride = nil
    }

    // MARK: - Selection (Step 6.3)

    /// Called when the user taps "Select" on a recommendation card.
    /// Stores the selected item and presents the confirmation sheet.
    func selectRecommendation(_ item: RecommendationItemResponse) {
        selectedRecommendation = item
        showConfirmationSheet = true
    }

    /// Called when the user confirms their selection in the bottom sheet.
    /// Records "selected" feedback, opens the merchant URL preferring native apps,
    /// logs a "handoff" analytics event, and preserves the recommendation for the
    /// return-to-app purchase prompt (Step 9.4).
    func confirmSelection() async {
        guard let item = selectedRecommendation else { return }

        // Record "selected" feedback (fire-and-forget — don't block the user)
        Task {
            try? await service.recordFeedback(
                recommendationId: item.id,
                action: "selected"
            )
        }

        // Dismiss the confirmation sheet and preserve the recommendation
        // for the return-to-app purchase prompt BEFORE opening the URL.
        // Opening the URL immediately backgrounds the app, so state must
        // be set first or handleReturnFromMerchant() finds nil. (Step 9.4)
        showConfirmationSheet = false
        pendingHandoffRecommendation = item
        selectedRecommendation = nil

        // Open the merchant URL with native-app preference and log handoff (Step 9.3)
        // Ideas have no external URL — skip merchant handoff for them.
        if let urlString = item.externalUrl {
            await MerchantHandoffService.openMerchantURL(
                urlString: urlString,
                recommendationId: item.id,
                service: service
            )
        }
    }

    /// Dismisses the confirmation sheet without confirming.
    func dismissSelection() {
        showConfirmationSheet = false
        selectedRecommendation = nil
    }

    // MARK: - Save (Step 6.6)

    /// Returns whether the recommendation with the given ID has been saved.
    func isSaved(_ recommendationId: String) -> Bool {
        savedRecommendationIds.contains(recommendationId)
    }

    /// Saves a recommendation locally via SwiftData and records "saved" feedback.
    ///
    /// If the recommendation is already saved, this is a no-op (the button toggles
    /// to "Saved" state and stays there — unsave is not supported in the MVP).
    func saveRecommendation(_ item: RecommendationItemResponse) {
        guard !isSaved(item.id) else { return }

        // Insert into SwiftData
        if let modelContext {
            let contentData: Data? = if let sections = item.contentSections {
                try? JSONEncoder().encode(sections)
            } else {
                nil
            }
            let saved = SavedRecommendation(
                recommendationId: item.id,
                recommendationType: item.recommendationType,
                title: item.title,
                descriptionText: item.description,
                externalURL: item.externalUrl,
                priceCents: item.priceCents,
                currency: item.currency,
                merchantName: item.merchantName,
                imageURL: item.imageUrl,
                isIdea: item.isIdea == true,
                contentSectionsData: contentData
            )
            modelContext.insert(saved)
            try? modelContext.save()
        }

        // Update local set for instant UI
        savedRecommendationIds.insert(item.id)

        // Haptic feedback
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        // Record feedback (fire-and-forget)
        Task {
            try? await service.recordFeedback(
                recommendationId: item.id,
                action: "saved"
            )
        }
    }

    // MARK: - Share (Step 6.6)

    /// Presents the system share sheet with the recommendation URL and a custom message.
    ///
    /// Records "shared" feedback on the backend only when the user completes the share
    /// (not on cancellation).
    func shareRecommendation(_ item: RecommendationItemResponse) {
        let title = item.title
        let merchantText = item.merchantName.map { " from \($0)" } ?? ""
        let message = "Check out this recommendation\(merchantText): \(title)"

        var items: [Any] = [message]
        if let urlString = item.externalUrl, let url = URL(string: urlString) {
            items.append(url)
        }

        let activityVC = UIActivityViewController(activityItems: items, applicationActivities: nil)

        // Record feedback only on successful share (not cancellation)
        let service = self.service
        let itemId = item.id
        activityVC.completionWithItemsHandler = { activityType, completed, _, _ in
            guard completed, activityType != nil else { return }
            Task {
                try? await service.recordFeedback(
                    recommendationId: itemId,
                    action: "shared"
                )
            }
        }

        // Present the share sheet from the top-most view controller
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            var topVC = rootVC
            while let presented = topVC.presentedViewController {
                topVC = presented
            }
            topVC.present(activityVC, animated: true)
        }
    }

    // MARK: - Return-to-App (Step 9.4)

    /// Called when the app returns to foreground and there is a pending handoff.
    /// Presents the purchase prompt sheet after a brief delay.
    func handleReturnFromMerchant() {
        guard pendingHandoffRecommendation != nil else { return }
        // Small delay to let the app fully resume before presenting a sheet
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            guard pendingHandoffRecommendation != nil else { return }
            showPurchasePromptSheet = true
        }
    }

    /// Called when the user taps "Yes, I bought it!" in the purchase prompt.
    /// Records "purchased" feedback and shows the optional rating step.
    func confirmPurchase() async {
        guard let item = pendingHandoffRecommendation else { return }

        // Record "purchased" feedback (fire-and-forget)
        Task {
            try? await service.recordFeedback(
                recommendationId: item.id,
                action: "purchased"
            )
        }

        // Dismiss the purchase prompt and show the rating step
        showPurchasePromptSheet = false
        showRatingPrompt = true

        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    /// Called when the user submits a rating after confirming purchase.
    /// Records a "rated" feedback with the rating value and optional text.
    /// If the rating is 5 stars and the 90-day cooldown has elapsed,
    /// shows the App Store review prompt after a 2-second delay (Step 10.4).
    func submitPurchaseRating(_ rating: Int, feedbackText: String? = nil) async {
        guard let item = pendingHandoffRecommendation else { return }

        Task {
            try? await service.recordFeedback(
                recommendationId: item.id,
                action: "rated",
                rating: rating,
                feedbackText: feedbackText
            )
        }

        showRatingPrompt = false
        pendingHandoffRecommendation = nil

        UINotificationFeedbackGenerator().notificationOccurred(.success)

        // Step 10.4: After a 5-star rating, prompt for App Store review
        if rating == 5 && canPromptForAppReview() {
            try? await Task.sleep(for: .seconds(2))
            showAppReviewPrompt = true
        }
    }

    /// Called when the user skips the rating after confirming purchase.
    func skipPurchaseRating() {
        showRatingPrompt = false
        pendingHandoffRecommendation = nil
    }

    /// Called when the user taps "No, save for later" in the purchase prompt.
    /// Saves the recommendation locally and clears the pending handoff.
    func declinePurchaseAndSave() {
        guard let item = pendingHandoffRecommendation else { return }

        // Reuse existing save logic
        saveRecommendation(item)

        showPurchasePromptSheet = false
        pendingHandoffRecommendation = nil
    }

    /// Called when the user dismisses the purchase prompt without choosing.
    func dismissPurchasePrompt() {
        showPurchasePromptSheet = false
        pendingHandoffRecommendation = nil
    }

    // MARK: - Idea Detail (Step 15.1: ideas now appear in the unified trio)

    /// Opens the idea detail view for the given idea.
    func selectIdea(_ idea: IdeaItemResponse) {
        selectedIdea = idea
        showIdeaDetail = true
    }

    /// Opens the idea detail view for an idea that appeared in the unified trio.
    /// Converts the `RecommendationItemResponse` to `IdeaItemResponse` for the detail view.
    func openIdeaFromTrio(_ item: RecommendationItemResponse) {
        let idea = IdeaItemResponse(
            id: item.id,
            title: item.title,
            description: item.description,
            recommendationType: item.recommendationType,
            contentSections: item.contentSections ?? [],
            matchedInterests: item.matchedInterests,
            matchedVibes: item.matchedVibes,
            matchedLoveLanguages: item.matchedLoveLanguages,
            createdAt: ""
        )
        selectIdea(idea)
    }

    // MARK: - Private Helpers

    /// Loads saved recommendation IDs from SwiftData on init.
    private func loadSavedIds() {
        guard let modelContext else { return }

        let descriptor = FetchDescriptor<SavedRecommendation>()
        if let saved = try? modelContext.fetch(descriptor) {
            savedRecommendationIds = Set(saved.map(\.recommendationId))
        }
    }

    // MARK: - App Review Prompt Helpers (Step 10.4)

    /// UserDefaults key for the last time the App Store review prompt was shown.
    private static let appReviewPromptKey = "lastAppReviewPromptDate"

    /// Minimum number of days between App Store review prompts.
    private static let reviewCooldownDays = 90

    /// Returns true if enough time has elapsed since the last review prompt.
    func canPromptForAppReview() -> Bool {
        guard let lastPrompt = UserDefaults.standard.object(
            forKey: Self.appReviewPromptKey
        ) as? Date else {
            return true
        }
        let daysSince = Calendar.current.dateComponents(
            [.day], from: lastPrompt, to: Date()
        ).day ?? 0
        return daysSince >= Self.reviewCooldownDays
    }

    /// Records the current date as the last review prompt date.
    func recordAppReviewPromptDate() {
        UserDefaults.standard.set(Date(), forKey: Self.appReviewPromptKey)
    }

    /// Dismisses the App Store review prompt without recording the date.
    func dismissAppReviewPrompt() {
        showAppReviewPrompt = false
    }
}
