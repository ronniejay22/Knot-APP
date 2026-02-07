//
//  OnboardingVibesView.swift
//  Knot
//
//  Created on February 7, 2026.
//  Step 3.1: Placeholder for onboarding Step 6 — Aesthetic Vibes.
//  Step 3.6: Full implementation — dark-themed 2-column visual card grid
//            with Lucide icons, descriptions, and multi-select (min 1, no max).
//

import SwiftUI
import LucideIcons

/// Step 6: Select aesthetic vibes that describe the partner's style.
///
/// Dark-themed screen with a 2-column grid of visual vibe cards. Each card
/// displays a themed gradient background, a Lucide icon, the vibe display name,
/// and a short description. The user must select at least 1 vibe (no maximum).
///
/// Features:
/// - Personalized title using the partner's name from Step 3.2
/// - 2-column grid of 8 vibe cards with unique gradients and Lucide icons
/// - Selection counter showing "X selected" with checkmark when at least 1 chosen
/// - No maximum limit — all 8 vibes can be selected
/// - Pink border + checkmark badge for selected state
struct OnboardingVibesView: View {
    @Environment(OnboardingViewModel.self) private var viewModel

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 2)

    var body: some View {
        VStack(spacing: 0) {
            // MARK: - Header
            headerSection
                .padding(.horizontal, 24)
                .padding(.bottom, 16)

            // MARK: - Card Grid
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(Constants.vibeOptions, id: \.self) { vibe in
                        VibeCard(
                            vibe: vibe,
                            displayName: Self.displayName(for: vibe),
                            description: Self.vibeDescription(for: vibe),
                            icon: Self.vibeIcon(for: vibe),
                            gradient: Self.vibeGradient(for: vibe),
                            isSelected: viewModel.selectedVibes.contains(vibe)
                        ) {
                            toggleVibe(vibe)
                        }
                    }
                }
                .padding(.horizontal, 20)
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
        VStack(spacing: 8) {
            let name = viewModel.partnerName.trimmingCharacters(in: .whitespacesAndNewlines)
            let displayName = name.isEmpty ? "their" : "\(name)'s"

            Text("What's \(displayName) aesthetic?")
                .font(.title.weight(.bold))
                .foregroundStyle(Theme.textPrimary)

            Text("Choose vibes that match their style.\nThis shapes the look and feel of our suggestions.")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
        }
        .padding(.top, 4)
    }

    // MARK: - Selection Counter

    private var counterSection: some View {
        let count = viewModel.selectedVibes.count

        return HStack(spacing: 4) {
            Text("\(count) selected")
                .fontWeight(.semibold)

            if count == 0 {
                Text("(pick at least 1)")
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(.subheadline)
            }
        }
        .font(.subheadline)
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

    // MARK: - Lucide Icons

    /// Maps each vibe to a Lucide icon.
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

// MARK: - Vibe Card

/// A visual card representing a single aesthetic vibe option.
///
/// Displays a themed gradient background with a centered Lucide icon,
/// the vibe display name, and a short description. Larger than interest cards
/// since there are only 8 vibes (2-column grid vs 3-column).
///
/// Visual states:
/// - **Unselected:** Gradient background, semi-transparent icon, white text
/// - **Selected:** Pink border, checkmark badge in top-right corner, slight scale-up
private struct VibeCard: View {
    let vibe: String
    let displayName: String
    let description: String
    let icon: UIImage
    let gradient: LinearGradient
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                // Gradient background
                gradient

                // Dark overlay for text readability
                LinearGradient(
                    colors: [.clear, .black.opacity(0.40)],
                    startPoint: .top,
                    endPoint: .bottom
                )

                // Large Lucide icon (centered, semi-transparent)
                Image(uiImage: icon)
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 36, height: 36)
                    .foregroundStyle(.white.opacity(0.18))
                    .offset(x: 30, y: -20)

                // Content — vibe name + description at bottom-left
                VStack(alignment: .leading, spacing: 4) {
                    Spacer()

                    // Lucide icon (small, above name)
                    Image(uiImage: icon)
                        .renderingMode(.template)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 22, height: 22)
                        .foregroundStyle(.white.opacity(0.85))

                    Text(displayName)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)

                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.70))
                        .shadow(color: .black.opacity(0.4), radius: 1, x: 0, y: 1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)

                // Selection checkmark badge — top-right
                if isSelected {
                    VStack {
                        HStack {
                            Spacer()
                            Circle()
                                .fill(Color.pink)
                                .frame(width: 26, height: 26)
                                .overlay {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundStyle(.white)
                                }
                                .shadow(color: .black.opacity(0.3), radius: 3, x: 0, y: 1)
                        }
                        Spacer()
                    }
                    .padding(10)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .aspectRatio(1.25, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        isSelected ? Color.pink : Color.white.opacity(0.06),
                        lineWidth: isSelected ? 2.5 : 0.5
                    )
            )
            .scaleEffect(isSelected ? 1.02 : 1.0)
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.25), value: isSelected)
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
