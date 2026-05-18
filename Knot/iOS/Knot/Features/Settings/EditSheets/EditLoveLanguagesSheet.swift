//
//  EditLoveLanguagesSheet.swift
//  Knot
//
//  Edit-only composite — primary and secondary love language picked from
//  one card grid. Used by the Settings → Edit Vault flow. Onboarding uses
//  the two per-question screens instead.
//

import SwiftUI

struct EditLoveLanguagesSheet: View {
    @Environment(OnboardingViewModel.self) private var viewModel

    var body: some View {
        VStack(spacing: 0) {
            headerSection
                .padding(.horizontal, 24)
                .padding(.bottom, 16)

            ScrollView {
                VStack(spacing: 12) {
                    ForEach(Constants.loveLanguages, id: \.self) { language in
                        LoveLanguageCard(
                            language: language,
                            selectionState: selectionState(for: language)
                        ) {
                            selectLanguage(language)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }

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

    private var headerSection: some View {
        VStack(spacing: 8) {
            let name = viewModel.partnerName.trimmingCharacters(in: .whitespacesAndNewlines)
            let displayName = name.isEmpty ? "your partner" : name

            Text("How does \(displayName) feel loved?")
                .knotFont(Theme.Typography.sectionHeader)
                .foregroundStyle(Theme.textPrimary)

            Text(headerSubtitle)
                .knotFont(Theme.Typography.body)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .animation(.easeInOut(duration: 0.3), value: viewModel.primaryLoveLanguage)
                .animation(.easeInOut(duration: 0.3), value: viewModel.secondaryLoveLanguage)
        }
        .padding(.top, 4)
    }

    private var headerSubtitle: String {
        if viewModel.primaryLoveLanguage.isEmpty {
            return "Choose their primary love language first."
        } else if viewModel.secondaryLoveLanguage.isEmpty {
            return "Great! Now choose their secondary love language."
        } else {
            return "Perfect — you can change either by tapping."
        }
    }

    private var selectionStatusSection: some View {
        HStack(spacing: 6) {
            let primarySet = !viewModel.primaryLoveLanguage.isEmpty
            let secondarySet = !viewModel.secondaryLoveLanguage.isEmpty

            if primarySet && secondarySet {
                Image(systemName: "checkmark.circle.fill")
                    .knotFont(Theme.Typography.body)
                Text("Both selected")
                    .knotFont(Theme.Typography.cta)
            } else if primarySet {
                Image(systemName: "1.circle.fill")
                    .knotFont(Theme.Typography.body)
                Text("Primary set — pick secondary")
                    .knotFont(Theme.Typography.cta)
            } else {
                Text("Pick primary love language")
                    .knotFont(Theme.Typography.cta)
            }
        }
        .knotFont(Theme.Typography.body)
        .foregroundStyle(Theme.accent)
        .animation(.easeInOut(duration: 0.2), value: viewModel.primaryLoveLanguage)
        .animation(.easeInOut(duration: 0.2), value: viewModel.secondaryLoveLanguage)
    }

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
    /// 1. If no primary set → set as primary
    /// 2. Tapping the current primary → clear both (full reset)
    /// 3. Tapping the current secondary → clear secondary only
    /// 4. Primary set, no secondary → set as secondary
    /// 5. Both set → replace secondary with the tapped card
    private func selectLanguage(_ language: String) {
        if language == viewModel.primaryLoveLanguage {
            viewModel.primaryLoveLanguage = ""
            viewModel.secondaryLoveLanguage = ""
        } else if language == viewModel.secondaryLoveLanguage {
            viewModel.secondaryLoveLanguage = ""
        } else if viewModel.primaryLoveLanguage.isEmpty {
            viewModel.primaryLoveLanguage = language
        } else if viewModel.secondaryLoveLanguage.isEmpty {
            viewModel.secondaryLoveLanguage = language
        } else {
            viewModel.secondaryLoveLanguage = language
        }
    }
}

#Preview("Both Selected") {
    let vm = OnboardingViewModel()
    vm.partnerName = "Jordan"
    vm.primaryLoveLanguage = "quality_time"
    vm.secondaryLoveLanguage = "receiving_gifts"
    return EditLoveLanguagesSheet()
        .background(Theme.backgroundGradient.ignoresSafeArea())
        .environment(vm)
}
