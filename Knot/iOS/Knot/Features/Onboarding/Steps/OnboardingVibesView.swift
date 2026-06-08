//
//  OnboardingVibesView.swift
//  Knot
//
//  Created on February 7, 2026.
//  Step 3.1: Placeholder for onboarding Step 6 — Aesthetic Vibes.
//  Step 3.6: Full implementation — dark-themed 2-column visual card grid
//            with Lucide icons, descriptions, and multi-select (min 1, no max).
//  Updated: The onboarding step itself converted to the shared vertical-list
//           experience (`InterestListRow`) used by the interests/dislikes steps —
//           SF Symbol icon chips (`vibeSymbol(for:)`) plus a description subtitle.
//           The Lucide `vibeIcon(for:)` + `vibeGradient(for:)` helpers are kept
//           for the Recommendations and Completion screens that still render the
//           gradient vibe cards.
//

import SwiftUI
import LucideIcons

/// Step 6: Select aesthetic vibes that describe the partner's style.
///
/// Single-column vertical list of vibe rows, matching the onboarding
/// interests/dislikes screens. Each row shows an SF Symbol icon chip, the vibe
/// display name, and a short description subtitle. The user must select at
/// least 1 vibe (no maximum).
///
/// Features:
/// - Personalized title using the partner's name from Step 3.2
/// - Vertical list of 8 vibe rows (`InterestListRow`) with SF Symbol icons
/// - Selection counter showing "X selected" with checkmark when at least 1 chosen
/// - No maximum limit — all 8 vibes can be selected
/// - Accent border + checkmark for selected state
struct OnboardingVibesView: View {
    @Environment(OnboardingViewModel.self) private var viewModel

