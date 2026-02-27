//
//  SavedView.swift
//  Knot
//
//  Created on February 26, 2026.
//  Saved tab — displays all bookmarked recommendations.
//

import SwiftUI
import LucideIcons

/// Saved tab showing all bookmarked recommendations.
///
/// Replaces the limited (5-item) saved recommendations section that was
/// previously inline on the Home screen. Shows the full list with delete
/// and external link actions per card.
struct SavedView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = SavedViewModel()

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.backgroundGradient.ignoresSafeArea()

                if viewModel.savedRecommendations.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        VStack(spacing: 12) {
                            ForEach(viewModel.savedRecommendations) { saved in
                                savedRecommendationCard(saved)
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
            .onAppear {
                viewModel.loadSavedRecommendations(modelContext: modelContext)
            }
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
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)

                Text("Save recommendations from Discover to find them here later.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Saved Recommendation Card

    private func savedRecommendationCard(_ saved: SavedRecommendation) -> some View {
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
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    if let merchantName = saved.merchantName, !merchantName.isEmpty {
                        Text(merchantName)
                            .font(.caption2)
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                    }

                    if let priceCents = saved.priceCents {
                        Text(RecommendationCard.formattedPrice(cents: priceCents, currency: saved.currency))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }

            Spacer()

            // Open link button
            if let urlString = saved.externalURL, let url = URL(string: urlString) {
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
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Theme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Theme.surfaceBorder, lineWidth: 1)
                )
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
