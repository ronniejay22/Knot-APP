//
//  IdeaContentSectionsView.swift
//  Knot
//
//  Created on June 12, 2026.
//  Spotlight redesign: extracted the structured-section renderers out of
//  `IdeaDetailView` so both the legacy idea detail and the new unified
//  `RecommendationDetailView` render Knot Original content identically.
//

import SwiftUI
import LucideIcons

/// Renders the structured `IdeaContentSection` list of a Knot Original idea/plan.
///
/// Each section is drawn according to its `type`:
/// - `overview` — paragraph with accent left border
/// - `setup` — bulleted checklist items
/// - `steps` — numbered step cards
/// - `tips` — yellow-tinted box with lightbulb icon
/// - `conversation` — chat-bubble-styled conversation starters
/// - `budget_tips` — green-tinted card with dollar icon
/// - `variations` — list of alternative approaches
/// - `music` / `food_pairing` — icon + description cards
///
/// Hosted by both `IdeaDetailView` and `RecommendationDetailView`; the parent
/// owns the surrounding chrome (header, hero, chips, CTA) and spacing.
struct IdeaContentSectionsView: View {
    let sections: [IdeaContentSection]

    /// Vertical spacing between sections. Defaults to the 24pt rhythm used by
    /// the original `IdeaDetailView`.
    var spacing: CGFloat = 24

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            ForEach(sections) { section in
                sectionView(for: section)
            }
        }
    }

    // MARK: - Section Rendering

    @ViewBuilder
    private func sectionView(for section: IdeaContentSection) -> some View {
        switch section.type {
        case "overview":
            overviewSection(section)
        case "steps":
            stepsSection(section)
        case "setup":
            listSection(section, icon: Lucide.clipboardList)
        case "tips":
            tipsSection(section)
        case "conversation":
            conversationSection(section)
        case "budget_tips":
            budgetTipsSection(section)
        case "variations":
            listSection(section, icon: Lucide.shuffle)
        case "music":
            iconCardSection(section, icon: Lucide.music)
        case "food_pairing":
            iconCardSection(section, icon: Lucide.utensils)
        default:
            genericSection(section)
        }
    }

    // MARK: - Overview

    private func overviewSection(_ section: IdeaContentSection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeading(section.heading)

            if let body = section.body {
                HStack(spacing: 0) {
                    Rectangle()
                        .fill(Theme.accent)
                        .frame(width: 3)

                    Text(body)
                        .knotFont(Theme.Typography.body)
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.leading, 12)
                }
            }
        }
    }

    // MARK: - Steps

    private func stepsSection(_ section: IdeaContentSection) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeading(section.heading)

            if let items = section.items {
                ForEach(Array(items.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .top, spacing: 12) {
                        // Step number circle
                        Text("\(index + 1)")
                            .knotFont(Theme.Typography.label)
                            .foregroundStyle(.white)
                            .frame(width: 24, height: 24)
                            .background(Circle().fill(Theme.accent))

                        Text(step)
                            .knotFont(Theme.Typography.body)
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Theme.surface)
                    )
                }
            }
        }
    }

    // MARK: - Tips

    private func tipsSection(_ section: IdeaContentSection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeading(section.heading)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(uiImage: Lucide.lightbulb)
                        .renderingMode(.template)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 16, height: 16)
                        .foregroundStyle(.yellow)

                    Text("Pro Tips")
                        .knotFont(Theme.Typography.label)
                        .foregroundStyle(.yellow)
                }

                if let body = section.body {
                    Text(body)
                        .knotFont(Theme.Typography.body)
                        .foregroundStyle(Theme.textSecondary)
                }

                if let items = section.items {
                    ForEach(items, id: \.self) { item in
                        HStack(alignment: .top, spacing: 8) {
                            Text("\u{2022}")
                                .foregroundStyle(.yellow)
                            Text(item)
                                .knotFont(Theme.Typography.body)
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.yellow.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.yellow.opacity(0.2), lineWidth: 1)
                    )
            )
        }
    }

    // MARK: - Conversation Starters

    private func conversationSection(_ section: IdeaContentSection) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeading(section.heading)

            if let items = section.items {
                ForEach(items, id: \.self) { starter in
                    HStack(alignment: .top, spacing: 10) {
                        Image(uiImage: Lucide.messageCircle)
                            .renderingMode(.template)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 14, height: 14)
                            .foregroundStyle(Theme.accent)
                            .padding(.top, 2)

                        Text("\"\(starter)\"")
                            .knotFont(Theme.Typography.italicQuote)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Theme.accent.opacity(0.06))
                    )
                }
            }
        }
    }

    // MARK: - Budget Tips

    private func budgetTipsSection(_ section: IdeaContentSection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeading(section.heading)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(uiImage: Lucide.circleDollarSign)
                        .renderingMode(.template)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 16, height: 16)
                        .foregroundStyle(.green)

                    Text("Budget Friendly")
                        .knotFont(Theme.Typography.label)
                        .foregroundStyle(.green)
                }

                if let body = section.body {
                    Text(body)
                        .knotFont(Theme.Typography.body)
                        .foregroundStyle(Theme.textSecondary)
                }

                if let items = section.items {
                    ForEach(items, id: \.self) { item in
                        HStack(alignment: .top, spacing: 8) {
                            Text("\u{2022}")
                                .foregroundStyle(.green)
                            Text(item)
                                .knotFont(Theme.Typography.body)
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.green.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.green.opacity(0.2), lineWidth: 1)
                    )
            )
        }
    }

    // MARK: - Generic List Section (setup, variations)

    private func listSection(_ section: IdeaContentSection, icon: UIImage) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeading(section.heading)

            if let body = section.body {
                Text(body)
                    .knotFont(Theme.Typography.body)
                    .foregroundStyle(Theme.textSecondary)
            }

            if let items = section.items {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(items, id: \.self) { item in
                        HStack(alignment: .top, spacing: 10) {
                            Image(uiImage: icon)
                                .renderingMode(.template)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 14, height: 14)
                                .foregroundStyle(Theme.accent)
                                .padding(.top, 2)

                            Text(item)
                                .knotFont(Theme.Typography.body)
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Theme.surface)
                )
            }
        }
    }

    // MARK: - Icon Card Section (music, food_pairing)

    private func iconCardSection(_ section: IdeaContentSection, icon: UIImage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeading(section.heading)

            HStack(alignment: .top, spacing: 12) {
                Image(uiImage: icon)
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 20, height: 20)
                    .foregroundStyle(Theme.accent)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 6) {
                    if let body = section.body {
                        Text(body)
                            .knotFont(Theme.Typography.body)
                            .foregroundStyle(Theme.textSecondary)
                    }

                    if let items = section.items {
                        ForEach(items, id: \.self) { item in
                            Text(item)
                                .knotFont(Theme.Typography.body)
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Theme.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Theme.surfaceBorder, lineWidth: 1)
                    )
            )
        }
    }

    // MARK: - Fallback Generic Section

    private func genericSection(_ section: IdeaContentSection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeading(section.heading)

            if let body = section.body {
                Text(body)
                    .knotFont(Theme.Typography.body)
                    .foregroundStyle(Theme.textSecondary)
            }

            if let items = section.items {
                ForEach(items, id: \.self) { item in
                    Text("- \(item)")
                        .knotFont(Theme.Typography.body)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
    }

    // MARK: - Shared Helpers

    private func sectionHeading(_ text: String) -> some View {
        Text(text)
            .knotFont(Theme.Typography.cardTitle)
            .foregroundStyle(Theme.textPrimary)
    }
}