    var body: some View {
        VStack(spacing: 0) {
            // MARK: - Header
            headerSection
                .padding(.horizontal, 24)
                .padding(.bottom, 16)

            // MARK: - Vibe List
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(Constants.vibeOptions, id: \.self) { vibe in
                        InterestListRow(
                            title: Self.displayName(for: vibe),
                            iconName: Self.vibeSymbol(for: vibe),
                            subtitle: Self.vibeDescription(for: vibe),
                            isSelected: viewModel.selectedVibes.contains(vibe)
                        ) {
                            toggleVibe(vibe)
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }

            // MARK: - Selection Counter
            counterSection
                .padding(.horizontal, 24)
                .padding(.vertical, 10)
        }
        .onAppear {
            viewModel.validateCurrentStep()
        }
        .onChange(of: viewModel.selectedVibes) { _, _ in
            viewModel.validateCurrentStep()
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        let name = viewModel.partnerName.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = name.isEmpty ? "their" : "\(name)'s"

        return OnboardingStepHeader(
            title: "What's \(displayName) aesthetic?",
            subtitle: "Choose vibes that match their style. This shapes the look and feel of our suggestions."
        )
        .padding(.top, 4)
    }

    // MARK: - Selection Counter

    private var counterSection: some View {
        let count = viewModel.selectedVibes.count

        return HStack(spacing: 4) {
            Text("\(count) selected")
                .knotFont(Theme.Typography.cta)

            if count == 0 {
                Text("(pick at least 1)")
                    .knotFont(Theme.Typography.body)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(.subheadline)
            }
        }
        .foregroundStyle(Theme.accent)
        .animation(.easeInOut(duration: 0.2), value: count)
    }

    // MARK: - Selection Logic

    private func toggleVibe(_ vibe: String) {
        if viewModel.selectedVibes.contains(vibe) {
            viewModel.selectedVibes.remove(vibe)
        } else {
            viewModel.selectedVibes.insert(vibe)
        }
    }

    // MARK: - Vibe Display Names

    /// Converts snake_case vibe keys to human-readable display names.
    static func displayName(for vibe: String) -> String {
        let names: [String: String] = [
            "quiet_luxury": "Quiet Luxury",
            "street_urban": "Street / Urban",
            "outdoorsy": "Outdoorsy",
            "vintage": "Vintage",
            "minimalist": "Minimalist",
            "bohemian": "Bohemian",
            "romantic": "Romantic",
            "adventurous": "Adventurous"
        ]
        return names[vibe] ?? vibe.replacingOccurrences(of: "_", with: " ").capitalized
    }

    // MARK: - Vibe Descriptions

    /// Short descriptions for each vibe to help the user understand the aesthetic.
    static func vibeDescription(for vibe: String) -> String {
        let descriptions: [String: String] = [
            "quiet_luxury": "Elegant & understated",
            "street_urban": "City vibes & streetwear",
            "outdoorsy": "Nature & fresh air",
            "vintage": "Retro & timeless",
            "minimalist": "Clean & simple",
            "bohemian": "Free-spirited & eclectic",
            "romantic": "Dreamy & sentimental",
            "adventurous": "Bold & thrill-seeking"
        ]
        return descriptions[vibe] ?? ""
    }

    // MARK: - Vibe Symbols (list rows)

    /// Maps each vibe to an SF Symbol, matching the icon-chip style used by the
    /// interests/dislikes list rows. Used by the onboarding step's `InterestListRow`s.
    static func vibeSymbol(for vibe: String) -> String {
        switch vibe {
        case "quiet_luxury": return "diamond"
        case "street_urban": return "building.2.fill"
        case "outdoorsy":    return "leaf.fill"
        case "vintage":      return "clock.arrow.circlepath"
        case "minimalist":   return "circle"
        case "bohemian":     return "sun.max.fill"
        case "romantic":     return "heart.fill"
        case "adventurous":  return "safari"
        default:             return "sparkles"
        }
    }

    // MARK: - Lucide Icons (gradient cards)

    /// Maps each vibe to a Lucide icon. Used by the Recommendations and
    /// Completion screens that still render the gradient vibe cards.
    static func vibeIcon(for vibe: String) -> UIImage {
        switch vibe {
        case "quiet_luxury": return Lucide.gem
        case "street_urban": return Lucide.building2
        case "outdoorsy": return Lucide.trees
        case "vintage": return Lucide.watch
        case "minimalist": return Lucide.penLine
        case "bohemian": return Lucide.sun
        case "romantic": return Lucide.heart
        case "adventurous": return Lucide.compass
        default: return Lucide.sparkles
        }
    }

    // MARK: - Card Gradients

    /// Generates a themed gradient for each vibe with a unique color palette.
    /// Used by the Recommendations and Completion gradient vibe cards.
    static func vibeGradient(for vibe: String) -> LinearGradient {
        let colors: (Color, Color) = {
            switch vibe {
            case "quiet_luxury":
                return (
                    Color(hue: 0.08, saturation: 0.35, brightness: 0.45),
                    Color(hue: 0.08, saturation: 0.50, brightness: 0.20)
                )
            case "street_urban":
                return (
                    Color(hue: 0.60, saturation: 0.30, brightness: 0.40),
                    Color(hue: 0.62, saturation: 0.45, brightness: 0.18)
                )
            case "outdoorsy":
                return (
                    Color(hue: 0.35, saturation: 0.55, brightness: 0.45),
                    Color(hue: 0.38, saturation: 0.65, brightness: 0.18)
                )
            case "vintage":
                return (
                    Color(hue: 0.05, saturation: 0.50, brightness: 0.48),
                    Color(hue: 0.07, saturation: 0.60, brightness: 0.20)
                )
            case "minimalist":
                return (
                    Color(hue: 0.55, saturation: 0.10, brightness: 0.45),
                    Color(hue: 0.55, saturation: 0.15, brightness: 0.20)
                )
            case "bohemian":
                return (
                    Color(hue: 0.12, saturation: 0.60, brightness: 0.50),
                    Color(hue: 0.15, saturation: 0.70, brightness: 0.22)
                )
            case "romantic":
                return (
                    Color(hue: 0.92, saturation: 0.50, brightness: 0.50),
                    Color(hue: 0.95, saturation: 0.65, brightness: 0.22)
                )
            case "adventurous":
                return (
                    Color(hue: 0.55, saturation: 0.60, brightness: 0.50),
                    Color(hue: 0.58, saturation: 0.70, brightness: 0.22)
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

// MARK: - Previews

#Preview("Empty") {
    OnboardingVibesView()
        .background(Theme.backgroundGradient.ignoresSafeArea())
        .environment(OnboardingViewModel())
}

#Preview("2 Selected") {
    let vm = OnboardingViewModel()
    vm.partnerName = "Alex"
    vm.selectedVibes = ["quiet_luxury", "romantic"]
    return OnboardingVibesView()
        .background(Theme.backgroundGradient.ignoresSafeArea())
        .environment(vm)
}

#Preview("4 Selected (Max)") {
    let vm = OnboardingViewModel()
    vm.partnerName = "Jordan"
    vm.selectedVibes = ["quiet_luxury", "minimalist", "romantic", "vintage"]
    return OnboardingVibesView()
        .background(Theme.backgroundGradient.ignoresSafeArea())
        .environment(vm)
}
