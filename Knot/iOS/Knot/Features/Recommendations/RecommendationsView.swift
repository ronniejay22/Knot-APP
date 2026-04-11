//
//  RecommendationsView.swift
//  Knot
//
//  Created on February 10, 2026.
//  Step 6.2: Choice-of-Three horizontal scroll with paging, loading state, and Refresh button.
//  Step 6.3: Card selection flow with confirmation bottom sheet.
//  Step 6.4: Refresh flow with reason selection sheet and card animations.
//  Step 6.5: Manual vibe override — Adjust Vibe button and VibeOverrideSheet.
//  Step 6.6: Save and Share action buttons wired into RecommendationCard.
//  Step 9.4: Return-to-app purchase prompt and rating sheets after merchant handoff.
//  Step 10.4: App Store review prompt after 5-star purchase ratings.
//  Step 14.8: Added "Suggestions"/"Ideas" segmented control and ideas feed.
//

import SwiftUI
import StoreKit
import LucideIcons

/// Displays exactly 3 recommendation cards in a horizontal paging scroll view.
///
/// Layout:
/// ```
/// ┌─────────────────────────────────────┐
/// │  ← Recommendations        ● ● ○    │
/// ├─────────────────────────────────────┤
/// │                                     │
/// │  ┌─────────────────────────────┐    │
/// │  │   RecommendationCard (1/3)  │    │
/// │  │   ← swipe to page →        │    │
/// │  └─────────────────────────────┘    │
/// │                                     │
/// │  ┌─────────────────────────────┐    │
/// │  │      🔄 Refresh             │    │
/// │  └─────────────────────────────┘    │
/// └─────────────────────────────────────┘
/// ```
struct RecommendationsView: View {
    /// Optional milestone ID for milestone-contextual recommendations.
    var milestoneId: String?

