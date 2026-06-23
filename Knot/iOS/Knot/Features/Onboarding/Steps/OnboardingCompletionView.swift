//
//  OnboardingCompletionView.swift
//  Knot
//
//  Created on February 7, 2026.
//  Step 3.1: Placeholder for onboarding Step 9 — Completion / Transition to Home.
//  Step 3.9: Full implementation — success header with comprehensive profile summary.
//  Step 19.x: Replaced the static "You're All Set!" summary with an in-onboarding
//             recommendation reveal. The user's first "Just Because" picks are
//             generated and shown here before they ever reach the For You tab.
//

import SwiftUI
import LucideIcons

/// The final onboarding step: the user's very first recommendations, generated and
/// shown *inside* the onboarding flow before they reach the Home / For You tab.
///
/// By the time this view appears the partner vault has already been submitted — the
/// Love Languages step's "Next" button POSTs it (see `OnboardingContainerView`). So
/// this view immediately kicks off a default "Just Because" recommendation run using
/// the same `RecommendationsViewModel` engine the For You tab uses, then renders the
/// resulting cards.
///
/// Unlike `RecommendationsView`, this reveal deliberately omits the toolbar, the
/// tab-bar bottom clearance, the Adjust Vibe / Refresh actions, and the
/// `vaultMissing → hasCompletedOnboarding = false` re-route. The last one matters:
/// we have *just* created the vault, and a read-after-write lag could otherwise bounce
/// the user back out of onboarding mid-reveal.
///
/// The "Continue" button that finishes onboarding lives in `OnboardingContainerView`'s
/// navigation bar (it detects `.isLast` on this step), so it stays reachable in every
/// state below — loading, loaded, empty, or error — and the user is never trapped.
struct OnboardingCompletionView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    /// The shared onboarding view model (injected by `OnboardingContainerView`).
    /// Used to submit the partner vault as the first step of this reveal so the
    /// vault POST and the recommendation generation sit behind one loading screen.
    @Environment(OnboardingViewModel.self) private var onboarding

    /// Drives the container's "Continue" button visibility. The button lives in
    /// `OnboardingContainerView`'s navigation bar, so this reveal reports up
    /// whether it is still in progress: the button stays hidden while loading or
    /// celebrating, and appears only once the user reaches a terminal state.
    @Binding var showContinue: Bool

    @State private var viewModel = RecommendationsViewModel()

    /// True while the climax celebration plays — between loading completing and the
    /// recommendation cards appearing. Mirrors `RecommendationsView`'s own flag.
    @State private var isPlayingClimax = false

    /// True once the partner vault POST has succeeded. Until then the loading
    /// screen represents vault creation; afterward it represents recommendation
    /// generation. Keeping it `false` initially shows `ForYouLoadingView`
    /// immediately, with no empty-state flash before submission starts.
    @State private var vaultReady = false

    /// True if the vault POST failed, surfacing a retry-able error state.
    @State private var vaultFailed = false

    /// True while the reveal is still in progress — the loading screen (vault
    /// creation then recommendation generation) or the climax celebration is on
    /// screen. Mirrors the busy branches of `content` below. The container hides
    /// "Continue" while this is true; it stays interactive in the loaded, empty,
    /// error, and vault-failed states so the user is never trapped.
    private var isRevealing: Bool {
        Self.revealInProgress(
            vaultFailed: vaultFailed,
            vaultReady: vaultReady,
            isLoading: viewModel.isLoading,
            isPlayingClimax: isPlayingClimax
        )
    }

    /// Pure gating logic for `isRevealing`, factored out of the computed property
    /// so the Continue-button gating can be unit-tested independently of the
    /// view's `@State`. Mirrors the busy branches of the `content` switch: the
    /// reveal is "in progress" while the loading screen (vault creation then
    /// recommendation generation) or the climax celebration is on screen, and
    /// NOT in progress in the terminal loaded / empty / error / vault-failed
    /// states (where "Continue" should appear so the user is never trapped).
    static func revealInProgress(
        vaultFailed: Bool,
        vaultReady: Bool,
        isLoading: Bool,
        isPlayingClimax: Bool
    ) -> Bool {
        (!vaultFailed && (!vaultReady || isLoading)) || isPlayingClimax
    }

    var body: some View {
        content
            // Keep the container's "Continue" button in sync with the reveal's
            // progress without mutating state mid-render.
            .onChange(of: isRevealing) { _, revealing in
                showContinue = !revealing
            }
            // Trigger the celebration only on a fresh, successful load — skips on
            // error or when no recommendations came back.
            .onChange(of: viewModel.isLoading) { wasLoading, nowLoading in
                guard wasLoading,
                      !nowLoading,
                      !viewModel.recommendations.isEmpty,
                      viewModel.errorMessage == nil
                else { return }

                withAnimation(.easeIn(duration: 0.2)) {
                    isPlayingClimax = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.3) {
                    withAnimation(.easeOut(duration: 0.4)) {
                        isPlayingClimax = false
                    }
                }
            }
            .task {
                // Hide "Continue" the moment the reveal begins; `onChange` above
                // re-shows it once the reveal finishes.
                showContinue = false
                viewModel.configure(modelContext: modelContext)
                await submitVaultThenGenerate()
            }
            // MARK: - CTA flow (full parity with RecommendationsView)
            //
            // The card "Select" button opens this confirmation sheet, which hands
            // off to the merchant. Mirrors RecommendationsView so onboarding picks
            // behave identically to the For You tab.
            .sheet(isPresented: $viewModel.showConfirmationSheet) {
                if let item = viewModel.selectedRecommendation {
                    SelectionConfirmationSheet(
                        item: item,
                        onConfirm: {
                            Task { await viewModel.confirmSelection() }
                        },
                        onCancel: {
                            viewModel.dismissSelection()
                        }
                    )
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
                }
            }
            // Idea / date-plan "Read" button opens the idea detail.
            .fullScreenCover(isPresented: $viewModel.showIdeaDetail) {
                if let idea = viewModel.selectedIdea {
                    IdeaDetailView(idea: idea) {
                        viewModel.showIdeaDetail = false
                        viewModel.selectedIdea = nil
                    }
                }
            }
            // Spotlight detail page — opened by tapping a deck card. Mirrors the
            // For You tab so onboarding picks behave identically.
            .fullScreenCover(item: $viewModel.selectedDetailItem) { item in
                RecommendationDetailView(
                    item: item,
                    partnerName: viewModel.partnerName,
                    isSaved: viewModel.isSaved(item.id),
                    onOpenMerchant: { Task { await viewModel.openMerchantFromDetail(item) } },
                    onSave: { viewModel.saveRecommendation(item) },
                    onShare: { viewModel.shareRecommendation(item) },
                    onDismiss: { viewModel.dismissDetail() }
                )
            }
            // Return-to-app purchase prompt after the merchant handoff.
            .sheet(isPresented: $viewModel.showPurchasePromptSheet) {
                if let item = viewModel.pendingHandoffRecommendation {
                    PurchasePromptSheet(
                        title: item.title,
                        merchantName: item.merchantName,
                        onConfirmPurchase: {
                            Task { await viewModel.confirmPurchase() }
                        },
                        onSaveForLater: {
                            viewModel.declinePurchaseAndSave()
                        },
                        onDismiss: {
                            viewModel.dismissPurchasePrompt()
                        }
                    )
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
                }
            }
            // Rating prompt after confirming a purchase.
            .sheet(isPresented: $viewModel.showRatingPrompt) {
                if let item = viewModel.pendingHandoffRecommendation {
                    PurchaseRatingSheet(
                        itemTitle: item.title,
                        onSubmit: { rating, feedbackText in
                            Task {
                                await viewModel.submitPurchaseRating(rating, feedbackText: feedbackText)
                            }
                        },
                        onSkip: {
                            viewModel.skipPurchaseRating()
                        }
                    )
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
                }
            }
            // Detect return from the merchant to fire the purchase prompt.
            //
            // Unlike RecommendationsView, this onboarding reveal deliberately does
            // NOT port the App Store review prompt or the background "still
            // preparing" notification machinery — requesting a review or scheduling
            // a loading notification during first-run onboarding is premature.
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    viewModel.handleReturnFromMerchant()
                }
            }
    }

    // MARK: - Reveal Flow

    /// Submits the partner vault, then — on success — generates the first
    /// recommendations. Both run behind a single `ForYouLoadingView`: the loading
    /// screen represents vault creation until `vaultReady` flips, then seamlessly
    /// represents recommendation generation. On vault failure it stops and shows
    /// the retry-able error state. Also used by the error state's "Try Again".
    private func submitVaultThenGenerate() async {
        vaultFailed = false
        let success = await onboarding.submitVault()
        guard success else {
            vaultFailed = true
            return
        }
        // Set `vaultReady` immediately before the awaited call: the synchronous
        // prefix of `generateRecommendations()` sets `isLoading = true` in the
        // same run-loop tick, so the loading screen never flashes the empty state.
        vaultReady = true
        // Default arguments → occasionType "just_because", milestoneId nil,
        // the same run the For You tab's JustBecauseCard makes.
        await viewModel.generateRecommendations()
    }

    // MARK: - State Switch

    @ViewBuilder
    private var content: some View {
        if vaultFailed {
            errorState(
                message: onboarding.submissionError
                    ?? "We couldn't save your partner vault. Please try again.",
                retry: { Task { await submitVaultThenGenerate() } }
            )
        } else if !vaultReady || viewModel.isLoading {
            // One continuous loading screen: vault creation first (`!vaultReady`),
            // then recommendation generation (`viewModel.isLoading`).
            ForYouLoadingView()
        } else if isPlayingClimax {
            ForYouClimaxView()
                .transition(.opacity)
        } else if let error = viewModel.errorMessage {
            errorState(
                message: error,
                retry: { Task { await viewModel.generateRecommendations() } }
            )
        } else if viewModel.recommendations.isEmpty {
            emptyState
        } else {
            recommendationsList
        }
    }

    // MARK: - Loaded

    private var recommendationsList: some View {
        VStack(spacing: 0) {
            OnboardingStepHeader(title: "Here are your recommendations")
                .padding(.horizontal, 24)
                .padding(.bottom, 16)

            // A browse-only carousel of the first picks: the user swipes between
            // the Spotlight cards (page dots track position) and taps "See Details"
            // to open a pick. There's no save/pass voting here — saving happens
            // later on the For You tab and the detail page. The container's
            // "Continue" button proceeds to Home.
            SpotlightCarouselView(
                items: viewModel.recommendations,
                partnerName: viewModel.partnerName,
                isSaved: { viewModel.isSaved($0) },
                onOpenDetail: { viewModel.openDetail($0) }
            )
            .padding(.bottom, 24)
        }
    }

    // MARK: - Error State

    /// Vault submission or recommendation generation failed. The container's
    /// "Continue" button remains below, so the user can always proceed to Home
    /// even if this run errored. `retry` re-runs whichever step failed.
    private func errorState(message: String, retry: @escaping () -> Void) -> some View {
        VStack(spacing: 16) {
            Image(uiImage: Lucide.circleAlert)
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 40, height: 40)
                .foregroundStyle(Theme.textTertiary)

            Text(message)
                .knotFont(Theme.Typography.body)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button {
                retry()
            } label: {
                HStack(spacing: 6) {
                    Image(uiImage: Lucide.refreshCw)
                        .renderingMode(.template)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 14, height: 14)

                    Text("Try Again")
                        .knotFont(Theme.Typography.cta)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(
                    Capsule()
                        .fill(Theme.accent)
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(uiImage: Lucide.sparkles)
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 40, height: 40)
                .foregroundStyle(Theme.textTertiary)

            VStack(spacing: 8) {
                Text("You're all set")
                    .knotFont(Theme.Typography.cardTitle)
                    .foregroundStyle(Theme.textPrimary)

                Text("We'll have personalized picks waiting for you on the For You tab.")
                    .knotFont(Theme.Typography.body)
                    .foregroundStyle(Theme.textTertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Preview

#Preview {
    OnboardingCompletionView(showContinue: .constant(true))
        .environment(OnboardingViewModel())
}
