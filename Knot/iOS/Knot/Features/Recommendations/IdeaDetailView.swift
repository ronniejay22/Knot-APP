//
//  IdeaDetailView.swift
//  Knot
//
//  Created on February 23, 2026.
//  Step 14.9: Full-screen detail view for Knot Original ideas.
//

import SwiftUI
import LucideIcons

/// Full-screen ScrollView for reading the structured content of a Knot Original idea.
///
/// Renders each content section according to its type:
/// - `overview` — paragraph with accent left border
/// - `setup` — bulleted checklist items
/// - `steps` — numbered step cards
/// - `tips` — highlighted box with lightbulb icon
/// - `conversation` — chat-bubble-styled conversation starters
/// - `budget_tips` — green-tinted card with dollar icon
/// - `variations` — list of alternative approaches
/// - `music` / `food_pairing` — icon + description cards
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

                        ForEach(idea.contentSections) { section in
                            sectionView(for: section)
                        }
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
                    .tint(.white)
                }

                ToolbarItem(placement: .principal) {
                    Text("Idea")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)
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
                    .font(.caption.weight(.bold))
                    .textCase(.uppercase)
            }
            .foregroundStyle(Theme.accent)

            Text(idea.title)
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)

            if let description = idea.description, !description.isEmpty {
                Text(description)
                    .font(.body)
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
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.white)
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
                        .font(.body)
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
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 24, height: 24)
                            .background(Circle().fill(Theme.accent))

                        Text(step)
                            .font(.subheadline)
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
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.yellow)
                }

                if let body = section.body {
                    Text(body)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                }

                if let items = section.items {
                    ForEach(items, id: \.self) { item in
                        HStack(alignment: .top, spacing: 8) {
                            Text("\u{2022}")
                                .foregroundStyle(.yellow)
                            Text(item)
                                .font(.subheadline)
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
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                            .italic()
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
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.green)
                }

                if let body = section.body {
                    Text(body)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                }

                if let items = section.items {
                    ForEach(items, id: \.self) { item in
                        HStack(alignment: .top, spacing: 8) {
                            Text("\u{2022}")
                                .foregroundStyle(.green)
                            Text(item)
                                .font(.subheadline)
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
                    .font(.subheadline)
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
                                .font(.subheadline)
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
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                    }

                    if let items = section.items {
                        ForEach(items, id: \.self) { item in
                            Text(item)
                                .font(.subheadline)
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
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }

            if let items = section.items {
                ForEach(items, id: \.self) { item in
                    Text("- \(item)")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
    }

    // MARK: - Shared Helpers

    private func sectionHeading(_ text: String) -> some View {
        Text(text)
            .font(.headline.weight(.semibold))
            .foregroundStyle(.white)
    }
}