    /// Display context for the milestone header (nil for "just because" mode).
    var milestoneContext: MilestoneDisplayContext?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.requestReview) private var requestReview
    @Environment(AuthViewModel.self) private var authViewModel

    @State private var viewModel = RecommendationsViewModel()

    @State private var isBriefingExpanded = false
    @State private var isBriefingDismissed = false

    /// True while the climax celebration is playing — between loading completing and
    /// recommendation cards appearing. Driven by `.onChange(of: viewModel.isLoading)`.
    @State private var isPlayingClimax = false

    var body: some View {
        recommendationsBody
            .background(Theme.backgroundGradient.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    if let ctx = milestoneContext {
                        VStack(spacing: 1) {
                            Text(ctx.name)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.textPrimary)
                            Text(MilestonesViewModel.daysUntilText(ctx.daysUntil))
                                .font(.caption2)
                                .foregroundStyle(Theme.textSecondary)
                        }
                    } else {
                        Text("Recommendations")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(Theme.textPrimary)
                    }
                }
            }
            .task {
                viewModel.configure(modelContext: modelContext)
                await generateWithMilestoneContext()
            }
            .sheet(isPresented: $viewModel.showConfirmationSheet) {
                if let item = viewModel.selectedRecommendation {
                    SelectionConfirmationSheet(
                        item: item,
                        onConfirm: {
                            Task {
                                await viewModel.confirmSelection()
                            }
                        },
                        onCancel: {
                            viewModel.dismissSelection()
                        }
                    )
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
                }
            }
            .sheet(isPresented: $viewModel.showRefreshReasonSheet) {
                RefreshReasonSheet { reason in
                    Task {
                        await viewModel.handleRefreshReason(reason)
                    }
                }
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $viewModel.showVibeOverrideSheet) {
                VibeOverrideSheet(
                    selectedVibes: viewModel.vibeOverride ?? [],
                    onSave: { vibes in
                        Task {
                            await viewModel.saveVibeOverride(vibes)
                        }
                    },
                    onClear: {
                        viewModel.clearVibeOverride()
                        viewModel.showVibeOverrideSheet = false
                    }
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
            // Purchase prompt sheet (Step 9.4)
            .sheet(isPresented: $viewModel.showPurchasePromptSheet) {
                if let item = viewModel.pendingHandoffRecommendation {
                    PurchasePromptSheet(
                        title: item.title,
                        merchantName: item.merchantName,
                        onConfirmPurchase: {
                            Task {
                                await viewModel.confirmPurchase()
                            }
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
            // Rating prompt sheet (Step 9.4)
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
            // App Store review prompt sheet (Step 10.4)
            .sheet(isPresented: $viewModel.showAppReviewPrompt) {
                AppReviewPromptSheet(
                    onAccept: {
                        viewModel.recordAppReviewPromptDate()
                        viewModel.showAppReviewPrompt = false
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(500))
                            requestReview()
                        }
                    },
                    onDecline: {
                        viewModel.dismissAppReviewPrompt()
                    }
                )
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
            }
            // Return-to-app detection (Step 9.4) + background loading (Step 15.2)
            // iOS transitions .background → .inactive → .active, so we check
            // for .active arrival rather than direct .background → .active.
            // The guard in handleReturnFromMerchant() prevents false triggers.
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    viewModel.handleReturnFromMerchant()
                    viewModel.cancelPendingLoadingNotification()
                } else if newPhase == .background {
                    viewModel.handleAppBackgroundedWhileLoading()
                }
            }
            // Vault missing — route back to onboarding automatically.
            // Triggered when generateRecommendations() confirms the vault doesn't exist.
            .onChange(of: viewModel.vaultMissing) { _, isMissing in
                if isMissing {
                    authViewModel.hasCompletedOnboarding = false
                }
            }
            // Idea detail view (Step 14.9)
            .fullScreenCover(isPresented: $viewModel.showIdeaDetail) {
                if let idea = viewModel.selectedIdea {
                    IdeaDetailView(idea: idea) {
                        viewModel.showIdeaDetail = false
                        viewModel.selectedIdea = nil
                    }
                }
            }
    }

    // MARK: - Recommendations Body

    /// The full recommendations UI.
    private var recommendationsBody: some View {
        ZStack {
            Theme.backgroundGradient.ignoresSafeArea()
            suggestionsContent
        }
        .onChange(of: viewModel.isLoading) { wasLoading, nowLoading in
            // Trigger the climax celebration only on a fresh successful load.
            // Skips if there was an error or if no recommendations came back.
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
    }

    // MARK: - Milestone-Aware Generation

    /// Generates recommendations using the milestone context passed from ForYouView,
    /// or falls back to "just_because" when no milestone context is provided.
    private func generateWithMilestoneContext() async {
        if let ctx = milestoneContext, let mId = milestoneId {
            await viewModel.generateRecommendations(
                occasionType: ctx.occasionType,
                milestoneId: mId
            )
        } else {
            await viewModel.generateRecommendations()
        }
    }

    // MARK: - Briefing Card

    /// A conversational briefing card displayed above the recommendation cards.
    /// Synthesizes hints, interests, and milestone context into a friendly narrative.
    private func briefingCard(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row — always visible
            HStack(spacing: 10) {
                Image(uiImage: Lucide.messageCircle)
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 16, height: 16)
                    .foregroundStyle(Theme.accent)

                Text("Knot's Take")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)

                Spacer()

                // Dismiss button
                Button {
                    withAnimation(.easeOut(duration: 0.25)) {
                        isBriefingDismissed = true
                    }
                } label: {
                    Image(uiImage: Lucide.x)
                        .renderingMode(.template)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 14, height: 14)
                        .foregroundStyle(Theme.textTertiary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)

            // Body text — collapsed (2 lines) or expanded
            Text(text)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .lineSpacing(3)
                .lineLimit(isBriefingExpanded ? nil : 2)
                .padding(.horizontal, 14)
                .padding(.bottom, isBriefingExpanded ? 4 : 10)

            // "Read more" / "Show less" toggle
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isBriefingExpanded.toggle()
                }
            } label: {
                Text(isBriefingExpanded ? "Show less" : "Read more")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Theme.accent)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Theme.accent.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Theme.accent.opacity(0.15), lineWidth: 1)
                )
        )
    }

    // MARK: - Suggestions Content

    @ViewBuilder
    private var suggestionsContent: some View {
        if viewModel.isLoading {
            loadingState
        } else if isPlayingClimax {
            ForYouClimaxView()
                .transition(.opacity)
        } else if let error = viewModel.errorMessage {
            errorState(message: error)
        } else if viewModel.recommendations.isEmpty {
            emptyState
        } else {
            recommendationsContent
        }
    }

    // MARK: - Recommendations Content

    private var recommendationsContent: some View {
        VStack(spacing: 20) {
            // Milestone briefing card (shown when a contextual briefing was generated)
            if let briefing = viewModel.briefingText, !isBriefingDismissed {
                briefingCard(briefing)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // Page indicator (hidden during refresh animation)
            pageIndicator
                .opacity(viewModel.cardsVisible ? 1 : 0)
                .animation(.easeInOut(duration: 0.3), value: viewModel.cardsVisible)

            ZStack {
                // Horizontal paging scroll (animated out/in during refresh)
                TabView(selection: $viewModel.currentPage) {
                    ForEach(Array(viewModel.recommendations.enumerated()), id: \.element.id) { index, item in
                        ScrollView {
                            RecommendationCard(
                                title: item.title,
                                descriptionText: item.description,
                                recommendationType: item.recommendationType,
                                priceCents: item.isIdea == true ? nil : item.priceCents,
                                currency: item.currency,
                                priceConfidence: item.priceConfidence ?? "unknown",
                                merchantName: item.isIdea == true ? nil : item.merchantName,
                                imageURL: item.imageUrl,
                                isSaved: viewModel.isSaved(item.id),
                                matchedInterests: item.matchedInterests ?? [],
                                matchedVibes: item.matchedVibes ?? [],
                                matchedLoveLanguages: item.matchedLoveLanguages ?? [],
                                personalizationNote: item.personalizationNote,
                                onSelect: {
                                    if item.isIdea == true || item.recommendationType == "plan" {
                                        viewModel.openIdeaFromTrio(item)
                                    } else {
                                        viewModel.selectRecommendation(item)
                                    }
                                },
                                onSave: {
                                    viewModel.saveRecommendation(item)
                                },
                                onShare: {
                                    viewModel.shareRecommendation(item)
                                }
                            )
                            .padding(.horizontal, 20)
                        }
                        .scrollIndicators(.hidden)
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .opacity(viewModel.cardsVisible ? 1 : 0)
                .scaleEffect(viewModel.cardsVisible ? 1 : 0.85)
                .animation(.easeInOut(duration: 0.3), value: viewModel.cardsVisible)

                // Refresh loading overlay (Step 6.4)
                if viewModel.isRefreshing {
                    RefreshLoadingOverlay()
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.3), value: viewModel.isRefreshing)

            // Action buttons (Step 6.5: Adjust Vibe + Refresh)
            HStack(spacing: 12) {
                adjustVibeButton
                refreshButton
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
    }

    // MARK: - Adjust Vibe Button (Step 6.5)

    private var adjustVibeButton: some View {
        Button {
            viewModel.requestVibeOverride()
        } label: {
            HStack(spacing: 8) {
                Image(uiImage: Lucide.sparkles)
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 16, height: 16)

                Text("Adjust Vibe")
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(viewModel.hasVibeOverride ? .white : Theme.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(viewModel.hasVibeOverride ? Theme.accent.opacity(0.3) : Theme.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(
                                viewModel.hasVibeOverride ? Theme.accent : Theme.surfaceBorder,
                                lineWidth: viewModel.hasVibeOverride ? 1.5 : 1
                            )
                    )
            )
        }
        .disabled(viewModel.isRefreshing || !viewModel.cardsVisible)
        .opacity(viewModel.isRefreshing || !viewModel.cardsVisible ? 0.6 : 1.0)
    }

    // MARK: - Page Indicator

    private var pageIndicator: some View {
        HStack(spacing: 8) {
            ForEach(0..<viewModel.recommendations.count, id: \.self) { index in
                Circle()
                    .fill(index == viewModel.currentPage ? Theme.accent : Theme.textTertiary)
                    .frame(width: 8, height: 8)
                    .scaleEffect(index == viewModel.currentPage ? 1.2 : 1.0)
                    .animation(.easeInOut(duration: 0.2), value: viewModel.currentPage)
            }
        }
        .padding(.top, 12)
    }

    // MARK: - Refresh Button

    private var refreshButton: some View {
        Button {
            viewModel.requestRefresh()
        } label: {
            HStack(spacing: 8) {
                if viewModel.isRefreshing {
                    ProgressView()
                        .tint(Theme.textPrimary)
                        .scaleEffect(0.8)
                } else {
                    Image(uiImage: Lucide.refreshCw)
                        .renderingMode(.template)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 16, height: 16)
                }

                Text(viewModel.isRefreshing ? "Finding better options..." : "Refresh")
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(Theme.textPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Theme.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Theme.surfaceBorder, lineWidth: 1)
                    )
            )
        }
        .disabled(viewModel.isRefreshing || !viewModel.cardsVisible)
        .opacity(viewModel.isRefreshing || !viewModel.cardsVisible ? 0.6 : 1.0)
    }

    // MARK: - Loading State

    private var loadingState: some View {
        ForYouLoadingView()
    }

    // MARK: - Error State

    private func errorState(message: String) -> some View {
        VStack(spacing: 16) {
            Image(uiImage: Lucide.circleAlert)
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 40, height: 40)
                .foregroundStyle(Theme.textTertiary)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button {
                Task {
                    await generateWithMilestoneContext()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(uiImage: Lucide.refreshCw)
                        .renderingMode(.template)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 14, height: 14)

                    Text("Try Again")
                        .font(.subheadline.weight(.semibold))
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
                Text("Ready to find a gift?")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)

                Text("Tap below and we'll find personalized recommendations for your partner.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textTertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Button {
                Task { await generateWithMilestoneContext() }
            } label: {
                HStack(spacing: 8) {
                    Image(uiImage: Lucide.sparkles)
                        .renderingMode(.template)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 16, height: 16)
                    Text("Get Recommendations")
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Theme.accent)
                )
            }
            .padding(.horizontal, 40)
            .padding(.top, 4)
        }
    }
}

