//
//  InterestListRow.swift
//  Knot
//
//  Shared full-width selectable list row used by the onboarding interests
//  and dislikes screens. Replaces the former 3-column image-card grid with a
//  flat, single-column list (icon chip + label + accent border when selected).
//

import SwiftUI

/// A full-width selectable row representing a single interest/dislike category.
///
/// Layout: a tinted leading icon chip, the category name, and a trailing
/// checkmark that appears only when selected.
///
/// Visual states:
/// - **Unselected:** `Theme.surface` background, subtle border, muted icon
/// - **Selected:** accent-tinted background, pink (`Theme.accent`) border,
///   accent-tinted icon chip, checkmark — matching the onboarding radio rows
struct InterestListRow: View {
    let title: String
    /// From `OnboardingInterestsView.icon(for:)` (or a vibe's icon).
    let icon: KnotIcon
    /// Optional secondary line shown beneath the title (e.g. a vibe description).
    /// Interests/dislikes leave this `nil`, rendering a title-only row.
    var subtitle: String? = nil
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                // Leading icon chip
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(isSelected ? Theme.accent.opacity(0.20) : Theme.surfaceElevated)
                        .frame(width: 40, height: 40)

                    KnotIconView(icon, size: 22)
                        .foregroundStyle(isSelected ? Theme.accent : Theme.textSecondary)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .knotFont(Theme.Typography.cta)
                        .foregroundStyle(Theme.textPrimary)

                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .knotFont(Theme.Typography.label)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }

                Spacer(minLength: 0)

                // Trailing checkmark — only when selected
                if isSelected {
                    KnotIconView(.checkCircle, size: 24)
                        .foregroundStyle(Theme.accent)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(isSelected ? Theme.accent.opacity(0.12) : Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.lg)
                    .stroke(
                        isSelected ? Theme.accent.opacity(0.5) : Theme.surfaceBorder,
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.25), value: isSelected)
    }
}

// MARK: - Preview

#Preview("Interest List Rows") {
    VStack(spacing: 10) {
        InterestListRow(title: "Travel", icon: .flightOutlined, isSelected: true) {}
        InterestListRow(title: "Cooking", icon: .outdoorGrillOutlined, isSelected: false) {}
        InterestListRow(title: "Movies", icon: .movieOutlined, isSelected: false) {}
        InterestListRow(
            title: "Quiet Luxury",
            icon: .diamondOutlined,
            subtitle: "Elegant & understated",
            isSelected: true
        ) {}
    }
    .padding(24)
    .background(Theme.backgroundGradient)
}
