//
//  RecommendationsView.swift
//  Knot
//
//  Created on February 10, 2026.
//  Step 6.2: Choice-of-Three horizontal scroll with paging, loading state, and Refresh button.
//

import SwiftUI
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
    @Environment(\.dismiss) private var dismiss

    @State private var viewModel = RecommendationsViewModel()

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.backgroundGradient.ignoresSafeArea()

                Group {
                    if viewModel.isLoading {
                        loadingState
                    } else if let error = viewModel.errorMessage {
                        errorState(message: error)
                    } else if viewModel.recommendations.isEmpty {
                        emptyState
                    } else {
                        recommendationsContent
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(uiImage: Lucide.arrowLeft)
                            .renderingMode(.template)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 20, height: 20)
                    }
                    .tint(.white)
                }

                ToolbarItem(placement: .principal) {
                    Text("Recommendations")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)
                }
            }
            .task {
                await viewModel.generateRecommendations()
            }
        }
    }

    // MARK: - Recommendations Content

    private var recommendationsContent: some View {
        VStack(spacing: 20) {
            // Page indicator
            pageIndicator

            // Horizontal paging scroll
            TabView(selection: $viewModel.currentPage) {
                ForEach(Array(viewModel.recommendations.enumerated()), id: \.element.id) { index, item in
                    ScrollView {
                        RecommendationCard(
                            title: item.title,
                            descriptionText: item.description,
                            recommendationType: item.recommendationType,
                            priceCents: item.priceCents,
                            currency: item.currency,
                            merchantName: item.merchantName,
                            imageURL: item.imageUrl,
                            onSelect: {
                                // Selection flow will be implemented in Step 6.3
                            }
                        )
                        .padding(.horizontal, 20)
                    }
                    .scrollIndicators(.hidden)
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            // Refresh button
            refreshButton
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
        }
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
            Task {
                await viewModel.refreshRecommendations(reason: "show_different")
            }
        } label: {
            HStack(spacing: 8) {
                if viewModel.isRefreshing {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(0.8)
                } else {
                    Image(uiImage: Lucide.refreshCw)
                        .renderingMode(.template)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 16, height: 16)
                }

                Text(viewModel.isRefreshing ? "Finding new options..." : "Refresh")
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(.white)
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
        .disabled(viewModel.isRefreshing)
        .opacity(viewModel.isRefreshing ? 0.6 : 1.0)
    }

    // MARK: - Loading State

    private var loadingState: some View {
        VStack(spacing: 16) {
            ProgressView()
                .tint(Theme.accent)
                .scaleEffect(1.2)

            Text("Generating recommendations...")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.textSecondary)
        }
    }

    // MARK: - Error State

    private func errorState(message: String) -> some View {
        VStack(spacing: 16) {
            Image(uiImage: Lucide.alertCircle)
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
                    await viewModel.generateRecommendations()
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
        VStack(spacing: 16) {
            Image(uiImage: Lucide.sparkles)
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 40, height: 40)
                .foregroundStyle(Theme.textTertiary)

            Text("No recommendations yet")
                .font(.headline.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)

            Text("Complete your partner vault to get personalized recommendations.")
                .font(.subheadline)
                .foregroundStyle(Theme.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }
}

// MARK: - Previews

#Preview("Loading") {
    RecommendationsView()
        .preferredColorScheme(.dark)
}