// MARK: - For You Loading Animation

/// Full-screen loading animation shown while AI gift recommendations are being generated.
///
/// Layout:
/// - Two pulsing concentric rings around a center icon
/// - Six decorative icons drifting around the perimeter
/// - Center 64×64 gradient tile with an icon that cycles through gift/date categories
/// - Cycling contextual messages
/// - Progress bar that fills toward 95% over ~28s (the parent owns final completion)
///
/// Mirrors the Figma Make design at figma.com/make/tD11m6jemTVFt7nfWVVdt3
private struct ForYouLoadingView: View {

    // Center icon cycle (every 2 seconds)
    private static let centerIcons: [UIImage] = [
        Lucide.bottleWine,
        Lucide.flower2,
        Lucide.utensilsCrossed,
        Lucide.popcorn,
        Lucide.gift,
        Lucide.heart,
        Lucide.music,
        Lucide.palette,
        Lucide.plane,
    ]

    // Decorative floating icons — positioned around the perimeter with staggered delays
    private struct FloatingIcon {
        let image: UIImage
        let x: CGFloat
        let y: CGFloat
        let size: CGFloat
        let delay: Double
        let opacity: Double
    }

    private static let floatingIcons: [FloatingIcon] = [
        .init(image: Lucide.gift,        x: -60, y: -70, size: 22, delay: 0.2, opacity: 0.55),
        .init(image: Lucide.shieldCheck, x: -80, y: -20, size: 20, delay: 0.4, opacity: 0.45),
        .init(image: Lucide.star,        x: -90, y:  40, size: 18, delay: 0.6, opacity: 0.45),
        .init(image: Lucide.lightbulb,   x:  60, y: -60, size: 20, delay: 0.3, opacity: 0.50),
        .init(image: Lucide.sparkles,    x:  80, y:  10, size: 16, delay: 0.5, opacity: 0.50),
        .init(image: Lucide.star,        x:  50, y:  60, size: 14, delay: 0.7, opacity: 0.40),
    ]

