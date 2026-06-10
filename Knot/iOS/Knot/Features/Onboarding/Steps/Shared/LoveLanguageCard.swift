//
//  LoveLanguageCard.swift
//  Knot
//
//  Shared love language card visual + display-name/icon/description helpers
//  used by the combined love languages onboarding screen and the Settings
//  EditLoveLanguagesSheet.
//
//  Styled to match the onboarding interests/dislikes rows (`InterestListRow`):
//  a flat `Theme.surface` row with a tinted leading icon chip, the language
//  name + description, an accent border when selected, and a trailing
//  PRIMARY / SECONDARY rank badge.
//

import SwiftUI
import LucideIcons

// MARK: - Selection State

/// The three possible selection states for a love language card.
enum LoveLanguageSelectionState: Equatable {
    case unselected
    case primary
    case secondary
}

// MARK: - Display Mapping

enum LoveLanguageDisplay {
    /// Converts snake_case love language keys to human-readable display names.
    static func name(for language: String) -> String {
        let names: [String: String] = [
            "words_of_affirmation": "Words of Affirmation",
            "acts_of_service": "Acts of Service",
            "receiving_gifts": "Receiving Gifts",
            "quality_time": "Quality Time",
            "physical_touch": "Physical Touch"
        ]
        return names[language] ?? language.replacingOccurrences(of: "_", with: " ").capitalized
    }

    /// Contextual descriptions for each love language.
    static func description(for language: String) -> String {
        let descriptions: [String: String] = [
            "words_of_affirmation": "They feel loved through compliments, encouragement, and heartfelt messages.",
            "acts_of_service": "Actions speak louder — they appreciate helpful, thoughtful gestures.",
            "receiving_gifts": "Meaningful, well-chosen gifts make them feel truly seen and valued.",
            "quality_time": "Undivided attention and shared experiences matter most to them.",
            "physical_touch": "Closeness, comfort, and physical connection bring them joy."
        ]
        return descriptions[language] ?? ""
    }

    /// Maps each love language to a Lucide icon.
    static func icon(for language: String) -> UIImage {
        switch language {
        case "words_of_affirmation": return Lucide.messageCircle
        case "acts_of_service": return Lucide.heartHandshake
        case "receiving_gifts": return Lucide.gift
        case "quality_time": return Lucide.clock
        case "physical_touch": return Lucide.hand
        default: return Lucide.heart
        }
    }
}

// MARK: - Love Language Card

/// A full-width selectable row representing a single love language option.
///
/// Mirrors `InterestListRow`'s flat aesthetic: a tinted leading icon chip, the
/// language name + description, and an accent border when selected. Because a
/// love language can be ranked, the trailing indicator is a PRIMARY / SECONDARY
/// pill badge rather than a plain checkmark.
///
/// Visual states:
/// - **Unselected:** `Theme.surface` background, subtle border, muted icon
/// - **Primary:** pink (`Theme.accent`) border + icon chip, "PRIMARY" badge
/// - **Secondary:** muted-pink border + icon chip, "SECONDARY" badge
struct LoveLanguageCard: View {
    let language: String
    let selectionState: LoveLanguageSelectionState
    let action: () -> Void

    private var isSelected: Bool {
        selectionState != .unselected
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                // Leading icon chip
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(isSelected ? Theme.accent.opacity(0.20) : Theme.surfaceElevated)
                        .frame(width: 40, height: 40)

                    Image(uiImage: LoveLanguageDisplay.icon(for: language))
                        .renderingMode(.template)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 20, height: 20)
                        .foregroundStyle(isSelected ? Theme.accent : Theme.textSecondary)
                }

                VStack(alignment: .leading, spacing: 2) {
                    // One line always: keeps the row height stable when the
                    // trailing badge appears and steals width. The scale floor
                    // absorbs the tight case — the longest name ("Words of
                    // Affirmation") next to the wider "SECONDARY" badge on a
                    // narrow device — without truncating to an ellipsis.
                    Text(LoveLanguageDisplay.name(for: language))
                        .knotFont(Theme.Typography.cta)
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)

                    Text(LoveLanguageDisplay.description(for: language))
                        .knotFont(Theme.Typography.label)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 8)

                // Trailing rank badge — only when selected. Fixed-size with a
                // higher layout priority so it can't be compressed by the title.
                if selectionState == .primary {
                    rankBadge("PRIMARY", fill: Theme.accent)
                } else if selectionState == .secondary {
                    rankBadge("SECONDARY", fill: Theme.accent.opacity(0.6))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.lg)
                    .stroke(borderColor, lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.25), value: selectionState)
    }

    private var borderColor: Color {
        switch selectionState {
        case .primary: return Theme.accent
        case .secondary: return Theme.accent.opacity(0.6)
        case .unselected: return Theme.surfaceBorder
        }
    }

    private func rankBadge(_ text: String, fill: Color) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .heavy))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(fill))
            .fixedSize()
            .layoutPriority(1)
            .transition(.scale.combined(with: .opacity))
    }
}

// MARK: - Preview

#Preview("Love Language Cards") {
    VStack(spacing: 12) {
        LoveLanguageCard(language: "quality_time", selectionState: .primary) {}
        LoveLanguageCard(language: "physical_touch", selectionState: .secondary) {}
        LoveLanguageCard(language: "words_of_affirmation", selectionState: .unselected) {}
        LoveLanguageCard(language: "acts_of_service", selectionState: .unselected) {}
        LoveLanguageCard(language: "receiving_gifts", selectionState: .unselected) {}
    }
    .padding(20)
    .background(Theme.backgroundGradient)
}
