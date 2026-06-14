//
//  IdeaDetailView.swift
//  Knot
//
//  Created on February 23, 2026.
//  Step 14.9: Full-screen detail view for Knot Original ideas.
//  June 12, 2026: Section renderers extracted into the shared
//                 `IdeaContentSectionsView` (also used by RecommendationDetailView).
//

import SwiftUI
import LucideIcons

/// Full-screen ScrollView for reading the structured content of a Knot Original idea.
///
/// The structured-section rendering lives in the shared `IdeaContentSectionsView`;
/// this view owns only the surrounding chrome (toolbar, header, matched-factor chips).
struct IdeaDetailView: View {
    let idea: IdeaItemResponse
    let onDismiss: @MainActor () -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.backgroundGradient.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        headerSection
                        matchedFactorChips

                        IdeaContentSectionsView(sections: idea.contentSections)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .padding(.bottom, 40)
                }
                .scrollIndicators(.hidden)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        onDismiss()
                    } label: {
                        Image(uiImage: Lucide.arrowLeft)
                            .renderingMode(.template)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 20, height: 20)
                    }
                    .tint(Theme.textPrimary)
                }

                ToolbarItem(placement: .principal) {
                    Text("Idea")
                        .knotFont(Theme.Typography.cardTitle)
                        .foregroundStyle(Theme.textPrimary)
                }
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Type badge
            HStack(spacing: 5) {
                Image(uiImage: Lucide.lightbulb)
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 14, height: 14)

                Text("KNOT ORIGINAL")
                    .knotFont(Theme.Typography.label)
                    .textCase(.uppercase)
            }
            .foregroundStyle(Theme.accent)

            Text(idea.title)
                .knotFont(Theme.Typography.sectionHeader)
                .foregroundStyle(Theme.textPrimary)

            if let description = idea.description, !description.isEmpty {
                Text(description)
                    .knotFont(Theme.Typography.body)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    // MARK: - Matched Factor Chips

    @ViewBuilder
    private var matchedFactorChips: some View {
        let interests = idea.matchedInterests ?? []
        let vibes = idea.matchedVibes ?? []
        let loveLanguages = idea.matchedLoveLanguages ?? []
        let allChips = interests + vibes + loveLanguages

        if !allChips.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(allChips, id: \.self) { chip in
                        Text(chip)
                            .knotFont(Theme.Typography.label)
                            .foregroundStyle(Theme.accent)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(Theme.accent.opacity(0.2))
                            )
                            .overlay(
                                Capsule()
                                    .stroke(Theme.accent.opacity(0.4), lineWidth: 1)
                            )
                    }
                }
            }
        }
    }
}