    private static let messages = [
        "Thinking about what they love...",
        "Finding the perfect vibe...",
        "Crafting your top picks...",
        "Almost ready..."
    ]

    @State private var iconIndex = 0
    @State private var messageIndex = 0
    @State private var showTimeHint = false
    @State private var ringPulse = false
    @State private var floatingActive = false
    @State private var centerWobble = false
    @State private var progress: CGFloat = 0

    var body: some View {
        VStack(spacing: 36) {
            // Animated icon cluster
            ZStack {
                // Pulsing concentric rings
                Circle()
                    .stroke(Theme.accent.opacity(0.25), lineWidth: 2)
                    .frame(width: 128, height: 128)
                    .scaleEffect(ringPulse ? 1.3 : 1.0)
                    .opacity(ringPulse ? 0 : 0.6)

                Circle()
                    .stroke(Theme.accent.opacity(0.25), lineWidth: 1)
                    .frame(width: 96, height: 96)
                    .scaleEffect(ringPulse ? 1.4 : 1.0)
                    .opacity(ringPulse ? 0 : 0.4)
                    .animation(
                        .easeInOut(duration: 2.5).repeatForever(autoreverses: false).delay(0.3),
                        value: ringPulse
                    )

                // Floating decorative icons
                ForEach(0..<Self.floatingIcons.count, id: \.self) { i in
                    let icon = Self.floatingIcons[i]
                    Image(uiImage: icon.image)
                        .renderingMode(.template)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: icon.size, height: icon.size)
                        .foregroundStyle(Theme.accent.opacity(icon.opacity))
                        .offset(
                            x: floatingActive ? icon.x : icon.x * 0.5,
                            y: floatingActive ? icon.y : icon.y * 0.5
                        )
                        .opacity(floatingActive ? icon.opacity : 0)
                        .scaleEffect(floatingActive ? 1.0 : 0.5)
                        .animation(
                            .easeInOut(duration: 4)
                                .repeatForever(autoreverses: true)
                                .delay(icon.delay),
                            value: floatingActive
                        )
                }

                // Center cycling icon — gradient rounded tile
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Theme.accent,
                                    Theme.accent.opacity(0.85),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 64, height: 64)
                        .shadow(color: Theme.accent.opacity(0.35), radius: 12, x: 0, y: 6)

                    Image(uiImage: Self.centerIcons[iconIndex])
                        .renderingMode(.template)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 32, height: 32)
                        .foregroundStyle(.white)
                        .id(iconIndex)
                        .transition(.scale(scale: 0.5).combined(with: .opacity))
                }
                .rotationEffect(.degrees(centerWobble ? 4 : -4))
                .scaleEffect(centerWobble ? 1.05 : 1.0)
                .animation(
                    .easeInOut(duration: 3).repeatForever(autoreverses: true),
                    value: centerWobble
                )
            }
            .frame(width: 200, height: 200)

            // Cycling contextual message
            VStack(spacing: 8) {
                Text(Self.messages[messageIndex])
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .id(messageIndex)
                    .transition(.opacity)

                Text("This usually takes about 30 seconds")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary.opacity(0.6))
                    .opacity(showTimeHint ? 1 : 0)
            }

            // Progress bar — fills to 95% over 28s, parent owns the final 100%
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Theme.surfaceBorder)
                    .frame(width: 200, height: 4)

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [Theme.accent.opacity(0.7), Theme.accent],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: 200 * progress, height: 4)
            }
        }
        .onAppear {
            // Start ring pulse
            withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: false)) {
                ringPulse = true
            }
            // Activate floating icons (they drift to their full positions and fade in)
            withAnimation {
                floatingActive = true
            }
            // Center wobble
            withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: true)) {
                centerWobble = true
            }
            // Animate progress to 95% over 28 seconds
            withAnimation(.linear(duration: 28)) {
                progress = 0.95
            }
            // Reveal time hint after 5s
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                withAnimation(.easeIn(duration: 0.6)) {
                    showTimeHint = true
                }
            }
        }
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in
            withAnimation(.easeInOut(duration: 0.4)) {
                iconIndex = (iconIndex + 1) % Self.centerIcons.count
            }
        }
        .onReceive(Timer.publish(every: 2.5, on: .main, in: .common).autoconnect()) { _ in
            withAnimation(.easeInOut(duration: 0.4)) {
                messageIndex = (messageIndex + 1) % Self.messages.count
            }
        }
    }
}

// MARK: - For You Climax Animation

/// Celebration animation that plays for ~2.3s when recommendations have just finished
/// generating. Features expanding shockwave rings, burst particles, falling confetti,
/// a spring-loaded checkmark, and orbiting celebration icons.
///
/// Mirrors the Figma Make climax sequence at figma.com/make/tD11m6jemTVFt7nfWVVdt3
private struct ForYouClimaxView: View {

    // MARK: Particle data (deterministic — computed once at type load)

    private struct BurstParticle {
        let x: CGFloat
        let y: CGFloat
        let size: CGFloat
        let color: Color
        let delay: Double
    }

    private struct ConfettiPiece {
        let x: CGFloat
        let yMid: CGFloat
        let yEnd: CGFloat
        let rotation: Double
        let color: Color
        let delay: Double
        let width: CGFloat
        let height: CGFloat
    }

    private struct OrbitIcon {
        let image: UIImage
        let angle: Double // degrees
        let color: Color
        let distance: CGFloat
    }

