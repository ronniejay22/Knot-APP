//
//  DeepLinkRecommendationView.swift
//  Knot
//
//  Created on February 12, 2026.
//  Step 9.2: Full-screen view for displaying a recommendation opened via Universal Link.
//

import SwiftUI
import LucideIcons

/// Full-screen view for displaying a single recommendation opened via deep link.
///
/// Lifecycle:
/// 1. Presented as `fullScreenCover` from `HomeView` when a deep link is received
/// 2. Fetches the recommendation by ID from `GET /api/v1/recommendations/{id}`
/// 3. Displays loading → error → content states
/// 4. Uses `RecommendationCard` for visual consistency with the main recommendations flow
/// 5. Dismisses when the user taps the close button
struct DeepLinkRecommendationView: View {
    let recommendationId: String
    let onDismiss: @MainActor () -> Void

    @State private var recommendation: MilestoneRecommendationItemResponse?
    @State private var isLoading = true
    @State private var errorMessage: String?

    private let service = RecommendationService()

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.backgroundGradient.ignoresSafeArea()

                Group {
                    if isLoading {
                        loadingState
                    } else if let error = errorMessage {
                        errorState(message: error)
                    } else if let rec = recommendation {
                        contentState(rec)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        onDismiss()
                    } label: {
                        Image(uiImage: Lucide.x)
                            .renderingMode(.template)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 20, height: 20)
                    }
                    .tint(.white)
                }

                ToolbarItem(placement: .principal) {
                    Text("Recommendation")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)
                }
            }
            .task {
                await loadRecommendation()
            }
        }
    }

    // MARK: - Content State

    private func contentState(_ rec: MilestoneRecommendationItemResponse) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                RecommendationCard(
                    title: rec.title,
                    descriptionText: rec.description,
                    recommendationType: rec.recommendationType,
                    priceCents: rec.priceCents,
                    currency: "USD",
                    merchantName: rec.merchantName,
                    imageURL: rec.imageUrl,
                    isSaved: false,
                    onSelect: {
                        openExternalURL(rec.externalUrl)
                    },
                    onSave: {},
                    onShare: {}
                )
                .padding(.horizontal, 20)

                // Dismiss button
                Button {
                    onDismiss()
                } label: {
                    Text("Go Home")
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
                .padding(.horizontal, 20)
            }
            .padding(.top, 12)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: - Loading State

    private var loadingState: some View {
        VStack(spacing: 16) {
            ProgressView()
                .tint(Theme.accent)
                .scaleEffect(1.2)

            Text("Loading recommendation...")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.textSecondary)
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
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            VStack(spacing: 12) {
                Button {
                    Task {
                        await loadRecommendation()
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

                Button {
                    onDismiss()
                } label: {
                    Text("Go Home")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
    }

    // MARK: - Data Loading

    private func loadRecommendation() async {
        isLoading = true
        errorMessage = nil

        do {
            recommendation = try await service.fetchRecommendation(id: recommendationId)
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    // MARK: - Helpers

    private func openExternalURL(_ urlString: String?) {
        guard let urlString else { return }
        guard let rec = recommendation else { return }
        Task {
            await MerchantHandoffService.openMerchantURL(
                urlString: urlString,
                recommendationId: rec.id,
                service: service
            )
        }
    }
}

// MARK: - Previews

#Preview("Loading") {
    DeepLinkRecommendationView(
        recommendationId: "preview-123",
        onDismiss: {}
    )
    .preferredColorScheme(.dark)
}
