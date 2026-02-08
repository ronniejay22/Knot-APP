//
//  OnboardingLoveLanguagesView.swift
//  Knot
//
//  Created on February 7, 2026.
//  Step 3.1: Placeholder for onboarding Step 8 — Love Languages.
//  Step 3.8: Full implementation — two-step selection (primary then
//            secondary) with visual hierarchy, unique gradients, and
//            Lucide icons per love language.
//

import SwiftUI
import LucideIcons

/// Step 8: Select primary and secondary love languages.
///
/// Dark-themed screen with 5 full-width love language cards. Implements a
/// two-step selection flow: (1) tap a card to set it as Primary, (2) tap
/// a different card to set it as Secondary. Clear visual hierarchy
/// distinguishes Primary (prominent pink border + "PRIMARY" badge + scale)
/// from Secondary (lighter accent border + "SECONDARY" badge).
///
/// Selection flow:
/// 1. No selection → tap a card → becomes **Primary**
/// 2. Primary set → tap a different card → becomes **Secondary**
/// 3. Both set → tap a third card → replaces Secondary
/// 4. Tap current Primary → clears both (reset)
/// 5. Tap current Secondary → clears Secondary only
/// 6. Same card cannot be both Primary and Secondary
///
/// Validation: Both primary and secondary must be set before "Next" enables.
struct OnboardingLoveLanguagesView: View {
    @Environment(OnboardingViewModel.self) private var viewModel