    private static let particleColors: [Color] = [
        Color(red: 0.98, green: 0.40, blue: 0.50),  // rose
        Color(red: 0.97, green: 0.55, blue: 0.65),  // pink
        Color(red: 0.99, green: 0.78, blue: 0.30),  // amber
        Color(red: 0.93, green: 0.30, blue: 0.65),  // fuchsia
        Color(red: 0.99, green: 0.62, blue: 0.30),  // orange
        Color(red: 0.98, green: 0.65, blue: 0.72),  // light rose
    ]

    private static let burstParticles: [BurstParticle] = (0..<16).map { i in
        let angle = (Double(i) / 16.0) * .pi * 2.0
        let distance: CGFloat = 90 + CGFloat((i * 17) % 50)
        let size: CGFloat = 4 + CGFloat((i * 13) % 6)
        return BurstParticle(
            x: cos(angle) * distance,
            y: sin(angle) * distance,
            size: size,
            color: particleColors[i % particleColors.count],
            delay: Double(i % 5) * 0.03
        )
    }

    private static let confettiPieces: [ConfettiPiece] = (0..<24).map { i in
        let angle = (Double(i) / 24.0) * .pi * 2.0 + Double(i % 5) * 0.1
        let distance: CGFloat = 110 + CGFloat((i * 11) % 80)
        let yEnd = sin(angle) * distance - 40
        return ConfettiPiece(
            x: cos(angle) * distance,
            yMid: yEnd * 0.5,
            yEnd: yEnd + 80,
            rotation: Double((i * 41) % 720) - 360,
            color: particleColors[i % particleColors.count],
            delay: Double(i % 6) * 0.05,
            width: i % 2 == 0 ? 6 : 4,
            height: i % 2 == 0 ? 10 : 6
        )
    }

    private static let orbitIcons: [OrbitIcon] = [
        .init(image: Lucide.heart,       angle: 0,   color: Color(red: 0.98, green: 0.30, blue: 0.45), distance: 70),
        .init(image: Lucide.star,        angle: 72,  color: Color(red: 0.99, green: 0.72, blue: 0.20), distance: 75),
        .init(image: Lucide.partyPopper, angle: 144, color: Color(red: 0.93, green: 0.30, blue: 0.65), distance: 70),
        .init(image: Lucide.sparkles,    angle: 216, color: Color(red: 0.99, green: 0.55, blue: 0.20), distance: 75),
        .init(image: Lucide.gift,        angle: 288, color: Color(red: 0.98, green: 0.40, blue: 0.55), distance: 70),
    ]

    // MARK: Animation state

    @State private var ringsExpanded = false
    @State private var burstActive = false
    @State private var confettiActive = false
    @State private var glowActive = false
    @State private var checkScale: CGFloat = 0
    @State private var checkRotation: Double = -180
    @State private var checkVisible = false
    @State private var orbitsActive = false
    @State private var orbitPulse = false
    @State private var textVisible = false

    var body: some View {
        VStack(spacing: 24) {
            ZStack {
                // Expanding shockwave rings
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .stroke(Theme.accent.opacity(0.5), lineWidth: ringsExpanded ? 1 : 3)
                        .frame(
                            width: ringsExpanded ? 250 : 60,
                            height: ringsExpanded ? 250 : 60
                        )
                        .opacity(ringsExpanded ? 0 : 0.6)
                        .animation(
                            .easeOut(duration: 1.2).delay(Double(i) * 0.15),
                            value: ringsExpanded
                        )
                }

                // Burst particles
                ForEach(0..<Self.burstParticles.count, id: \.self) { i in
                    let p = Self.burstParticles[i]
                    Circle()
                        .fill(p.color)
                        .frame(width: p.size, height: p.size)
                        .scaleEffect(burstActive ? 0.5 : 0)
                        .offset(
                            x: burstActive ? p.x : 0,
                            y: burstActive ? p.y : 0
                        )
                        .opacity(burstActive ? 0 : 1)
                        .animation(
                            .easeOut(duration: 0.9).delay(p.delay),
                            value: burstActive
                        )
                }

                // Confetti pieces
                ForEach(0..<Self.confettiPieces.count, id: \.self) { i in
                    let c = Self.confettiPieces[i]
                    RoundedRectangle(cornerRadius: 1)
                        .fill(c.color)
                        .frame(width: c.width, height: c.height)
                        .rotationEffect(.degrees(confettiActive ? c.rotation : 0))
                        .offset(
                            x: confettiActive ? c.x : 0,
                            y: confettiActive ? c.yEnd : 0
                        )
                        .opacity(confettiActive ? 0 : 1)
                        .scaleEffect(confettiActive ? 0.6 : 0)
                        .animation(
                            .easeOut(duration: 1.6).delay(0.1 + c.delay),
                            value: confettiActive
                        )
                }

                // Glowing backdrop
                Circle()
                    .fill(Theme.accent.opacity(0.18))
                    .frame(width: 112, height: 112)
                    .scaleEffect(glowActive ? 1.3 : 0)
                    .opacity(glowActive ? 0.6 : 0)

                // Center checkmark — gradient circle
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Theme.accent,
                                    Color(red: 0.93, green: 0.30, blue: 0.65),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 80, height: 80)
                        .shadow(color: Theme.accent.opacity(0.4), radius: 16, x: 0, y: 6)

                    Image(uiImage: Lucide.check)
                        .renderingMode(.template)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 40, height: 40)
                        .foregroundStyle(.white)
                        .scaleEffect(checkVisible ? 1 : 0)
                        .opacity(checkVisible ? 1 : 0)
                }
                .scaleEffect(checkScale)
                .rotationEffect(.degrees(checkRotation))

                // Orbiting celebration icons
                ForEach(0..<Self.orbitIcons.count, id: \.self) { i in
                    let icon = Self.orbitIcons[i]
                    let rad = (icon.angle * .pi) / 180
                    Image(uiImage: icon.image)
                        .renderingMode(.template)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 22, height: 22)
                        .foregroundStyle(icon.color)
                        .scaleEffect(orbitsActive ? (orbitPulse ? 1.2 : 1.0) : 0)
                        .offset(
                            x: orbitsActive ? cos(rad) * icon.distance : 0,
                            y: orbitsActive ? sin(rad) * icon.distance : 0
                        )
                        .animation(
                            .spring(response: 0.6, dampingFraction: 0.55)
                                .delay(0.3 + Double(i) * 0.08),
                            value: orbitsActive
                        )
                }
            }
            .frame(width: 260, height: 260)

            // Success text
            VStack(spacing: 6) {
                Text("Your matches are ready!")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Theme.textPrimary)

                Text("Tap to view your picks")
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
            }
            .opacity(textVisible ? 1 : 0)
            .offset(y: textVisible ? 0 : 20)
        }
        .onAppear {
            // Shockwave rings
            ringsExpanded = true

            // Burst particles
            burstActive = true

            // Glowing backdrop
            withAnimation(.easeOut(duration: 0.8)) {
                glowActive = true
            }

            // Confetti
            withAnimation {
                confettiActive = true
            }

            // Center checkmark — spring bounce in
            withAnimation(.spring(response: 0.55, dampingFraction: 0.55).delay(0.05)) {
                checkScale = 1
                checkRotation = 0
            }
            // Checkmark icon fades in slightly after the circle lands
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                withAnimation(.easeOut(duration: 0.3)) {
                    checkVisible = true
                }
            }

            // Orbiting icons spring outward
            orbitsActive = true

            // Continuous gentle pulse on orbit icons
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                    orbitPulse = true
                }
            }

            // Success text fades up
            withAnimation(.easeOut(duration: 0.5).delay(0.5)) {
                textVisible = true
            }
        }
    }
}

