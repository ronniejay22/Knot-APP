//
//  InterestSelectRow.swift
//  Knot
//
//  Created on June 7, 2026.
//  Step 18.30: Shared full-width selectable list row for the Interests and
//              Dislikes onboarding screens (replaces the 3-column image-card grid).
//

import SwiftUI

/// A full-width, selectable list row showing a leading SF Symbol icon and a
/// label — the building block for the Interests and Dislikes onboarding screens.
///
/// Visual states:
/// - **Unselected:** `Theme.surface` fill with a hairline `Theme.surfaceBorder`.
/// - **Selected:** subtle accent tint, an accent (pink) border, the icon tinted
///   to the accent, and a trailing `checkmark.circle.fill` badge.
///
/// Mirrors the chrome of `KnotListRow` and the accent-border selection idiom from
/// `LoveLanguageCard`, kept consistent with the rest of onboarding.
struct InterestSelectRow: View {
    let title: String
    let isSelected: Bool
    /// SF Symbol name (from `OnboardingInterestsView.iconName(for:)`).
    let iconName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: iconName)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(isSelected ? Theme.accent : Theme.textSecondary)
                    .frame(width: 24, height: 24)

                Text(title)
                    .knotFont(Theme.Typography.cta)
                    .foregroundStyle(Theme.textPrimary)

                Spacer(minLength: 8)

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Theme.accent.opacity(0.08) : Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.md)
                    .stroke(
                        isSelected ? Theme.accent : Theme.surfaceBorder,
                        lineWidth: isSelected ? 2 : 1
                    )
            )
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.25), value: isSelected)
    }
}

// MARK: - Preview

#Preview("States") {
    VStack(spacing: 12) {
        InterestSelectRow(title: "Travel", isSelected: false, iconName: "airplane") {}
        InterestSelectRow(title: "Cooking", isSelected: true, iconName: "flame.fill") {}
        InterestSelectRow(title: "Photography", isSelected: false, iconName: "camera.fill") {}
        InterestSelectRow(title: "Music", isSelected: true, iconName: "music.note") {}
    }
    .padding(24)
    .background(Theme.backgroundGradient.ignoresSafeArea())
}
