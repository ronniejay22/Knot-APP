//
//  RecentPicksSheet.swift
//  Knot
//
//  Step 19.63 — the sheet behind the Journal's "View recent recommendations".
//
//  Shows the picks a milestone push pre-generated, for a user who never tapped
//  that push. Framed like the event's own detail screen (`MilestoneDetailView`:
//  header · hero · DATE/COUNTDOWN/RECIPIENT card) and then the same headline +
//  photo cards the recommendations feed uses, so a pick opens the same detail
//  page from here as from anywhere else. Presented as a stock `.sheet` — it
//  covers `KnotTabBar` on its own and the grab handle plus scrim say "glance
//  and go" — rather than the full-screen cover the push tap-through uses.
//
//  Opening it counts as viewing the push: the host marks every notification
//  behind the alert viewed from `.task`, before the batch is even read.
//

import SwiftUI
import SwiftData
import LucideIcons

/// The stored picks behind an untapped milestone push, in an event-style sheet.
struct RecentPicksSheet: View {

    let alert: PendingPicksAlert
    let partnerName: String
    /// Urgency tier for the countdown's colour, computed by `ForYouViewModel`.
    let urgency: MilestoneUrgency
    /// Fired once, from `.task`: the host marks every push in `alert` viewed.
    let onViewed: @MainActor () -> Void
    /// The empty state's "Get ideas". The host dismisses this sheet, then
    /// pushes `RecommendationsView` for the milestone — the Journal's
    /// `pendingIdeasMilestone` hand-off, shared with the other presentations.
    let onGetIdeas: @MainActor () -> Void
    let onDismiss: @MainActor () -> Void

    @Environment(\.modelContext) private var modelContext

    /// `RecommendationsViewModel` rather than a sheet-specific one:
    /// `loadPregeneratedRecommendations` already yields loading / error /
    /// empty / loaded for a stored batch, and `isSaved`, `openDetail`,
    /// `saveRecommendation` and `openMerchantFromDetail` are exactly what the
    /// detail cover needs. Injectable so a harness can seed it loaded.
    @State private var viewModel: RecommendationsViewModel

    /// `loadPregeneratedRecommendations` returned false — nothing is stored.
    @State private var batchMissing = false

    /// The first frame's guard, as in `RecommendationsView`: until `.task` has
    /// run, `isLoading` is still false and the phase would resolve to `.empty`.
    @State private var awaitingFirstLoad = true

    private static let cornerRadius: CGFloat = 24

    init(
        alert: PendingPicksAlert,
        partnerName: String,
        urgency: MilestoneUrgency,
        onViewed: @escaping @MainActor () -> Void,
        onGetIdeas: @escaping @MainActor () -> Void,
        onDismiss: @escaping @MainActor () -> Void,
        viewModel: RecommendationsViewModel = RecommendationsViewModel()
    ) {
        self.alert = alert
        self.partnerName = partnerName
        self.urgency = urgency
        self.onViewed = onViewed
        self.onGetIdeas = onGetIdeas
        self.onDismiss = onDismiss
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        ZStack {
            Theme.backgroundGradient.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    headerRow
                    MilestoneArtworkHero(milestone: alert.milestone)
                    MilestoneMetaCard(milestone: alert.milestone, partnerName: partnerName, urgency: urgency)
                    picksSection
                }
                .padding(.horizontal, 20)
                // Clears the sheet's drag indicator.
                .padding(.top, Theme.Spacing.xxl)
                .padding(.bottom, 40)
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(Self.cornerRadius)
        .task {
            viewModel.configure(modelContext: modelContext, milestoneId: alert.milestone.id)
            onViewed()
            // A view model handed in already loaded (harness) keeps its content.
            guard !viewModel.hasLoadedInitially else {
                awaitingFirstLoad = false
                return
            }
            await load()
            awaitingFirstLoad = false
        }
        // The same detail page `RecommendationsView` opens, wired identically.
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

    // MARK: - Header

    private var headerRow: some View {
        HStack(spacing: 12) {
            Text(alert.milestone.milestoneName)
                .knotFont(Theme.Typography.sectionHeaderSemibold)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            Spacer(minLength: 0)

            // A plain Button rather than `KnotIconButton(.ghost)`: that variant
            // paints `Theme.accent`, and a pink X reads as an action rather than
            // a dismiss. Same call `MilestoneRecommendationSheet` makes.
            Button(action: onDismiss) {
                Image(uiImage: Lucide.x)
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 20, height: 20)
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
    }

    // MARK: - Picks

    /// The phase this sheet is in, from the same pure resolver the
    /// recommendations screen uses. Always a pregenerated read: this surface
    /// never generates, so a missing batch is a state, not a trigger.
    private var phase: RecommendationRevealPhase {
        RecommendationsLoadingView.phase(
            isLoading: viewModel.isLoading || awaitingFirstLoad,
            isPregeneratedRead: true,
            hasError: viewModel.errorMessage != nil,
            pregeneratedMissing: batchMissing,
            isEmpty: viewModel.recommendations.isEmpty
        )
    }

    @ViewBuilder
    private var picksSection: some View {
        switch phase {
        case .loading, .silent:
            HStack {
                Spacer()
                ProgressView()
                    .tint(Theme.accent)
                Spacer()
            }
            .padding(.vertical, 40)

        case .error:
            errorCard

        case .missing, .empty:
            missingCard

        case .loaded:
            VStack(alignment: .leading, spacing: 16) {
                picksHeader

                RecommendationFeedList(
                    items: viewModel.recommendations,
                    isSaved: { viewModel.isSaved($0) },
                    onOpenDetail: { viewModel.openDetail($0) }
                )
            }
        }
    }

    private var picksHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Picks for \(partnerName)")
                .knotFont(Theme.Typography.sectionHeaderSemibold)
                .foregroundStyle(Theme.textPrimary)

            Spacer(minLength: 12)

            // The batch's own timestamp when the read returned one; the push's
            // send time otherwise (the two are seconds apart in practice).
            Text("Found \(PendingPicksAlert.agePhrase(sentAt: viewModel.batchGeneratedAt ?? alert.sentAt))")
                .knotFont(Theme.Typography.label)
                .foregroundStyle(Theme.accent)
                .fixedSize()
        }
    }