// MARK: - Refresh Loading Overlay

/// Compact loading overlay shown over existing recommendation cards during a refresh.
/// Uses a pulsing sparkles icon without orbiting elements to keep the overlay subtle.
private struct RefreshLoadingOverlay: View {

    @State private var pulse = false

    var body: some View {
        VStack(spacing: 14) {
            Image(uiImage: Lucide.sparkles)
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 32, height: 32)
                .foregroundStyle(Theme.accent)
                .scaleEffect(pulse ? 1.15 : 0.88)

            Text("Finding better options...")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 22)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Theme.surface)
                .shadow(color: Theme.overlayDim.opacity(0.25), radius: 14, x: 0, y: 4)
        )
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}

// MARK: - Selection Confirmation Sheet (Step 6.3)

/// Bottom sheet shown when the user taps "Select" on a recommendation card.
/// Displays full details and provides "Open in [Merchant]" and "Cancel" buttons.
struct SelectionConfirmationSheet: View {
    let item: RecommendationItemResponse
    let onConfirm: @MainActor () -> Void
    let onCancel: @MainActor () -> Void

    var body: some View {
        ZStack {
            Theme.backgroundGradient.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Header
                    Text("Confirm Selection")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(Theme.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 8)

                    // Type badge
                    HStack(spacing: 5) {
                        Image(systemName: typeIconSystemName)
                            .font(.caption2.weight(.bold))

                        Text(typeLabel)
                            .font(.caption.weight(.bold))
                            .textCase(.uppercase)
                    }
                    .foregroundStyle(Theme.accent)

                    // Title
                    Text(item.title)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)

                    // Description
                    if let description = item.description, !description.isEmpty {
                        Text(description)
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                    }

                    // Merchant + Price row
                    HStack {
                        if let merchantName = item.merchantName, !merchantName.isEmpty {
                            HStack(spacing: 5) {
                                Image(uiImage: Lucide.store)
                                    .renderingMode(.template)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 14, height: 14)

                                Text(merchantName)
                                    .font(.subheadline.weight(.medium))
                            }
                            .foregroundStyle(Theme.textSecondary)
                        }

                        Spacer()

                        if let priceCents = item.priceCents {
                            let prefix = item.priceConfidence == "estimated" ? "~" : ""
                            Text(prefix + formattedPrice(cents: priceCents, currency: item.currency))
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(Theme.textPrimary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    Capsule()
                                        .fill(Theme.surfaceElevated)
                                )
                        }
                    }

