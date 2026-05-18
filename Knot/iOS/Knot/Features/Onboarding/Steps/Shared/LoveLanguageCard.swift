//
//  LoveLanguageCard.swift
//  Knot
//
//  Shared love language card visual + display-name/icon/gradient helpers
//  used by the primary/secondary onboarding screens, EditLoveLanguagesSheet,
//  RecommendationCard, and OnboardingCompletionView.
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

    /// Unique background gradient for each love language.
    static func gradient(for language: String) -> LinearGradient {
        let colors: (Color, Color) = {
            switch language {
            case "words_of_affirmation":
                return (
                    Color(hue: 0.04, saturation: 0.45, brightness: 0.50),
                    Color(hue: 0.06, saturation: 0.55, brightness: 0.22)
                )
            case "acts_of_service":
                return (
                    Color(hue: 0.38, saturation: 0.50, brightness: 0.42),
                    Color(hue: 0.40, saturation: 0.60, brightness: 0.18)
                )
            case "receiving_gifts":
                return (
                    Color(hue: 0.82, saturation: 0.50, brightness: 0.50),
                    Color(hue: 0.85, saturation: 0.60, brightness: 0.22)
                )
            case "quality_time":
                return (
                    Color(hue: 0.12, saturation: 0.55, brightness: 0.52),
                    Color(hue: 0.14, saturation: 0.65, brightness: 0.22)
                )
            case "physical_touch":
                return (
                    Color(hue: 0.95, saturation: 0.45, brightness: 0.48),
                    Color(hue: 0.97, saturation: 0.55, brightness: 0.22)
                )
            default:
                return (
                    Color(hue: 0.75, saturation: 0.40, brightness: 0.40),
                    Color(hue: 0.75, saturation: 0.50, brightness: 0.18)
                )
            }
        }()

        return LinearGradient(
            colors: [colors.0, colors.1],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - Love Language Card

/// A full-width card representing a single love language option.
///
/// Layout: gradient background with icon + text on the left, and an
/// independent badge overlay pinned to the top-right corner.
///
/// Visual states:
/// - **Unselected:** Gradient background, subtle border, 1.0 scale
/// - **Primary:** Pink border, "PRIMARY" badge (top-right), 1.02 scale
/// - **Secondary:** Muted pink border, "SECONDARY" badge (top-right)
/// - **Disabled:** rendered at 0.5 opacity to indicate it can't be picked
struct LoveLanguageCard: View {
    let language: String
    let selectionState: LoveLanguageSelectionState
    let isDisabled: Bool
    let action: () -> Void

    init(
        language: String,
        selectionState: LoveLanguageSelectionState,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) {
        self.language = language
        self.selectionState = selectionState
        self.isDisabled = isDisabled
        self.action = action
    }

    private var isSelected: Bool {
        selectionState != .unselected
    }

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                HStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(.white.opacity(isSelected ? 0.20 : 0.12))
                            .frame(width: 48, height: 48)

                        Image(uiImage: LoveLanguageDisplay.icon(for: language))
                            .renderingMode(.template)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 24, height: 24)
                            .foregroundStyle(.white.opacity(isSelected ? 0.95 : 0.75))
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(LoveLanguageDisplay.name(for: language))
                            .knotFont(Theme.Typography.cardTitle)
                            .foregroundStyle(.white)

                        Text(LoveLanguageDisplay.description(for: language))
                            .knotFont(Theme.Typography.label)
                            .foregroundStyle(.white.opacity(0.65))
                            .lineLimit(2)
                    }

                    Spacer(minLength: 0)
                }
                .padding(16)

                if selectionState == .primary {
                    Text("PRIMARY")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.pink))
                        .padding(10)
                        .transition(.scale.combined(with: .opacity))
                } else if selectionState == .secondary {
                    Text("SECONDARY")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.pink.opacity(0.6)))
                        .padding(10)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .background(LoveLanguageDisplay.gradient(for: language))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(borderColor, lineWidth: isSelected ? 2.5 : 0.5)
            )
            .scaleEffect(selectionState == .primary ? 1.02 : 1.0)
            .opacity(isDisabled ? 0.5 : 1.0)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .animation(.easeInOut(duration: 0.25), value: selectionState)
    }

    private var borderColor: Color {
        switch selectionState {
        case .primary: return .pink
        case .secondary: return .pink.opacity(0.6)
        case .unselected: return .white.opacity(0.06)
        }
    }
}
