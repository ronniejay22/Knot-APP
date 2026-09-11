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
//  Step 15.2: Background loading + local notifications when app is backgrounded mid-generation.
//  Step 18.6: Session hint capture inside the refresh flow — pending reason + sheet state, hint submission before refresh.
//

import Foundation
import SwiftData
import UIKit
import UserNotifications

/// Seam for fetching a milestone's pre-generated recommendations, so the
/// push tap-through's preload path is unit-testable without a live backend.
/// Conformed to by the existing `NotificationHistoryService`.
@MainActor
protocol MilestoneRecommendationsFetching {
    func fetchMilestoneRecommendations(
        milestoneId: String
    ) async throws -> MilestoneRecommendationsResponse

    /// The newest stored batch for the vault, whichever surface produced it.
    /// Backs the recovery path for a generation whose response never arrived.
    func fetchLatestRecommendations() async throws -> MilestoneRecommendationsResponse
}

extension NotificationHistoryService: MilestoneRecommendationsFetching {}

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

    // MARK: - Session Hint Capture (Step 18.6)

    /// Whether the session hint capture sheet is presented.
    /// Shown after the user picks a refresh reason and before the API call.
    var showSessionHintsSheet = false

    /// The refresh reason the user picked, held until the session hints sheet is dismissed.
    var pendingRefreshReason: String?

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

    // MARK: - Spotlight Deck State (June 12, 2026)

    /// Partner's first name, used to personalize the detail page's
    /// "Why Knot picked this for {name}" header. Loaded best-effort.
    var partnerName: String?

    /// Whether a deck top-up fetch is currently in flight (drives the
    /// end-of-deck "Finding more…" state in `SpotlightDeckView`).
    var isLoadingMore = false

    /// The recommendation whose Spotlight detail page is presented. Non-nil
    /// drives the detail full-screen cover.
    var selectedDetailItem: RecommendationItemResponse?

    /// Bumped whenever the deck is replaced wholesale (a fresh generate or a
    /// full refresh) so `SpotlightDeckView` resets to the first card. A deck
    /// top-up (`loadMoreForDeck`) appends instead and deliberately does NOT bump
    /// this — the user keeps their place.
    var deckResetToken = 0

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

    // MARK: - Briefing State

    /// Contextual milestone briefing text generated by Claude.
    /// Non-nil when recommendations were generated for a specific milestone.
    var briefingText: String?

    // MARK: - Idea Detail State (Step 15.1: ideas now appear in the unified trio)

    /// The idea selected for detail view navigation.
    var selectedIdea: IdeaItemResponse?

    /// Whether the idea detail view is presented.
    var showIdeaDetail = false

    // MARK: - Vault State

    /// Set to `true` when a generate call confirms the partner vault does not exist.
    /// The view observes this to route the user back to onboarding automatically.
    var vaultMissing = false

    // MARK: - Lifecycle

    /// Whether the initial recommendations have been loaded.
    /// Prevents re-fetching when the user switches tabs and returns.
    var hasLoadedInitially = false

    // MARK: - Background Loading State (Step 15.2)

    /// The background task identifier used to keep the app alive while a recommendation
    /// request is in flight after the user has backgrounded the app.
    /// Holding it is the whole state: `backgroundTaskID != .invalid` means a
    /// window is open, which is what both the re-entrancy guard and the release
    /// path key on. A separate "was backgrounded" flag used to shadow this and
    /// only ever disagreed with it — see `releaseBackgroundExecutionWindow()`.
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid

    // MARK: - Dependencies

    private let service: RecommendationService
    private let hintService: HintService
    private let milestoneFetcher: any MilestoneRecommendationsFetching
    private var modelContext: ModelContext?

    /// The event this surface is showing recommendations for, if any. Set by
    /// `configure(modelContext:milestoneId:)` and stamped onto every save.
    private var currentMilestoneId: String?

    init(
        service: RecommendationService = RecommendationService(),
        hintService: HintService = HintService(),
        milestoneFetcher: any MilestoneRecommendationsFetching = NotificationHistoryService()
    ) {
        self.service = service
        self.hintService = hintService
        self.milestoneFetcher = milestoneFetcher
    }

    /// Configures the model context for local persistence. Called from the view.
    ///
    /// - Parameter milestoneId: The event these recommendations belong to, when
    ///   the surface was opened with milestone context. Saves are stamped with
    ///   it so the event's detail screen can list the ideas saved for it. `nil`
    ///   for the "just because" and onboarding-reveal surfaces, which belong to
    ///   no event.
    func configure(modelContext: ModelContext, milestoneId: String? = nil) {
        self.modelContext = modelContext
        self.currentMilestoneId = milestoneId
        loadSavedIds()
        Task { await loadPartnerName() }
    }

    /// Best-effort load of the partner's name for detail-page personalization.
    /// Silent on failure — the detail page falls back to "your partner".
    func loadPartnerName() async {
        guard partnerName == nil else { return }
        let vaultService = VaultService()
        if let vault = try? await vaultService.getVault() {
            partnerName = vault.partnerName
        }
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

        // Captured before the request so recovery can tell this run's stored
        // batch apart from one that was already there.
        let replacedIds = recommendations.map(\.id)

        do {
            let response = try await service.generateRecommendations(
                occasionType: occasionType,
                milestoneId: milestoneId
            )
            recommendations = response.recommendations
            briefingText = response.briefingText
            hasLoadedInitially = true
            deckResetToken += 1
        } catch let serviceError as RecommendationServiceError {
            if case .noVault = serviceError {
                // Re-verify: the backend says no vault exists. Confirm via Supabase directly.
                // If vault is truly missing, signal the view to re-route to onboarding.
                // If vault exists, this is a transient backend error — let the user retry.
                let vaultService = VaultService()
                if await !vaultService.vaultExists() {
                    vaultMissing = true
                } else {
                    errorMessage = serviceError.localizedDescription
                }
            } else {
                errorMessage = serviceError.localizedDescription
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        // The request failed, but the backend may have finished and stored the
        // picks anyway. Recover them rather than showing an error for work that
        // actually completed — this is what stops the "your picks are ready"
        // push dead-ending on a suspended-then-killed request.
        if errorMessage != nil,
           !vaultMissing,
           await recoverRecentlyStoredBatch(replacing: replacedIds, milestoneId: milestoneId) {
            errorMessage = nil
        }

        releaseBackgroundExecutionWindow()
        isLoading = false
    }

    // MARK: - Pre-Generated Milestone Recommendations (push tap-through)

    /// Loads the PRE-GENERATED recommendations stored when a milestone push
    /// notification fired, instead of re-running the ~30s generation pipeline.
    /// This is what the push copy described, so the tap-through shows exactly
    /// those picks, instantly.
    ///
    /// - Returns: `true` when something was displayed (recommendations or an
    ///   error state whose Try Again re-runs this path); `false` when no stored
    ///   rows exist — the caller should fall back to the generate path.
    func loadPregeneratedRecommendations(milestoneId: String) async -> Bool {
        guard !isLoading else { return true }

        isLoading = true
        errorMessage = nil
        currentPage = 0
        defer { isLoading = false }

        do {
            let response = try await milestoneFetcher.fetchMilestoneRecommendations(
                milestoneId: milestoneId
            )
            guard !response.recommendations.isEmpty else {
                // No stored batch (generation failed when the push fired, or
                // legacy data) — signal the caller to generate fresh ones.
                return false
            }
            recommendations = response.recommendations.map { $0.toRecommendationItem() }
            briefingText = response.briefingText
            hasLoadedInitially = true
            deckResetToken += 1
            return true
        } catch {
            // Transient fetch error: surface the error state (Try Again
            // re-runs this path) rather than silently burning a 30s
            // pipeline run.
            errorMessage = error.localizedDescription
            return true
        }
    }

    // MARK: - Refresh

    /// Shows the refresh reason selection sheet.
    /// Guarded against duplicate calls during active refresh or animation.
    func requestRefresh() {
        guard !isRefreshing && cardsVisible else { return }
        showRefreshReasonSheet = true
    }

    /// Handles the user's selected refresh reason.
    /// Step 18.6: Instead of refreshing immediately, dismisses the reason sheet and
    /// presents the session hints sheet so the user can capture any new observations
    /// about their partner before the next set of recommendations is generated.
    func handleRefreshReason(_ reason: String) {
        showRefreshReasonSheet = false
        pendingRefreshReason = reason

        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        // Show the session hints sheet on the next runloop tick so the
        // reason sheet's dismissal animation has somewhere to land before
        // the new sheet presents.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            showSessionHintsSheet = true
        }
    }

    /// Step 18.6: Persists a fresh hint via `HintService` (best-effort) and then
    /// runs the deferred refresh using the previously-stored `pendingRefreshReason`.
    /// Trims the input; an empty string is treated as a skip.
    func submitSessionHintAndRefresh(text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let reason = pendingRefreshReason else { return }

        showSessionHintsSheet = false
        pendingRefreshReason = nil

        if !trimmed.isEmpty {
            do {
                _ = try await hintService.createHint(text: trimmed, source: "text_input")
            } catch {
                // Best-effort: log and continue with the refresh so the user is
                // never blocked by hint persistence failures.
                print("[Knot] RecommendationsViewModel: session hint submit failed — \(error)")
            }
        }

        await runDeferredRefresh(reason: reason)
    }

    /// Step 18.6: Dismisses the session hints sheet without submitting and runs
    /// the deferred refresh.
    func skipSessionHintAndRefresh() async {
        guard let reason = pendingRefreshReason else { return }

        showSessionHintsSheet = false
        pendingRefreshReason = nil

        await runDeferredRefresh(reason: reason)
    }

    /// Shared exit-animate → API → entry-animate orchestration for refresh,
    /// extracted from the original `handleRefreshReason` so the session hints
    /// sheet flow can reuse it.
    private func runDeferredRefresh(reason: String) async {
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
            deckResetToken += 1
        } catch let serviceError as RecommendationServiceError {
            switch serviceError {
            case .staleRecommendations:
                // The rejected IDs aren't in the DB (vault mismatch or prior silent save failure).
                // Clear the stale state and fall back to a fresh generate.
                isRefreshing = false
                recommendations = []
                await generateRecommendations()
                return
            case .noVault:
                let vaultService = VaultService()
                if await !vaultService.vaultExists() {
                    vaultMissing = true
                } else {
                    errorMessage = serviceError.localizedDescription
                }
            default:
                errorMessage = serviceError.localizedDescription
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        // Same recovery as generate — a re-roll is a full pipeline run and can
        // be lost to suspension exactly the same way. The backend stamps the
        // replacement batch with the milestone it inherited from the rejected
        // rows, which is this surface's own.
        // `rejectedIds` is exactly the batch this re-roll was replacing, and the
        // backend excludes them from the replacement — so an overlap means the
        // recovered batch is the one already on screen.
        if errorMessage != nil,
           !vaultMissing,
           await recoverRecentlyStoredBatch(
               replacing: rejectedIds,
               milestoneId: currentMilestoneId
           ) {
            errorMessage = nil
        }

        releaseBackgroundExecutionWindow()
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

        // Dismiss the confirmation sheet.
        showConfirmationSheet = false
        selectedRecommendation = nil

        // Open the merchant URL with native-app preference and log handoff (Step 9.3).
        // Only arm the return-to-app prompt when a tap-out actually happens: items
        // with no external URL (ideas/plans, or a purchasable still awaiting a URL
        // swap) never background the app, so a purchase prompt on the next resume
        // would be spurious. Set pendingHandoffRecommendation BEFORE opening the URL,
        // since opening immediately backgrounds the app and handleReturnFromMerchant()
        // would otherwise find nil. (Step 9.4)
        if let urlString = item.externalUrl {
            pendingHandoffRecommendation = item
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
        guard !isSaved(item.id) else {
            // Already in the library — but it may have been saved from a
            // surface with no event behind it (the "Surprise them today" card,
            // the onboarding reveal), in which case saving it again from an
            // event is the user asking for it to appear under that event.
            // Filling a blank is strictly an improvement; an idea already
            // attributed to a *different* event is deliberately left alone,
            // since `recommendationId` is unique and re-pointing it would
            // silently remove the idea from the other event's list.
            backfillMilestoneIfUnattributed(recommendationId: item.id)
            return
        }

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
                contentSectionsData: contentData,
                milestoneId: currentMilestoneId
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

    // MARK: - Spotlight Deck (June 12, 2026)

    /// 👎 — records a "disliked" feedback signal for the card the user passed on.
    /// Fire-and-forget; the weekly feedback-analysis job down-weights the disliked
    /// vibes/interests/types. The deck advances locally regardless of the result.
    func recordDislike(_ item: RecommendationItemResponse) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        Task {
            try? await service.recordFeedback(
                recommendationId: item.id,
                action: "disliked"
            )
        }
    }

    /// Appends a fresh batch of recommendations to the deck when the user reaches
    /// the end. Reuses the refresh path (the `/refresh` endpoint already excludes
    /// recently-seen titles) with the current set as the exclusion list, and dedupes
    /// by id. Best-effort: on failure the deck shows its end-of-deck state.
    func loadMoreForDeck() async {
        guard !isLoadingMore, !isRefreshing else { return }
        // Exclude saved items: the `/refresh` endpoint records a negative
        // "refreshed" signal for every id we pass as rejected, and we must not
        // train the model against the user's own positive picks. Passed items
        // already carry their own "disliked" signal, and the server dedupes by
        // recent title, so dropping the saved ids here loses no exclusion.
        let seenIds = recommendations.map(\.id).filter { !isSaved($0) }
        guard !seenIds.isEmpty else { return }

        isLoadingMore = true

        let vibeOverrideArray = vibeOverride.map { Array($0).sorted() }
        do {
            let response = try await service.refreshRecommendations(
                rejectedIds: seenIds,
                reason: "show_different",
                vibeOverride: vibeOverrideArray
            )
            let existing = Set(recommendations.map(\.id))
            let fresh = response.recommendations.filter { !existing.contains($0.id) }
            recommendations.append(contentsOf: fresh)
        } catch {
            print("[Knot] RecommendationsViewModel: deck top-up failed — \(error)")
        }

        isLoadingMore = false
    }

    /// Opens the Spotlight detail page for a recommendation (tap on a deck card).
    func openDetail(_ item: RecommendationItemResponse) {
        selectedDetailItem = item
    }

    /// Dismisses the Spotlight detail page.
    func dismissDetail() {
        selectedDetailItem = nil
    }

    /// Primary CTA from the detail page for a purchasable recommendation. Mirrors
    /// `confirmSelection()` (records "selected", opens the merchant URL, preserves
    /// the item for the return-to-app purchase prompt) but takes the item directly
    /// since the detail page is itself the confirmation surface — no intermediate
    /// confirmation sheet. Dismisses the detail first so the return-to-app prompt
    /// lands on the deck.
    func openMerchantFromDetail(_ item: RecommendationItemResponse) async {
        selectedDetailItem = nil

        Task {
            try? await service.recordFeedback(
                recommendationId: item.id,
                action: "selected"
            )
        }

        pendingHandoffRecommendation = item

        if let urlString = item.externalUrl {
            await MerchantHandoffService.openMerchantURL(
                urlString: urlString,
                recommendationId: item.id,
                service: service
            )
        }
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

    /// Attributes an already-saved idea to the current event, but only if it
    /// isn't attributed to one yet.
    ///
    /// `savedRecommendationIds` spans the whole library, so without this an idea
    /// saved earlier from a no-event surface could never reach an event's list:
    /// the save button reads "Saved", the early return fires, and the idea is
    /// invisible on the detail screen the user expects it on.
    private func backfillMilestoneIfUnattributed(recommendationId: String) {
        guard let modelContext, let milestoneId = currentMilestoneId else { return }

        let descriptor = FetchDescriptor<SavedRecommendation>()
        guard let existing = try? modelContext.fetch(descriptor)
            .first(where: { $0.recommendationId == recommendationId }),
              existing.milestoneId == nil
        else { return }

        existing.milestoneId = milestoneId
        try? modelContext.save()
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

    // MARK: - Background Loading (Step 15.2)

    /// Called when the app goes to background while a recommendation request is in flight.
    /// Begins a background execution window so the HTTP request can complete, and
    /// schedules a local notification to inform the user the request is still running.
    func handleAppBackgroundedWhileLoading() {
        guard isLoading || isRefreshing else { return }
        guard backgroundTaskID == .invalid else { return } // already running

        backgroundTaskID = UIApplication.shared.beginBackgroundTask(
            withName: "knot.recommendations.generate"
        ) { [weak self] in
            // Expiration handler — iOS is about to suspend us.
            // End the task gracefully; no ready notification fires.
            print("[Knot] Background task expired before request completed")
            Task { @MainActor in
                self?.endBackgroundExecution()
            }
        }

        print("[Knot] Began background task (id: \(backgroundTaskID.rawValue)), remaining time: \(String(format: "%.0f", UIApplication.shared.backgroundTimeRemaining))s")
        scheduleStillLoadingNotification()
    }

    /// Called when the app returns to the foreground while loading is still in progress
    /// (or after it has completed). Cancels the pending "still working" notification
    /// if it has not fired yet.
    ///
    /// Only `knot.recs.loading` is cancellable. The completion announcement is a
    /// remote push from the backend, so it is already out of the app's hands by
    /// the time it matters — the foreground suppression in
    /// `AppDelegate.presentationOptions(forCategory:)` is what keeps it off a
    /// returning user's screen.
    func cancelPendingLoadingNotification() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: ["knot.recs.loading"]
        )
    }

    /// Called at the end of generate/refresh to release the background execution
    /// window the app took when it was backgrounded mid-request.
    ///
    /// This no longer schedules a "ready" notification. That announcement is now
    /// a remote push fired by the backend when the pipeline finishes, because a
    /// local one could not be relied on: iOS grants only ~30s of background
    /// execution against a ~20-30s pipeline, and when that window expired the
    /// app was suspended — taking the in-flight request, and any chance of
    /// scheduling a notification, with it.
    ///
    /// **Unconditional on purpose.** `endBackgroundExecution()` already no-ops
    /// when no window is held, and gating the release on "was the app
    /// backgrounded" leaked the assertion whenever the user *returned* before
    /// the request finished: the flag was cleared on the foreground transition,
    /// so this early-returned and the task was never ended. The next backgrounded
    /// generation then bailed at `guard backgroundTaskID == .invalid`, taking no
    /// window and sending no "Still working on it…" notification at all.
    private func releaseBackgroundExecutionWindow() {
        endBackgroundExecution()
    }

    // MARK: - Recovering a Lost Generation

    /// How recent a stored batch must be to stand in for a generation whose
    /// response never arrived.
    ///
    /// Generation takes ~25s, so anything inside this window belongs to the run
    /// the user just asked for. Wide enough to cover an app suspended for a few
    /// minutes; far too narrow to resurface a batch from a previous session.
    static let recoverableBatchWindow: TimeInterval = 15 * 60

    /// Whether a stored batch can stand in for the run whose response was lost.
    ///
    /// Being *recent* is not enough, and that distinction is the whole safety
    /// argument. A re-roll that fails would otherwise recover the batch already
    /// on screen: the user waits ~25s, watches the cards animate out and back,
    /// and gets the identical three with no error to explain it.
    ///
    /// The guard is `replacing` — the ids showing when the request started —
    /// rather than a timestamp comparison, because the only clock available for
    /// that is the device's while `created_at` is the server's. Any skew
    /// tolerance wide enough to be safe is also wide enough to re-admit the
    /// batch being replaced, since an eager user re-rolls seconds after the
    /// previous one was stored. Row ids are exact and need no clock: the
    /// backend inserts new rows for every run, and `/refresh` explicitly
    /// excludes the ids it was given, so a genuine replacement shares none.
    ///
    /// The milestone context must match too — `/latest` serves whatever is
    /// newest for the vault, which can be another surface's batch, and saving
    /// one of those would file it under the wrong event.
    ///
    /// Pure so the rule is testable without a backend.
    ///
    /// - Parameters:
    ///   - replacing: Ids on screen when the lost request started.
    ///   - milestoneId: The milestone that run targeted, `nil` for just-because.
    static func isRecoverableBatch(
        _ response: MilestoneRecommendationsResponse,
        replacing: [String],
        milestoneId: String?,
        now: Date = Date()
    ) -> Bool {
        guard let newest = response.recommendations.first,
              let createdAt = parseTimestamp(newest.createdAt)
        else { return false }

        guard response.milestoneId == milestoneId else { return false }

        let recovered = Set(response.recommendations.map(\.id))
        guard recovered.isDisjoint(with: replacing) else { return false }

        return now.timeIntervalSince(createdAt) <= recoverableBatchWindow
    }

    /// Tries to recover a generation whose HTTP response never reached us.
    ///
    /// The pipeline runs server-side and stores its picks *before* responding,
    /// so a request killed by app suspension — iOS grants ~30s of background
    /// execution against a ~20-30s pipeline — leaves finished work in the
    /// database. Without this, the "your picks are ready" push announced picks
    /// and then dropped the user on an error state whose Try Again burned
    /// another ~25s regenerating what already existed.
    ///
    /// Not `private` so the tests can drive it directly; nothing outside this
    /// file calls it.
    ///
    /// - Parameters:
    ///   - replacing: Ids on screen when the lost request started. A batch
    ///     overlapping these is work this run did not do.
    ///   - milestoneId: The milestone that run targeted, `nil` for just-because.
    /// - Returns: `true` when the run's batch was recovered and published.
    func recoverRecentlyStoredBatch(
        replacing: [String],
        milestoneId: String?
    ) async -> Bool {
        let response: MilestoneRecommendationsResponse
        do {
            response = try await milestoneFetcher.fetchLatestRecommendations()
        } catch {
            return false
        }

        guard Self.isRecoverableBatch(
            response,
            replacing: replacing,
            milestoneId: milestoneId
        ) else { return false }

        recommendations = response.recommendations.map { $0.toRecommendationItem() }
        // Only overwrite the briefing when there is one to show. `/latest`
        // always answers with none, so assigning it unconditionally would wipe
        // the briefing card off a milestone surface on every recovery.
        if let briefing = response.briefingText {
            briefingText = briefing
        }
        hasLoadedInitially = true
        deckResetToken += 1
        return true
    }

    /// Parses a Supabase ISO 8601 timestamp, which carries microseconds.
    /// Falls back to the non-fractional form for older rows.
    static func parseTimestamp(_ value: String) -> Date? {
        let withFractional = ISO8601DateFormatter()
        withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFractional.date(from: value) { return date }

        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: value)
    }

    /// Ends the active background execution task and resets the identifier.
    private func endBackgroundExecution() {
        guard backgroundTaskID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTaskID)
        backgroundTaskID = .invalid
    }

    /// Schedules a local notification that fires 1 second after backgrounding,
    /// informing the user the request is still running.
    private func scheduleStillLoadingNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Still working on it…"
        content.body = "Your recommendations are loading in the background."
        content.sound = .none

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(
            identifier: "knot.recs.loading",
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                print("[Knot] Failed to schedule loading notification: \(error.localizedDescription)")
            }
        }
    }
}