                    // Location (for experiences/dates)
                    if let location = item.location {
                        let parts = [location.address, location.city, location.state]
                            .compactMap { $0 }
                            .filter { !$0.isEmpty }
                        if !parts.isEmpty {
                            HStack(spacing: 5) {
                                Image(uiImage: Lucide.mapPin)
                                    .renderingMode(.template)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 14, height: 14)

                                Text(parts.joined(separator: ", "))
                                    .font(.caption)
                            }
                            .foregroundStyle(Theme.textTertiary)
                        }
                    }

                    Divider()
                        .overlay(Theme.surfaceBorder)

                    // Action buttons
                    VStack(spacing: 12) {
                        // Confirm button
                        Button(action: onConfirm) {
                            HStack(spacing: 8) {
                                Image(uiImage: Lucide.externalLink)
                                    .renderingMode(.template)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 16, height: 16)

                                Text(confirmButtonLabel)
                                    .font(.subheadline.weight(.semibold))
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(Theme.accent)
                            )
                        }
                        .buttonStyle(.plain)

                        // Cancel button
                        Button(action: onCancel) {
                            Text("Cancel")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(Theme.textSecondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(
                                    RoundedRectangle(cornerRadius: 14)
                                        .fill(Theme.surface)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 14)
                                                .stroke(Theme.surfaceBorder, lineWidth: 1)
                                        )
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            .scrollIndicators(.hidden)
        }
    }

    // MARK: - Helpers

    private var confirmButtonLabel: String {
        if let merchantName = item.merchantName, !merchantName.isEmpty {
            return "Open in \(merchantName)"
        }
        return "Open Link"
    }

    private var typeIconSystemName: String {
        switch item.recommendationType {
        case "gift": return "gift.fill"
        case "experience": return "sparkles"
        case "date": return "heart.fill"
        default: return "star.fill"
        }
    }

    private var typeLabel: String {
        switch item.recommendationType {
        case "gift": return "Gift"
        case "experience": return "Experience"
        case "date": return "Date"
        default: return item.recommendationType.capitalized
        }
    }

    private func formattedPrice(cents: Int, currency: String) -> String {
        let amount = Double(cents) / 100.0
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        formatter.maximumFractionDigits = (cents % 100 == 0) ? 0 : 2
        return formatter.string(from: NSNumber(value: amount)) ?? "$\(amount)"
    }
}

// MARK: - Refresh Reason Sheet (Step 6.4)

/// Bottom sheet shown when the user taps "Refresh" on the recommendations screen.
/// Presents 5 rejection reason options that control backend exclusion filtering.
struct RefreshReasonSheet: View {
    let onSelectReason: @MainActor (String) -> Void

    var body: some View {
        ZStack {
            Theme.backgroundGradient.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    // Header
                    Text("Why are you refreshing?")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(Theme.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 8)
                        .padding(.bottom, 4)

                    // Reason options
                    reasonButton(
                        id: "too_expensive",
                        label: "Too expensive",
                        icon: "arrow.up.circle"
                    )

                    reasonButton(
                        id: "too_cheap",
                        label: "Too cheap",
                        icon: "arrow.down.circle"
                    )

                    reasonButton(
                        id: "not_their_style",
                        label: "Not their style",
                        icon: "hand.thumbsdown"
                    )

                    reasonButton(
                        id: "already_have_similar",
                        label: "Already have something similar",
                        icon: "doc.on.doc"
                    )

                    reasonButton(
                        id: "show_different",
                        label: "Just show me different options",
                        icon: "arrow.triangle.2.circlepath"
                    )
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            .scrollIndicators(.hidden)
        }
    }

    // MARK: - Reason Button

    private func reasonButton(id: String, label: String, icon: String) -> some View {
        Button {
            onSelectReason(id)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.body.weight(.medium))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 24, height: 24)

                Text(label)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.textPrimary)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Theme.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Theme.surfaceBorder, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Vibe Override Sheet (Step 6.5)

/// Bottom sheet for temporarily overriding vibe preferences for this session only.
/// Displays the 8 vibe options in a 2-column grid matching the onboarding vibes aesthetic.
/// The override does not modify the partner vault — it only affects the current recommendation session.
struct VibeOverrideSheet: View {
    @State private var selectedVibes: Set<String>
    let onSave: @MainActor (Set<String>) -> Void
    let onClear: @MainActor () -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 2)

    init(
        selectedVibes: Set<String>,
        onSave: @escaping @MainActor (Set<String>) -> Void,
        onClear: @escaping @MainActor () -> Void
    ) {
        self._selectedVibes = State(initialValue: selectedVibes)
        self.onSave = onSave
        self.onClear = onClear
    }

    var body: some View {
        ZStack {
            Theme.backgroundGradient.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                VStack(spacing: 8) {
                    Text("Adjust Vibe")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(Theme.textPrimary)

                    Text("Temporarily change vibes for this session.\nYour vault preferences won't be modified.")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(2)
                }
                .padding(.top, 16)
                .padding(.bottom, 16)

                // Vibe grid
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(Constants.vibeOptions, id: \.self) { vibe in
                            VibeOverrideCard(
                                vibe: vibe,
                                displayName: OnboardingVibesView.displayName(for: vibe),
                                description: OnboardingVibesView.vibeDescription(for: vibe),
                                icon: OnboardingVibesView.vibeIcon(for: vibe),
                                gradient: OnboardingVibesView.vibeGradient(for: vibe),
                                isSelected: selectedVibes.contains(vibe)
                            ) {
                                toggleVibe(vibe)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
                }

                // Counter + buttons
                VStack(spacing: 12) {
                    // Selection counter
                    HStack(spacing: 4) {
                        Text("\(selectedVibes.count) selected")
                            .fontWeight(.semibold)

                        if selectedVibes.isEmpty {
                            Text("(pick at least 1)")
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.subheadline)
                        }
                    }
                    .font(.subheadline)
                    .foregroundStyle(Theme.accent)

                    // Save button
                    Button {
                        onSave(selectedVibes)
                    } label: {
                        HStack(spacing: 8) {
                            Image(uiImage: Lucide.sparkles)
                                .renderingMode(.template)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 16, height: 16)

                            Text("Apply & Refresh")
                                .font(.subheadline.weight(.semibold))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(Theme.accent)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(selectedVibes.isEmpty)
                    .opacity(selectedVibes.isEmpty ? 0.5 : 1.0)

                    // Clear override button
                    Button {
                        onClear()
                    } label: {
                        Text("Reset to Vault Defaults")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Theme.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(Theme.surface)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14)
                                            .stroke(Theme.surfaceBorder, lineWidth: 1)
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
        }
    }

    private func toggleVibe(_ vibe: String) {
        if selectedVibes.contains(vibe) {
            selectedVibes.remove(vibe)
        } else {
            selectedVibes.insert(vibe)
        }
    }
}

// MARK: - Vibe Override Card

/// A compact vibe card for the override sheet, matching the onboarding vibe card aesthetic.
private struct VibeOverrideCard: View {
    let vibe: String
    let displayName: String
    let description: String
    let icon: UIImage
    let gradient: LinearGradient
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                gradient

                LinearGradient(
                    colors: [.clear, .black.opacity(0.40)],
                    startPoint: .top,
                    endPoint: .bottom
                )

                // Large icon watermark
                Image(uiImage: icon)
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 32, height: 32)
                    .foregroundStyle(.white.opacity(0.18))
                    .offset(x: 28, y: -16)

                // Content
                VStack(alignment: .leading, spacing: 3) {
                    Spacer()

                    Image(uiImage: icon)
                        .renderingMode(.template)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 18, height: 18)
                        .foregroundStyle(.white.opacity(0.85))

                    Text(displayName)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)

                    Text(description)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.70))
                        .shadow(color: .black.opacity(0.4), radius: 1, x: 0, y: 1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)

                // Checkmark badge
                if isSelected {
                    VStack {
                        HStack {
                            Spacer()
                            Circle()
                                .fill(Color.pink)
                                .frame(width: 22, height: 22)
                                .overlay {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(.white)
                                }
                                .shadow(color: .black.opacity(0.3), radius: 3, x: 0, y: 1)
                        }
                        Spacer()
                    }
                    .padding(8)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .aspectRatio(1.4, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(
                        isSelected ? Color.pink : Color.white.opacity(0.06),
                        lineWidth: isSelected ? 2.5 : 0.5
                    )
            )
            .scaleEffect(isSelected ? 1.02 : 1.0)
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.25), value: isSelected)
    }
}