    var body: some View {
        VStack(spacing: 0) {
            // MARK: - Header
            headerSection
                .padding(.horizontal, 24)
                .padding(.bottom, 16)

            // MARK: - Love Language Cards
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(Constants.loveLanguages, id: \.self) { language in
                        LoveLanguageCard(
                            language: language,
                            displayName: Self.displayName(for: language),
                            description: Self.languageDescription(for: language),
                            icon: Self.languageIcon(for: language),
                            gradient: Self.languageGradient(for: language),
                            selectionState: selectionState(for: language)
                        ) {
                            selectLanguage(language)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }

            // MARK: - Selection Status
            selectionStatusSection
                .padding(.horizontal, 24)
                .padding(.vertical, 10)
        }
        .onAppear {
            viewModel.validateCurrentStep()
        }
        .onChange(of: viewModel.primaryLoveLanguage) { _, _ in
            viewModel.validateCurrentStep()
        }
        .onChange(of: viewModel.secondaryLoveLanguage) { _, _ in
            viewModel.validateCurrentStep()
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 8) {
            let name = viewModel.partnerName.trimmingCharacters(in: .whitespacesAndNewlines)
            let displayName = name.isEmpty ? "your partner" : name

            Text("How does \(displayName) feel loved?")
                .font(.title.weight(.bold))
                .foregroundStyle(Theme.textPrimary)

            Text(headerSubtitle)
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .animation(.easeInOut(duration: 0.3), value: viewModel.primaryLoveLanguage)
                .animation(.easeInOut(duration: 0.3), value: viewModel.secondaryLoveLanguage)
        }
        .padding(.top, 4)
    }

    /// Dynamic subtitle that guides the user through the two-step selection.
    private var headerSubtitle: String {
        if viewModel.primaryLoveLanguage.isEmpty {
            return "Choose their primary love language first."
        } else if viewModel.secondaryLoveLanguage.isEmpty {
            return "Great! Now choose their secondary love language."
        } else {
            return "Perfect — you can change either by tapping."
        }
    }

    // MARK: - Selection Status

    private var selectionStatusSection: some View {
        HStack(spacing: 6) {
            let primarySet = !viewModel.primaryLoveLanguage.isEmpty
            let secondarySet = !viewModel.secondaryLoveLanguage.isEmpty

            if primarySet && secondarySet {
                Image(systemName: "checkmark.circle.fill")
                    .font(.subheadline)
                Text("Both selected")
                    .fontWeight(.semibold)
            } else if primarySet {
                Image(systemName: "1.circle.fill")
                    .font(.subheadline)
                Text("Primary set — pick secondary")
                    .fontWeight(.semibold)
            } else {
                Text("Pick primary love language")
                    .fontWeight(.semibold)
            }
        }
        .font(.subheadline)
        .foregroundStyle(Theme.accent)
        .animation(.easeInOut(duration: 0.2), value: viewModel.primaryLoveLanguage)
        .animation(.easeInOut(duration: 0.2), value: viewModel.secondaryLoveLanguage)
    }

    // MARK: - Selection Logic

    /// Returns the selection state of a love language card.
    private func selectionState(for language: String) -> LoveLanguageSelectionState {
        if language == viewModel.primaryLoveLanguage {
            return .primary
        } else if language == viewModel.secondaryLoveLanguage {
            return .secondary
        } else {
            return .unselected
        }
    }

    /// Handles tapping a love language card.
    ///
    /// Selection flow:
    /// 1. If no primary set → set as primary
    /// 2. If tapping the current primary → clear both (full reset)
    /// 3. If tapping the current secondary → clear secondary only
    /// 4. If primary is set but no secondary → set as secondary
    /// 5. If both are set → replace secondary with the tapped card
    private func selectLanguage(_ language: String) {
        if language == viewModel.primaryLoveLanguage {
            // Tapping primary clears both selections (reset)
            viewModel.primaryLoveLanguage = ""
            viewModel.secondaryLoveLanguage = ""
        } else if language == viewModel.secondaryLoveLanguage {
            // Tapping secondary clears just secondary
            viewModel.secondaryLoveLanguage = ""
        } else if viewModel.primaryLoveLanguage.isEmpty {
            // No primary yet — set this as primary
            viewModel.primaryLoveLanguage = language
        } else if viewModel.secondaryLoveLanguage.isEmpty {
            // Primary set, no secondary — set as secondary
            viewModel.secondaryLoveLanguage = language
        } else {
            // Both set — replace secondary
            viewModel.secondaryLoveLanguage = language
        }
    }

    // MARK: - Display Name Mapping

    /// Converts snake_case love language keys to human-readable display names.
    static func displayName(for language: String) -> String {
        let names: [String: String] = [
            "words_of_affirmation": "Words of Affirmation",
            "acts_of_service": "Acts of Service",
            "receiving_gifts": "Receiving Gifts",
            "quality_time": "Quality Time",
            "physical_touch": "Physical Touch"
        ]
        return names[language] ?? language.replacingOccurrences(of: "_", with: " ").capitalized
    }

    // MARK: - Description Mapping

    /// Contextual descriptions for each love language.
    static func languageDescription(for language: String) -> String {
        let descriptions: [String: String] = [
            "words_of_affirmation": "They feel loved through compliments, encouragement, and heartfelt messages.",
            "acts_of_service": "Actions speak louder — they appreciate helpful, thoughtful gestures.",
            "receiving_gifts": "Meaningful, well-chosen gifts make them feel truly seen and valued.",
            "quality_time": "Undivided attention and shared experiences matter most to them.",
            "physical_touch": "Closeness, comfort, and physical connection bring them joy."
        ]
        return descriptions[language] ?? ""
    }

    // MARK: - Icon Mapping

    /// Maps each love language to a Lucide icon.
    static func languageIcon(for language: String) -> UIImage {
        switch language {
        case "words_of_affirmation": return Lucide.messageCircle
        case "acts_of_service": return Lucide.heartHandshake
        case "receiving_gifts": return Lucide.gift
        case "quality_time": return Lucide.clock
        case "physical_touch": return Lucide.hand
        default: return Lucide.heart
        }
    }

    // MARK: - Gradient Mapping

    /// Unique background gradient for each love language.
    static func languageGradient(for language: String) -> LinearGradient {
        let colors: (Color, Color) = {
            switch language {
            case "words_of_affirmation":
                // Warm peach / coral
                return (
                    Color(hue: 0.04, saturation: 0.45, brightness: 0.50),
                    Color(hue: 0.06, saturation: 0.55, brightness: 0.22)
                )
            case "acts_of_service":
                // Earthy teal / green
                return (
                    Color(hue: 0.38, saturation: 0.50, brightness: 0.42),
                    Color(hue: 0.40, saturation: 0.60, brightness: 0.18)
                )
            case "receiving_gifts":
                // Rich purple / magenta
                return (
                    Color(hue: 0.82, saturation: 0.50, brightness: 0.50),
                    Color(hue: 0.85, saturation: 0.60, brightness: 0.22)
                )
            case "quality_time":
                // Warm amber / gold
                return (
                    Color(hue: 0.12, saturation: 0.55, brightness: 0.52),
                    Color(hue: 0.14, saturation: 0.65, brightness: 0.22)
                )
            case "physical_touch":
                // Deep rose / blush
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

// MARK: - Selection State

/// The three possible selection states for a love language card.
private enum LoveLanguageSelectionState: Equatable {
    case unselected
    case primary
    case secondary
}

// MARK: - Love Language Card

/// A full-width card representing a single love language option.
///
/// Layout: gradient background with icon + text on the left, and an
/// independent badge overlay pinned to the top-right corner. The badge
/// is in a separate `ZStack` layer so it never affects text layout.
///
/// Visual states:
/// - **Unselected:** Gradient background, subtle border, 1.0 scale
/// - **Primary:** Pink border, "PRIMARY" badge (top-right), 1.02 scale
/// - **Secondary:** Muted pink border, "SECONDARY" badge (top-right)
private struct LoveLanguageCard: View {
    let language: String
    let displayName: String
    let description: String
    let icon: UIImage
    let gradient: LinearGradient
    let selectionState: LoveLanguageSelectionState
    let action: () -> Void

    private var isSelected: Bool {
        selectionState != .unselected
    }

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                // Card content — icon + text (never changes layout)
                HStack(spacing: 16) {
                    // Icon badge
                    ZStack {
                        Circle()
                            .fill(.white.opacity(isSelected ? 0.20 : 0.12))
                            .frame(width: 48, height: 48)

                        Image(uiImage: icon)
                            .renderingMode(.template)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 24, height: 24)
                            .foregroundStyle(.white.opacity(isSelected ? 0.95 : 0.75))
                    }

                    // Name + description (stable layout, no badges here)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(displayName)
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.white)

                        Text(description)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.65))
                            .lineLimit(2)
                    }

                    Spacer(minLength: 0)
                }
                .padding(16)

