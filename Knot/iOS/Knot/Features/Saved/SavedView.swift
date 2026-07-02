//
//  SavedView.swift
//  Knot
//
//  Created on February 26, 2026.
//  Saved tab — displays all bookmarked recommendations.
//  Added the post-date reward loop: "We did this" reflection + a "Moments" section.
//

import SwiftUI
import LucideIcons

/// Saved tab showing all bookmarked recommendations.
///
/// Splits saved items into two sections:
/// - **Saved** — active items still to be done. Date plans get a "We did this"
///   action that opens a post-date reflection.
/// - **Moments** — date plans the user marked done, with the rating + note they
///   left. This is the payoff/record that used to be missing after a date plan.
struct SavedView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = SavedViewModel()

    /// The item currently being reflected on (drives the reflection sheet).
    @State private var selectedForReflection: SavedRecommendation?

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.backgroundGradient.ignoresSafeArea()

                if viewModel.savedRecommendations.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        VStack(spacing: 24) {
                            if !viewModel.activeItems.isEmpty {
                                section(
                                    title: "Saved",
                                    count: viewModel.activeItems.count,
                                    items: viewModel.activeItems
                                ) { activeCard($0) }
                            }

                            if !viewModel.completedItems.isEmpty {
                                section(
                                    title: "Moments",
                                    count: viewModel.completedItems.count,
                                    subtitle: momentsSubtitle(viewModel.completedItems.count),
                                    items: viewModel.completedItems
                                ) { momentCard($0) }
                            }

                            Spacer(minLength: 40)
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                    }
                }
            }
            .navigationTitle("Saved")
            .navigationBarTitleDisplayMode(.inline)
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

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(uiImage: Lucide.bookmark)
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 40, height: 40)
                .foregroundStyle(Theme.textTertiary)

            VStack(spacing: 6) {
                Text("No saved items")
                    .knotFont(Theme.Typography.cardTitle)
                    .foregroundStyle(Theme.textPrimary)

                Text("Save recommendations from For You to find them here later.")
                    .knotFont(Theme.Typography.body)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Section

    private func section<Content: View>(
        title: String,
        count: Int,
        subtitle: String? = nil,
        items: [SavedRecommendation],
        @ViewBuilder card: @escaping (SavedRecommendation) -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title)
                        .knotFont(Theme.Typography.cardTitle)
                        .foregroundStyle(Theme.textPrimary)

                    Text("\(count)")
                        .knotFont(Theme.Typography.label)
                        .foregroundStyle(Theme.textSecondary)
                }

                if let subtitle {
                    Text(subtitle)
                        .knotFont(Theme.Typography.label)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // ForEach over the typed items (SavedRecommendation is Identifiable)
            // preserves SwiftUI item identity so Saved→Moments moves and deletes
            // animate/diff correctly.
            ForEach(items) { item in
                card(item)
            }
        }
    }

    private func momentsSubtitle(_ count: Int) -> String {
        count == 1 ? "1 date you made real" : "\(count) dates you made real"
    }

    // MARK: - Active Card

    private func activeCard(_ saved: SavedRecommendation) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            cardRow(saved, showOpenLink: true)

            if saved.isDoable {
                Button {
                    selectedForReflection = saved
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle")
                        Text("We did this")
                    }
                    .knotFont(Theme.Typography.cta)
                    .foregroundStyle(Theme.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Theme.accent.opacity(0.12))
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(cardBackground)
    }

    // MARK: - Moment Card

    private func momentCard(_ saved: SavedRecommendation) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            cardRow(saved, showOpenLink: false)

            if let rating = saved.rating {
                starRow(rating)
            }

            if let note = saved.reflectionNote, !note.isEmpty {
                Text("“\(note)”")
                    .knotFont(Theme.Typography.body)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(cardBackground)
    }

    // MARK: - Shared Card Row

    /// The common top row: type icon, title, merchant/price, optional open-link,
    /// and delete. Used by both active and moment cards.
    private func cardRow(_ saved: SavedRecommendation, showOpenLink: Bool) -> some View {
        HStack(spacing: 12) {
            // Type icon
            Image(systemName: savedTypeIcon(saved.recommendationType))
                .font(.subheadline)
                .foregroundStyle(Theme.accent)
                .frame(width: 34, height: 34)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Theme.accent.opacity(0.12))
                )

            // Details
            VStack(alignment: .leading, spacing: 2) {
                Text(saved.title)
                    .knotFont(Theme.Typography.cta)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    if let merchantName = saved.merchantName, !merchantName.isEmpty {
                        Text(merchantName)
                            .knotFont(Theme.Typography.label)
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                    }

                    if let priceCents = saved.priceCents {
                        Text(RecommendationCard.formattedPrice(cents: priceCents, currency: saved.currency))
                            .knotFont(Theme.Typography.label)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }

            Spacer()

            // Open link button — hidden for a stale web-search/shopping link so an
            // old Saved card never reopens a Google results page.
            if showOpenLink, let urlString = saved.externalURL, let url = URL(string: urlString),
               !url.isSearchOrShoppingLink {
                Button {
                    UIApplication.shared.open(url)
                } label: {
                    Image(uiImage: Lucide.externalLink)
                        .renderingMode(.template)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 14, height: 14)
                        .foregroundStyle(Theme.textTertiary)
                }
                .buttonStyle(.plain)
            }

            // Delete button
            Button {
                viewModel.deleteSavedRecommendation(saved, modelContext: modelContext)
            } label: {
                Image(uiImage: Lucide.x)
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 12, height: 12)
                    .foregroundStyle(Theme.textTertiary)
            }
            .buttonStyle(.plain)
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

    // MARK: - Helpers

    /// Filled/empty star row for a completed moment's rating.
    private func starRow(_ rating: Int) -> some View {
        HStack(spacing: 4) {
            ForEach(1...5, id: \.self) { star in
                Image(systemName: star <= rating ? "star.fill" : "star")
                    .font(.caption)
                    .foregroundStyle(star <= rating ? .yellow : Theme.textTertiary)
            }
        }
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Theme.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Theme.surfaceBorder, lineWidth: 1)
            )
    }

    /// SF Symbol for saved recommendation type.
    private func savedTypeIcon(_ type: String) -> String {
        switch type {
        case "gift": return "gift.fill"
        case "experience": return "sparkles"
        case "date": return "heart.fill"
        default: return "star.fill"
        }
    }
}
