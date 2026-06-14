//
//  RecommendationChips.swift
//  Knot
//
//  Created on June 12, 2026.
//  Spotlight redesign: shared "matched factor" chip + builder, extracted from
//  RecommendationCard so the card, the Spotlight deck card, and the detail page
//  all render match badges identically.
//

import SwiftUI

/// A single match-factor badge (vibe / love language / interest) shown on a
/// recommendation. Color-coded by `style`.
struct MatchingFactorChip: View {
    let label: String
    let style: ChipStyle

    enum ChipStyle {
        case interest
        case vibe
        case loveLanguage
    }

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: iconName)
                .font(.system(size: 8, weight: .bold))
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .lineLimit(1)
        }
        .foregroundStyle(foregroundColor)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(backgroundColor)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(borderColor, lineWidth: 0.5)
        )
    }

    private var iconName: String {
        switch style {
        case .interest: return "heart.fill"
        case .vibe: return "sparkles"
        case .loveLanguage: return "hand.raised.fill"
        }
    }

    private var foregroundColor: Color {
        switch style {
        case .interest: return Theme.accent
        case .vibe: return Color.purple
        case .loveLanguage: return Color.orange
        }
    }

    private var backgroundColor: Color {
        switch style {
        case .interest: return Theme.accent.opacity(0.18)
        case .vibe: return Color.purple.opacity(0.18)
        case .loveLanguage: return Color.orange.opacity(0.18)
        }
    }

    private var borderColor: Color {
        switch style {
        case .interest: return Theme.accent.opacity(0.3)
        case .vibe: return Color.purple.opacity(0.3)
        case .loveLanguage: return Color.orange.opacity(0.3)
        }
    }
}

// MARK: - Display Chip Model

/// A resolved, display-ready match factor: a human-readable label plus the
/// chip style that determines its icon and color.
struct RecommendationDisplayChip: Identifiable {
    /// Stable identity derived from style + label. Must not be a fresh `UUID()`
    /// per build: the chip list is rebuilt on every body evaluation, and during
    /// the deck's swipe animation that churns `ForEach` identity every frame,
    /// tearing down and rebuilding each chip instead of diffing it.
    var id: String { "\(style)-\(label)" }
    let label: String
    let style: MatchingFactorChip.ChipStyle

    /// Builds the ordered chip list shown on a recommendation: vibes first, then
    /// love languages, then interests. Raw keys are resolved to display names via
    /// the onboarding display helpers.
    static func build(
        vibes: [String],
        loveLanguages: [String],
        interests: [String]
    ) -> [RecommendationDisplayChip] {
        var chips: [RecommendationDisplayChip] = []
        chips.append(contentsOf: vibes.map {
            RecommendationDisplayChip(label: OnboardingVibesView.displayName(for: $0), style: .vibe)
        })
        chips.append(contentsOf: loveLanguages.map {
            RecommendationDisplayChip(label: LoveLanguageDisplay.name(for: $0), style: .loveLanguage)
        })
        chips.append(contentsOf: interests.map {
            RecommendationDisplayChip(label: $0, style: .interest)
        })
        return chips
    }
}
