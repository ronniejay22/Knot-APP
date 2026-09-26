//
//  SavedView.swift
//  Knot
//
//  Created on February 26, 2026.
//  Saved tab — displays all bookmarked recommendations.
//  Restyled as "Saved recommendations" photo cards, sharing `SavedIdeaCard`
//  with a Home event's detail screen.
//

import SwiftUI

/// Saved tab showing all bookmarked recommendations.
///
/// One list, newest first: a large "Saved recommendations" header with its
/// accent count underneath, then a `SavedIdeaCard` per saved item. The header
/// lives in the content, like the "Saved ideas" section of
/// `MilestoneDetailView`, so the screen has no navigation bar — and, since the
/// detail opens as a full-screen cover, no `NavigationStack` either.
struct SavedView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: SavedViewModel

    /// The saved item whose detail page is open (drives the full-screen detail cover).
    /// Rebuilt from the local snapshot via `SavedRecommendation.toDetailItem()`.
    @State private var selectedDetailItem: RecommendationItemResponse?

    /// The default preserves every existing call site. The `viewModel:`
    /// parameter lets tests hand in one that has already loaded, so the list
    /// renders on the first layout pass rather than after `.task`.
    init(viewModel: SavedViewModel = SavedViewModel()) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        ZStack {
            Theme.backgroundGradient.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header(count: viewModel.savedRecommendations.count)

                    if viewModel.savedRecommendations.isEmpty {
                        emptyState
                    } else {
                        // ForEach over the typed items (SavedRecommendation is
                        // Identifiable) preserves SwiftUI item identity so
                        // deletes animate/diff correctly.
                        ForEach(viewModel.savedRecommendations) { saved in
                            SavedIdeaCard(
                                saved: saved,
                                listName: "saved recommendations",
                                onOpen: { selectedDetailItem = saved.toDetailItem() },
                                onRemove: { viewModel.deleteSavedRecommendation(saved, modelContext: modelContext) }
                            )
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 40)
            }
        }
        .task {
            await viewModel.loadSavedRecommendations(modelContext: modelContext)
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
    }

    // MARK: - Header

    /// Always rendered: with the navigation title gone, this is the screen's
    /// title, so it stays even when nothing is saved. The count sits on its
    /// own line because "Saved recommendations" at this size leaves no room
    /// beside it on most iPhones.
    private func header(count: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Saved recommendations")
                .knotFont(Theme.Typography.sectionHeaderSemibold)
                .foregroundStyle(Theme.textPrimary)

            // The count reads off the same array the list renders, so it can
            // never disagree with what is on screen.
            if count > 0 {
                Text(Self.savedCountText(count))
                    .knotFont(Theme.Typography.label)
                    .foregroundStyle(Theme.accent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.savedAccessibilityLabel(count: count))
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        KnotCard(padding: .lg, radius: Theme.Radius.xl) {
            VStack(spacing: 12) {
                KnotIconView(.bookmarkBorder, size: 32)
                    .foregroundStyle(Theme.textTertiary)

                Text("No saved items")
                    .knotFont(Theme.Typography.cta)
                    .foregroundStyle(Theme.textPrimary)

                Text("Save recommendations from Home to find them here later.")
                    .knotFont(Theme.Typography.label)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
        }
    }
}

// MARK: - Pure Helpers

extension SavedView {

    /// "1 saved" / "3 saved" — the accent count under "Saved recommendations".
    static func savedCountText(_ count: Int) -> String {
        "\(count) saved"
    }

    /// VoiceOver label for the header and its count. Pure and `static` so the
    /// wording is testable without rendering the screen.
    static func savedAccessibilityLabel(count: Int) -> String {
        count == 0 ? "Saved recommendations, none yet" : "Saved recommendations, \(savedCountText(count))"
    }
}
