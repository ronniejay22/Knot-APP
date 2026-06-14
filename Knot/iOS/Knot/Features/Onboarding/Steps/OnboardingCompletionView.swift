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

    @State private var viewModel = RecommendationsViewModel()

    /// True while the climax celebration plays — between loading completing and the
    /// recommendation cards appearing. Mirrors `RecommendationsView`'s own flag.
    @State private var isPlayingClimax = false

    var body: some View {
        content
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
                viewModel.configure(modelContext: modelContext)
                // Default arguments → occasionType "just_because", milestoneId nil,
                // the same run the For You tab's JustBecauseCard makes.
                await viewModel.generateRecommendations()
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

    // MARK: - State Switch

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading {
            ForYouLoadingView()
        } else if isPlayingClimax {
            ForYouClimaxView()
                .transition(.opacity)
        } else if let error = viewModel.errorMessage {
            errorState(message: error)
        } else if viewModel.recommendations.isEmpty {
            emptyState
        } else {
            recommendationsList
        }
    }

    // MARK: - Loaded

    private var recommendationsList: some View {
        VStack(spacing: 0) {
            OnboardingStepHeader(
                title: "Here are your first picks",
                subtitle: "Save the ones you love, pass on the rest. Tap Continue when you're ready."
            )
            .padding(.horizontal, 24)
            .padding(.bottom, 16)

            // The same Spotlight deck the For You tab uses. Onboarding is a fixed
            // reveal of the first picks, so `onNeedMore` is a no-op (the deck shows
            // its end-of-deck state and the container's "Continue" proceeds).
            SpotlightDeckView(
                items: viewModel.recommendations,
                partnerName: viewModel.partnerName,
                isSaved: { viewModel.isSaved($0) },
                onLike: { viewModel.saveRecommendation($0) },
                onPass: { viewModel.recordDislike($0) },
                onOpenDetail: { viewModel.openDetail($0) },
                onNeedMore: {},
                isLoadingMore: false,
                resetToken: viewModel.deckResetToken
            )
            .padding(.bottom, 24)
        }
    }

    // MARK: - Error State

    /// Generation failed. The container's "Continue" button remains below, so the
    /// user can always proceed to Home even if this run errored.
    private func errorState(message: String) -> some View {
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
                Task { await viewModel.generateRecommendations() }
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
    OnboardingCompletionView()
}