                // Selection badge — pinned top-right, independent of text
                if selectionState == .primary {
                    Text("PRIMARY")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(Color.pink)
                        )
                        .padding(10)
                        .transition(.scale.combined(with: .opacity))
                } else if selectionState == .secondary {
                    Text("SECONDARY")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(Color.pink.opacity(0.6))
                        )
                        .padding(10)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .background(gradient)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        borderColor,
                        lineWidth: isSelected ? 2.5 : 0.5
                    )
            )
            .scaleEffect(selectionState == .primary ? 1.02 : 1.0)
        }
        .buttonStyle(.plain)
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

// MARK: - Previews

#Preview("Empty") {
    OnboardingLoveLanguagesView()
        .background(Theme.backgroundGradient.ignoresSafeArea())
        .environment(OnboardingViewModel())
}

#Preview("Primary Only") {
    let vm = OnboardingViewModel()
    vm.partnerName = "Alex"
    vm.primaryLoveLanguage = "quality_time"
    return OnboardingLoveLanguagesView()
        .background(Theme.backgroundGradient.ignoresSafeArea())
        .environment(vm)
}

#Preview("Both Selected") {
    let vm = OnboardingViewModel()
    vm.partnerName = "Jordan"
    vm.primaryLoveLanguage = "quality_time"
    vm.secondaryLoveLanguage = "receiving_gifts"
    return OnboardingLoveLanguagesView()
        .background(Theme.backgroundGradient.ignoresSafeArea())
        .environment(vm)
}
