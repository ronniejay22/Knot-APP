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
//  June 23, 2026: Reuse the browse-only `SpotlightCarouselView` (the onboarding
//  reveal) so the main-app recommendation experience matches onboarding exactly —
//  no swipe voting, Refresh, or Adjust Vibe. Saving happens on the detail page.
//

import SwiftUI
import StoreKit
import LucideIcons

/// Displays the first picks in the same browse-only carousel as the onboarding
/// reveal — one Spotlight card at a time, swipe to page, tap "See Details".
///
/// Layout:
/// ```
/// ┌─────────────────────────────────────┐
/// │  ← Recommendations                  │
/// ├─────────────────────────────────────┤
/// │                                     │
/// │  ┌─────────────────────────────┐    │
/// │  │      SpotlightCard (1/3)    │    │
/// │  │   ← swipe to page →        │    │
/// │  └─────────────────────────────┘    │
/// │              ● ● ○                   │
/// └─────────────────────────────────────┘
/// ```
struct RecommendationsView: View {
    /// Optional milestone ID for milestone-contextual recommendations.
    var milestoneId: String?

    /// Display context for the milestone header (nil for "just because" mode).
    var milestoneContext: MilestoneDisplayContext?

    /// When true (the milestone push tap-through), load the PRE-GENERATED
    /// recommendations stored when the notification fired instead of
    /// re-running the generation pipeline. Falls back to generating when no
    /// stored batch exists.
    var preferPregenerated: Bool

    /// True when hosted inside a full-screen cover (no KnotTabBar below),
    /// so the tab-bar bottom clearance isn't needed.
    var isModal: Bool