// MARK: - Previews

#Preview("Loading") {
    RecommendationsView()
}

// MARK: - Confirmation Sheet Previews (Step 6.3)

private let _previewGiftItem: RecommendationItemResponse = {
    let json = """
    {
        "id": "preview-1",
        "recommendation_type": "gift",
        "title": "Ceramic Pottery Class for Two",
        "description": "A hands-on pottery experience where you and your partner create custom pieces together. Includes all materials and firing.",
        "price_cents": 8500,
        "currency": "USD",
        "price_confidence": "verified",
        "external_url": "https://example.com/pottery",
        "image_url": null,
        "merchant_name": "Clay Studio Brooklyn",
        "source": "yelp",
        "location": null,
        "interest_score": 0.85,
        "vibe_score": 0.72,
        "love_language_score": 0.9,
        "final_score": 0.82,
        "matched_interests": ["Art", "Cooking"],
        "matched_vibes": ["bohemian"],
        "matched_love_languages": ["quality_time"]
    }
    """.data(using: .utf8)!
    return try! JSONDecoder().decode(RecommendationItemResponse.self, from: json)
}()

private let _previewExperienceItem: RecommendationItemResponse = {
    let json = """
    {
        "id": "preview-2",
        "recommendation_type": "experience",
        "title": "Private Sunset Sailing on the Bay",
        "description": "Enjoy a 2-hour private sailing trip with champagne and charcuterie as the sun sets over the bay.",
        "price_cents": 24900,
        "currency": "USD",
        "price_confidence": "verified",
        "external_url": "https://example.com/sailing",
        "image_url": null,
        "merchant_name": "Bay Sailing Co.",
        "source": "yelp",
        "location": {
            "city": "San Francisco",
            "state": "CA",
            "country": "US",
            "address": "Pier 39"
        },
        "interest_score": 0.9,
        "vibe_score": 0.8,
        "love_language_score": 0.7,
        "final_score": 0.8,
        "matched_interests": ["Travel"],
        "matched_vibes": ["romantic", "quiet_luxury"],
        "matched_love_languages": ["quality_time"]
    }
    """.data(using: .utf8)!
    return try! JSONDecoder().decode(RecommendationItemResponse.self, from: json)
}()

#Preview("Confirmation Sheet — Gift") {
    SelectionConfirmationSheet(
        item: _previewGiftItem,
        onConfirm: {},
        onCancel: {}
    )
}

#Preview("Confirmation Sheet — Experience with Location") {
    SelectionConfirmationSheet(
        item: _previewExperienceItem,
        onConfirm: {},
        onCancel: {}
    )
}

#Preview("Refresh Reason Sheet") {
    RefreshReasonSheet(onSelectReason: { _ in })
    }

// MARK: - Vibe Override Sheet Previews (Step 6.5)

#Preview("Vibe Override — Empty") {
    VibeOverrideSheet(
        selectedVibes: [],
        onSave: { _ in },
        onClear: {}
    )
}

#Preview("Vibe Override — 2 Selected") {
    VibeOverrideSheet(
        selectedVibes: ["quiet_luxury", "romantic"],
        onSave: { _ in },
        onClear: {}
    )
}