    private var errorCard: some View {
        KnotCard(padding: .lg, radius: Theme.Radius.xl) {
            VStack(spacing: 12) {
                Image(uiImage: Lucide.circleAlert)
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 32, height: 32)
                    .foregroundStyle(Theme.textTertiary)

                Text(viewModel.errorMessage ?? "Something went wrong")
                    .knotFont(Theme.Typography.label)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)

                KnotButton(
                    "Try again",
                    variant: .outlineNeutral,
                    size: .sm,
                    shape: .pill,
                    action: { Task { await load() } }
                )
                .fixedSize()
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
        }
    }

    /// Shaped like `MilestoneDetailView.emptyIdeas`. Reached only when a push
    /// was marked sent with nothing stored (local dev without APNs) — the
    /// production webhook stores before it sends.
    private var missingCard: some View {
        KnotCard(padding: .lg, radius: Theme.Radius.xl) {
            VStack(spacing: 12) {
                Image(uiImage: Lucide.sparkles)
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 32, height: 32)
                    .foregroundStyle(Theme.textTertiary)

                Text("We're still putting these together")
                    .knotFont(Theme.Typography.cta)
                    .foregroundStyle(Theme.textPrimary)

                Text("Your picks for this date aren't ready yet. Want us to find some now? It takes about half a minute.")
                    .knotFont(Theme.Typography.label)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)

                KnotButton(
                    "Get ideas",
                    variant: .primary,
                    size: .sm,
                    shape: .pill,
                    action: onGetIdeas
                )
                .fixedSize()
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
        }
    }

    // MARK: - Loading

    /// The pregenerated read, exactly as `RecommendationsView.loadContent()`
    /// makes it: an empty batch is a state (`batchMissing`), a failed read is an
    /// error whose Try Again re-runs this read, never a generation.
    private func load() async {
        batchMissing = false
        let shown = await viewModel.loadPregeneratedRecommendations(milestoneId: alert.milestone.id)
        if !shown {
            batchMissing = true
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Recent Picks Sheet") {
    let milestone = MilestoneItemResponse(
        id: "1",
        milestoneType: "birthday",
        milestoneName: "Jas's Birthday",
        milestoneDate: "2000-10-12",
        recurrence: "yearly",
        budgetTier: "major_milestone",
        daysUntil: 4,
        createdAt: "2026-07-04",
        occasionCategory: "birthday"
    )
    let viewModel = RecommendationsViewModel()
    viewModel.recommendations = [
        PreviewRecommendations.decode(type: "experience", isIdea: false, headline: "Weekend Curations"),
        PreviewRecommendations.decode(type: "gift", isIdea: false, headline: "Small Luxuries"),
        PreviewRecommendations.decode(type: "idea", isIdea: true, headline: "The Art of Pause"),
    ]
    viewModel.partnerName = "Jas"
    viewModel.hasLoadedInitially = true
    viewModel.batchGeneratedAt = Calendar.current.date(byAdding: .day, value: -3, to: Date())

    return Color.clear
        .sheet(isPresented: .constant(true)) {
            RecentPicksSheet(
                alert: PendingPicksAlert(
                    notificationIds: ["preview"],
                    milestone: milestone,
                    sentAt: Calendar.current.date(byAdding: .day, value: -3, to: Date())!
                ),
                partnerName: "Jas",
                urgency: .soon,
                onViewed: {},
                onGetIdeas: {},
                onDismiss: {},
                viewModel: viewModel
            )
        }
}
#endif