    /// Absent in the two hosts with no tab bar (the full-screen cover and
    /// onboarding), so every use is optional-chained and no-ops there.
    @Environment(AppChrome.self) private var chrome: AppChrome?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.requestReview) private var requestReview
    @Environment(AuthViewModel.self) private var authViewModel

    @State private var viewModel: RecommendationsViewModel

    /// Defaults preserve every existing call site (ForYouView pushes, previews).
    /// The `viewModel:` parameter lets the screenshot harness inject a
    /// pre-seeded VM (with `hasLoadedInitially = true`) so no networking runs.
    init(
        milestoneId: String? = nil,
        milestoneContext: MilestoneDisplayContext? = nil,
        preferPregenerated: Bool = false,
        isModal: Bool = false,
        viewModel: RecommendationsViewModel = RecommendationsViewModel()
    ) {
        self.milestoneId = milestoneId
        self.milestoneContext = milestoneContext
        self.preferPregenerated = preferPregenerated
        self.isModal = isModal
        _viewModel = State(initialValue: viewModel)
        // Seed the *first* frame's answer from the flag, before `.task` has run
        // and set it from the operation actually in flight. Without this the
        // push tap-through resolves to `.loading` for one frame and flashes the
        // coral generation screen under the entry modal — the exact regression
        // Step 19.30 removed.
        _isPregeneratedRead = State(initialValue: preferPregenerated)
        // The push tap-through's first phase is `.silent`, everything else's is
        // `.loading` (via `awaitingFirstLoad`). Matching that here keeps the
        // first frame's chrome correct before `onChange` has run.
        _loaderIsCovering = State(initialValue: !preferPregenerated)
    }

    @State private var isBriefingExpanded = false
    @State private var isBriefingDismissed = false

    /// True when the push tap-through found no stored recommendations. Shows
    /// an honest opt-in state rather than silently running a ~30s generation.
    @State private var pregeneratedMissing = false

    /// True while the *currently running* load is the pre-generated read.
    ///
    /// Deliberately tracks the operation in flight rather than the
    /// `preferPregenerated` constructor flag. That flag stays true for the
    /// whole tap-through, including when the user taps "Find picks now" from
    /// `pregeneratedMissingState` — which runs the real ~30s pipeline. Gating
    /// on the flag would leave them staring at a blank gradient for half a
    /// minute after explicitly opting into the wait.
    @State private var isPregeneratedRead: Bool

    /// True until `.task` has decided what to do.
    ///
    /// On the very first frame the view model is empty and not yet loading, so
    /// the phase would resolve to `.empty` and render the "Ready to find a
    /// gift?" CTA. That was a single invisible frame before this screen
    /// animated its phase changes; with the crossfade it became a visible
    /// 0.42s flash of the empty state ahead of the loader. `OnboardingCompletionView`
    /// guards the same gap with `vaultReady`.
    @State private var awaitingFirstLoad = true

    /// True while the loading screen is on screen, including its 420ms recede.
    /// Owned here rather than read off `revealPhase` because the chrome has to
    /// stay out of the way until the coral surface has actually gone; the
    /// overlay writes it. Seeded to match the first frame's phase.
    @State private var loaderIsCovering: Bool

    /// Which surface the reveal should show, resolved by the shared pure
    /// function in `RecommendationsLoadingView` so this screen and the
    /// in-onboarding reveal cannot drift apart.
    private var revealPhase: RecommendationRevealPhase {
        RecommendationsLoadingView.phase(
            isLoading: viewModel.isLoading || awaitingFirstLoad,
            isPregeneratedRead: isPregeneratedRead,
            hasError: viewModel.errorMessage != nil,
            pregeneratedMissing: pregeneratedMissing,
            isEmpty: viewModel.recommendations.isEmpty
        )
    }

    /// Whether the navigation bar shows above this screen.
    ///
    /// The loading screen is a full-bleed brand surface carrying its own "Knot"
    /// wordmark, so a navigation bar over it is both a second header and
    /// dark-plum type on coral.
    ///
    /// Declared on `body` — the outermost node of this view's own subtree —
    /// rather than down inside `suggestionsContent`'s switch. Toolbar
    /// visibility resolves to the declaration nearest the destination's root,
    /// so the inner version lost to `ForYouView`'s wrapper and never took
    /// effect on a real push, while still *looking* correct in the screenshot
    /// harness (which mounted this view as a bare `NavigationStack` root with
    /// no wrapper above it). `RecommendationsView` is the sole owner now, and
    /// `ForYouView` no longer declares anything for this destination.
    ///
    /// Never hidden inside a full-screen cover: there the bar carries the only
    /// way out — `MilestoneRecommendationsCoverView`'s X — and taking it away
    /// would strand the user for the whole ~25s run.
    /// Keyed on whether the loading screen is still *on screen* rather than on
    /// the phase: the coral surface outlives `.loading` by the 420ms of its
    /// recede, and restoring the bar at the phase change pops a dark-plum
    /// inline title over it for that whole time.
    static func navigationBarVisibility(
        isModal: Bool,
        isCoveredByLoader: Bool
    ) -> Visibility {
        if isModal { return .visible }
        return isCoveredByLoader ? .hidden : .visible
    }

    /// Whether this screen wants `MainTabView`'s `KnotTabBar` to stand down.
    ///
    /// `isModal` is excluded rather than merely irrelevant: a full-screen cover
    /// inherits the presenting view's environment, so the modal host *can*
    /// reach `AppChrome` even though its own tab bar is already covered. Left
    /// ungated it would animate the bar out behind the cover and back in on
    /// dismissal, for no visible benefit.
    static func shouldHideTabBar(
        isModal: Bool,
        isCoveredByLoader: Bool
    ) -> Bool {
        !isModal && isCoveredByLoader
    }

    private var navigationBarVisibility: Visibility {
        Self.navigationBarVisibility(isModal: isModal, isCoveredByLoader: loaderIsCovering)
    }

    var body: some View {
        recommendationsBody
            .background(Theme.backgroundGradient.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(navigationBarVisibility, for: .navigationBar)
            // The tab bar belongs to `MainTabView`, an ancestor, so it can only
            // be hidden by telling it to stand down. `initial: true` covers the
            // common case where the screen is already `.loading` on its first
            // frame — an `onChange` alone would not fire until the phase moved.
            // Driven by `loaderIsCovering`, not the phase, so the tab bar comes
            // back only once the coral surface has finished receding.
            .onChange(of: loaderIsCovering, initial: true) { _, covering in
                chrome?.isTabBarHidden = Self.shouldHideTabBar(
                    isModal: isModal,
                    isCoveredByLoader: covering
                )
            }
            // Restore on the way out. Without this, backing out mid-generation
            // (or an error tearing the screen down) would leave the whole app
            // with no tab bar and no way to get it back.
            .onDisappear {
                chrome?.isTabBarHidden = false
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    if let ctx = milestoneContext {
                        VStack(spacing: 1) {
                            Text(ctx.name)
                                .knotFont(Theme.Typography.cta)
                                .foregroundStyle(Theme.textPrimary)
                            Text(MilestonesViewModel.daysUntilText(ctx.daysUntil))
                                .knotFont(Theme.Typography.label)
                                .foregroundStyle(Theme.textSecondary)
                        }
                    } else {
                        Text("Recommendations")
                            .knotFont(Theme.Typography.cardTitle)
                            .foregroundStyle(Theme.textPrimary)
                    }
                }
            }
            .task {
                // The milestone id travels with the save so the event's detail
                // screen can list the ideas saved for it.
                viewModel.configure(modelContext: modelContext, milestoneId: milestoneId)
                // A harness-seeded VM (or a tab revisit) already has content —
                // skip networking entirely.
                guard !viewModel.hasLoadedInitially else {
                    awaitingFirstLoad = false
                    return
                }
                await loadContent()
                awaitingFirstLoad = false
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
            // Purchase prompt sheet (Step 9.4)
            .sheet(isPresented: $viewModel.showPurchasePromptSheet) {
                if let item = viewModel.pendingHandoffRecommendation {
                    PurchasePromptSheet(
                        title: item.title,
                        merchantName: item.merchantName,
                        recommendationType: item.recommendationType,
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
            // Spotlight detail page (June 12, 2026) — opened by tapping a deck card.
            .fullScreenCover(item: $viewModel.selectedDetailItem) { item in
                RecommendationDetailView(
                    item: item,
                    partnerName: viewModel.partnerName,
                    isSaved: viewModel.isSaved(item.id),
                    onOpenMerchant: { Task { await viewModel.openMerchantFromDetail(item) } },
                    onSave: { viewModel.saveRecommendation(item) },
                    onDismiss: { viewModel.dismissDetail() }
                )
            }
    }

    // MARK: - Recommendations Body

    /// The full recommendations UI — a browse-only carousel matching the
    /// onboarding reveal, with no voting or action buttons.
    ///
    /// The loading screen hands straight off to the picks. There is no
    /// celebration in between: the 2.3-second confetti splash that used to sit
    /// here was an interruption between the user finishing waiting and seeing
    /// what they waited for, and its "Tap to view your picks" line was a lie —
    /// it carried no tap gesture and dismissed itself on a timer.
    private var recommendationsBody: some View {
        ZStack {
            Theme.backgroundGradient.ignoresSafeArea()
            suggestionsContent
        }
        // Above the background too, so the coral surface is genuinely
        // full-bleed while it is receding.
        .recommendationLoadingOverlay(phase: revealPhase, isCovering: $loaderIsCovering)
        // Opens the transaction the phase change runs in. The hand-off's real
        // timing lives on the two transitions themselves
        // (`.loadingHandoff` / `.revealIn`), which override this — they are
        // sequential, with different curves and durations per half, which a
        // single ambient animation cannot express.
        .animation(.timingCurve(0.4, 0, 0.2, 1, duration: RecommendationsLoadingView.handoffExitDuration),
                   value: revealPhase)
    }

    // MARK: - Content Loading

    /// Single entry point for the initial load and the error/empty retries.
    ///
    /// Push tap-through (`preferPregenerated`): fetch the stored batch — this
    /// is instant and is exactly what the push described. If nothing is
    /// stored we do NOT silently start a ~30s generation; the user gets an
    /// honest state with a CTA (see `pregeneratedMissing`) so a tap never
    /// turns into a surprise wait.
    private func loadContent() async {
        if preferPregenerated, let mId = milestoneId {
            pregeneratedMissing = false
            isPregeneratedRead = true
            let displayed = await viewModel.loadPregeneratedRecommendations(milestoneId: mId)
            if !displayed {
                pregeneratedMissing = true
            }
        } else {
            await generateWithMilestoneContext()
        }
    }

    // MARK: - Milestone-Aware Generation

    /// Generates recommendations using the milestone context passed from ForYouView,
    /// or falls back to "just_because" when no milestone context is provided.
    /// When a milestone ID is known but its display context lookup failed, the
    /// generation stays milestone-scoped ("major_milestone" occasion) instead of
    /// silently dropping the milestone.
    private func generateWithMilestoneContext() async {
        // A real pipeline run, whatever the constructor flag says — the
        // "Find picks now" retry reaches here with `preferPregenerated` still
        // true. The user opted into the wait; show them the progress.
        isPregeneratedRead = false
        if let mId = milestoneId {
            await viewModel.generateRecommendations(
                occasionType: milestoneContext?.occasionType ?? "major_milestone",
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
                    .knotFont(Theme.Typography.cta)
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
                .knotFont(Theme.Typography.label)
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
                    .knotFont(Theme.Typography.label)
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
        switch revealPhase {
        case .loading, .silent:
            // Neither case draws anything here.
            //
            // `.loading` is covered by `recommendationLoadingOverlay`, applied
            // below — the loading screen is an overlay rather than a branch of
            // this switch so that its recede can actually animate; a removal
            // transition on a branch is unmounted instantly (see the note on
            // `RecommendationLoadingOverlay`).
            //
            // `.silent` is a sub-second read of an already-stored batch, where
            // showing the generation screen would misrepresent the wait.
            Color.clear
        case .error:
            errorState(message: viewModel.errorMessage ?? "")
        case .missing:
            pregeneratedMissingState
        case .empty:
            emptyState
        case .loaded:
            recommendationsContent
                .transition(.revealIn)
        }
    }

    // MARK: - Recommendations Content

    private var recommendationsContent: some View {
        VStack(spacing: 0) {
            // Milestone briefing card (shown when a contextual briefing was generated)
            if let briefing = viewModel.briefingText, !isBriefingDismissed {
                briefingCard(briefing)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 16)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // Browse-only carousel — the same first-picks reveal used by the
            // onboarding completion screen (`OnboardingCompletionView`). The user
            // swipes between the Spotlight cards (page dots track position) and taps
            // "See Details" to open a pick. There's no save/pass voting here —
            // saving happens on the detail page.
            SpotlightCarouselView(
                items: viewModel.recommendations,
                partnerName: viewModel.partnerName,
                isSaved: { viewModel.isSaved($0) },
                onOpenDetail: { viewModel.openDetail($0) }
            )
            .padding(.top, 8)
            // Clearance above the KnotTabBar (~93pt content + home indicator).
            // SwiftUI's `safeAreaInset` from MainTabView does not propagate through
            // `navigationDestination` pushes, so we pad explicitly here. Inside a
            // full-screen cover (push tap-through) there is no tab bar, so only a
            // small breathing-room pad is needed.
            .padding(.bottom, isModal ? 24 : 100)
            .opacity(viewModel.cardsVisible ? 1 : 0)
            .animation(.easeInOut(duration: 0.3), value: viewModel.cardsVisible)
        }
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
                .knotFont(Theme.Typography.body)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button {
                Task {
                    await loadContent()
                }
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
    }

    // MARK: - Pre-Generated Missing State (push tap-through)

    /// Shown when a tapped push has no stored recommendations — rare, since
    /// the backend only sends a push after storing them. Rather than silently
    /// running a ~30s generation (which is exactly the surprise wait this
    /// feature exists to avoid), it explains the situation and lets the user
    /// opt in.
    private var pregeneratedMissingState: some View {
        VStack(spacing: 20) {
            Image(uiImage: Lucide.sparkles)
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 40, height: 40)
                .foregroundStyle(Theme.textTertiary)

            VStack(spacing: 8) {
                Text("We're still putting these together")
                    .knotFont(Theme.Typography.cardTitle)
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.center)

                Text("Your picks for this date aren't ready yet. Want us to find some now? It takes about half a minute.")
                    .knotFont(Theme.Typography.body)
                    .foregroundStyle(Theme.textTertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Button {
                Task {
                    pregeneratedMissing = false
                    await generateWithMilestoneContext()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(uiImage: Lucide.sparkles)
                        .renderingMode(.template)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 16, height: 16)
                    Text("Find picks now")
                        .knotFont(Theme.Typography.cta)
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
                    .knotFont(Theme.Typography.cardTitle)
                    .foregroundStyle(Theme.textPrimary)

                Text("Tap below and we'll find personalized recommendations for your partner.")
                    .knotFont(Theme.Typography.body)
                    .foregroundStyle(Theme.textTertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Button {
                Task { await loadContent() }
            } label: {
                HStack(spacing: 8) {
                    Image(uiImage: Lucide.sparkles)
                        .renderingMode(.template)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 16, height: 16)
                    Text("Get Recommendations")
                        .knotFont(Theme.Typography.cta)
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
                        .knotFont(Theme.Typography.sectionHeader)
                        .foregroundStyle(Theme.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 8)

                    // Type badge
                    HStack(spacing: 5) {
                        Image(systemName: typeIconSystemName)
                            .knotFont(Theme.Typography.label)

                        Text(typeLabel)
                            .knotFont(Theme.Typography.label)
                            .textCase(.uppercase)
                    }
                    .foregroundStyle(Theme.accent)

                    // Title
                    Text(item.title)
                        .knotFont(Theme.Typography.cardTitle)
                        .foregroundStyle(Theme.textPrimary)

                    // Description
                    if let description = item.description, !description.isEmpty {
                        Text(description)
                            .knotFont(Theme.Typography.body)
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
                                    .knotFont(Theme.Typography.cta)
                            }
                            .foregroundStyle(Theme.textSecondary)
                        }

                        Spacer()

                        if let priceCents = item.priceCents {
                            let prefix = item.priceConfidence == "estimated" ? "~" : ""
                            Text(prefix + formattedPrice(cents: priceCents, currency: item.currency))
                                .knotFont(Theme.Typography.cta)
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
                                    .knotFont(Theme.Typography.label)
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
                                    .knotFont(Theme.Typography.cta)
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
                                .knotFont(Theme.Typography.cta)
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
                        .knotFont(Theme.Typography.sectionHeader)
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
                    .knotFont(Theme.Typography.cta)
                    .foregroundStyle(Theme.accent)
                    .frame(width: 24, height: 24)

                Text(label)
                    .knotFont(Theme.Typography.cta)
                    .foregroundStyle(Theme.textPrimary)

                Spacer()

                Image(systemName: "chevron.right")
                    .knotFont(Theme.Typography.label)
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
                        .knotFont(Theme.Typography.sectionHeader)
                        .foregroundStyle(Theme.textPrimary)

                    Text("Temporarily change vibes for this session.\nYour vault preferences won't be modified.")
                        .knotFont(Theme.Typography.label)
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
                            .knotFont(Theme.Typography.cta)

                        if selectedVibes.isEmpty {
                            Text("(pick at least 1)")
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                                .knotFont(Theme.Typography.body)
                        }
                    }
                    .knotFont(Theme.Typography.body)
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
                                .knotFont(Theme.Typography.cta)
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
                            .knotFont(Theme.Typography.cta)
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
                        .knotFont(Theme.Typography.cta)
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)

                    Text(description)
                        .knotFont(Theme.Typography.label)
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

// MARK: - Session Hints Sheet (Step 18.6)

/// Bottom sheet that lets the user capture a fresh hint inside the recommendation
/// refresh flow. The hint is persisted via `HintService` so the next pipeline run
/// can pick it up via pgvector and weight the recommendations accordingly.
///
/// The sheet is purely optional — Skip dismisses without writing.
struct SessionHintsSheet: View {
    let onSubmit: @MainActor (String) -> Void
    let onSkip: @MainActor () -> Void

    @State private var text: String = ""
    @FocusState private var isFieldFocused: Bool

    private var trimmedCount: Int {
        text.trimmingCharacters(in: .whitespacesAndNewlines).count
    }

    private var canSubmit: Bool {
        trimmedCount > 0 && text.count <= Constants.Validation.maxHintLength
    }

    private var characterCountColor: Color {
        if text.count > Constants.Validation.maxHintLength {
            return .red
        } else if text.count >= 450 {
            return .red.opacity(0.8)
        } else {
            return Theme.textTertiary
        }
    }

    var body: some View {
        ZStack {
            Theme.backgroundGradient.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 16) {
                // Header
                VStack(alignment: .leading, spacing: 6) {
                    Text("Anything new she's mentioned?")
                        .knotFont(Theme.Typography.sectionHeader)
                        .foregroundStyle(Theme.textPrimary)

                    Text("A quick note here will shape your next set of picks. Skip if nothing comes to mind.")
                        .knotFont(Theme.Typography.label)
                        .foregroundStyle(Theme.textSecondary)
                        .lineSpacing(2)
                }
                .padding(.top, 8)

                // Multi-line input
                KnotInput(
                    text: $text,
                    placeholder: "e.g., she mentioned wanting to try that ramen spot in Hayes Valley",
                    style: .multiLine,
                    minHeight: 90,
                    maxHeight: 140,
                    validationState: isFieldFocused ? .focused : .neutral
                )
                .focused($isFieldFocused)

                // Character counter
                HStack {
                    Spacer()
                    Text("\(text.count)/\(Constants.Validation.maxHintLength)")
                        .knotFont(Theme.Typography.label)
                        .foregroundStyle(characterCountColor)
                }

                Spacer(minLength: 0)

                // Action row — Skip + Submit
                HStack(spacing: 12) {
                    Button {
                        onSkip()
                    } label: {
                        Text("Skip")
                            .knotFont(Theme.Typography.cta)
                            .foregroundStyle(Theme.textPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
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

                    Button {
                        onSubmit(text)
                    } label: {
                        Text("Submit & Refresh")
                            .knotFont(Theme.Typography.cta)
                            .foregroundStyle(canSubmit ? .white : Theme.textTertiary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(canSubmit ? Theme.accent : Theme.surface)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(
                                                canSubmit ? Theme.accent : Theme.surfaceBorder,
                                                lineWidth: 1
                                            )
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSubmit)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .onAppear {
            // Focus the field automatically so the user can start typing
            // without an extra tap.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                isFieldFocused = true
            }
        }
    }
}

#Preview("Session Hints Sheet") {
    SessionHintsSheet(onSubmit: { _ in }, onSkip: {})
}
