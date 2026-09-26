//
//  SavedView.swift
//  Knot
//
//  Created on February 26, 2026.
//  Saved tab — displays all bookmarked recommendations.
//  Added the post-date reward loop: "We did this" reflection + a "Moments" section.
//  Restyled as "Saved ideas" photo cards, sharing `SavedIdeaCard` with a
//  Journal event's detail screen.
//

import SwiftUI
import LucideIcons

/// Saved tab showing all bookmarked recommendations.
///
/// Splits saved items into two sections, each a large header over a list of
/// `SavedIdeaCard`s:
/// - **Saved ideas** — active items still to be done. Date plans carry a
///   "We did this" footer action that opens a post-date reflection.
/// - **Moments** — date plans the user marked done, with the rating + note they
///   left. This is the payoff/record that used to be missing after a date plan.
///
/// The header lives in the content rather than the navigation bar, matching
/// the "Saved ideas" section of `MilestoneDetailView`.
struct SavedView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = SavedViewModel()

    /// The item currently being reflected on (drives the reflection sheet).
    @State private var selectedForReflection: SavedRecommendation?

    /// The saved item whose detail page is open (drives the full-screen detail cover).
    /// Rebuilt from the local snapshot via `SavedRecommendation.toDetailItem()`.
    @State private var selectedDetailItem: RecommendationItemResponse?

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.backgroundGradient.ignoresSafeArea()

                ScrollView {
                    // Each split filters (and sorts) the whole library, so take
                    // them once per render.
                    let active = viewModel.activeItems
                    let moments = viewModel.completedItems

                    VStack(alignment: .leading, spacing: 28) {
                        savedIdeasSection(
                            active,
                            showsEmptyCard: Self.showsEmptyCard(activeCount: active.count, momentCount: moments.count)
                        )

                        if !moments.isEmpty {
                            momentsSection(moments)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 40)
                }
                // The section header replaces the navigation title. Hidden on the
                // scroll content rather than the ZStack so the sheet and cover
                // below stay outside the hidden subtree (the Step 19.31 scoping).
                .toolbar(.hidden, for: .navigationBar)
            }
            .task {
                await viewModel.loadSavedRecommendations(modelContext: modelContext)
            }
            .sheet(item: $selectedForReflection) { saved in
                PurchaseRatingSheet(
                    itemTitle: saved.title,
                    headline: "How did it go?",
                    onSubmit: { rating, note in
                        viewModel.markCompleted(saved, rating: rating, note: note, modelContext: modelContext)
                        selectedForReflection = nil
                    },
                    onSkip: {
                        selectedForReflection = nil
                    }
                )
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
            }
            .fullScreenCover(item: $selectedDetailItem) { item in
                RecommendationDetailView(
                    item: item,
                    // The "Why Knot picked this" block is hidden for saved snapshots
                    // (no note/chips stored), and partnerName is only used there.
                    partnerName: nil,
                    isSaved: true,
                    onOpenMerchant: { viewModel.openMerchant(item) },
                    onSave: {},
                    onDismiss: { selectedDetailItem = nil }
                )
            }
            .overlay(alignment: .top) {
                if let title = viewModel.lastCelebratedTitle {
                    rewardToast(title)
                        .padding(.horizontal, 20)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .task {
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                            try? await Task.sleep(for: .seconds(2.2))
                            withAnimation { viewModel.clearCelebration() }
                        }
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: viewModel.lastCelebratedTitle)
        }
    }

    // MARK: - Saved Ideas

    /// Always rendered — with the navigation title gone, this header is the
    /// screen's title, so it stays even when there is nothing left to do.
    /// Once every idea has been done it stands alone above Moments; the empty
    /// card is only for a library with nothing in it (see `showsEmptyCard`).
    private func savedIdeasSection(_ items: [SavedRecommendation], showsEmptyCard: Bool) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader(
                title: "Saved ideas",
                countText: items.isEmpty ? nil : Self.savedCountText(items.count),
                accessibilityLabel: Self.savedAccessibilityLabel(count: items.count)
            )

            if showsEmptyCard {
                emptyState
            } else {
                // ForEach over the typed items (SavedRecommendation is Identifiable)
                // preserves SwiftUI item identity so Saved→Moments moves and deletes
                // animate/diff correctly.
                ForEach(items) { saved in
                    SavedIdeaCard(
                        saved: saved,
                        onOpen: { selectedDetailItem = saved.toDetailItem() },
                        onRemove: { viewModel.deleteSavedRecommendation(saved, modelContext: modelContext) },
                        // `@MainActor in` is needed inside the ternary, where the
                        // closure is not inferred from the parameter's type.
                        onMarkDone: saved.isDoable ? { @MainActor in selectedForReflection = saved } : nil
                    )
                }
            }
        }
    }

    // MARK: - Moments

    private func momentsSection(_ items: [SavedRecommendation]) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader(
                title: "Moments",
                countText: Self.momentsCountText(items.count),
                accessibilityLabel: Self.momentsAccessibilityLabel(count: items.count)
            )

            ForEach(items) { saved in
                SavedIdeaCard(
                    saved: saved,
                    style: .moment,
                    onOpen: { selectedDetailItem = saved.toDetailItem() },
                    onRemove: { viewModel.deleteSavedRecommendation(saved, modelContext: modelContext) }
                )
            }
        }
    }

    // MARK: - Section Header

    /// Large title with a trailing accent count — the same treatment as the
    /// "Saved ideas" header on `MilestoneDetailView`.
    private func sectionHeader(
        title: String,
        countText: String?,
        accessibilityLabel: String
    ) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .knotFont(Theme.Typography.sectionHeaderSemibold)
                .foregroundStyle(Theme.textPrimary)

            Spacer(minLength: 12)

            // The count reads off the same array the section renders, so it
            // can never disagree with what is on screen.
            if let countText {
                Text(countText)
                    .knotFont(Theme.Typography.label)
                    .foregroundStyle(Theme.accent)
                    .fixedSize()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        KnotCard(padding: .lg, radius: Theme.Radius.xl) {
            VStack(spacing: 12) {
                Image(uiImage: Lucide.bookmark)
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 32, height: 32)
                    .foregroundStyle(Theme.textTertiary)

                Text("No saved items")
                    .knotFont(Theme.Typography.cta)
                    .foregroundStyle(Theme.textPrimary)

                Text("Save recommendations from Journal to find them here later.")
                    .knotFont(Theme.Typography.label)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
        }
    }

    // MARK: - Reward Toast

    private func rewardToast(_ title: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.headline)
                .foregroundStyle(Theme.accent)

            VStack(alignment: .leading, spacing: 2) {
                Text("Moment made real 💛")
                    .knotFont(Theme.Typography.cta)
                    .foregroundStyle(Theme.textPrimary)

                Text(title)
                    .knotFont(Theme.Typography.label)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Theme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Theme.surfaceBorder, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        )
    }
}

// MARK: - Pure Helpers

extension SavedView {

    /// "1 saved" / "3 saved" — the accent count beside "Saved ideas".
    static func savedCountText(_ count: Int) -> String {
        "\(count) saved"
    }

    /// "1 made real" / "3 made real" — the accent count beside "Moments".
    static func momentsCountText(_ count: Int) -> String {
        "\(count) made real"
    }

    /// VoiceOver label for the "Saved ideas" header and its count. Pure and
    /// `static` so the wording is testable without rendering the screen.
    static func savedAccessibilityLabel(count: Int) -> String {
        count == 0 ? "Saved ideas, none yet" : "Saved ideas, \(savedCountText(count))"
    }

    /// VoiceOver label for the "Moments" header and its count.
    static func momentsAccessibilityLabel(count: Int) -> String {
        count == 0 ? "Moments, none yet" : "Moments, \(momentsCountText(count))"
    }

    /// Whether "Saved ideas" shows its "No saved items" card: only when nothing
    /// is saved at all, the condition the old full-screen empty state used.
    /// Once every idea has been done, that copy would sit directly above the
    /// Moments that hold them.
    static func showsEmptyCard(activeCount: Int, momentCount: Int) -> Bool {
        activeCount == 0 && momentCount == 0
    }
}
