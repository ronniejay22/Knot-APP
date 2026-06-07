//
//  OnboardingSecondaryLoveLanguageView.swift
//  Knot
//
//  One-question screen: pick the partner's secondary love language.
//  The card matching the user's primary is shown with its primary badge
//  but disabled, so the same language can't be picked twice.
//

import SwiftUI

struct OnboardingSecondaryLoveLanguageView: View {
    @Environment(OnboardingViewModel.self) private var viewModel

    var body: some View {
        VStack(spacing: 0) {
            headerSection
                .padding(.horizontal, 24)
                .padding(.bottom, 16)

            ScrollView {
                VStack(spacing: 12) {
                    ForEach(Constants.loveLanguages, id: \.self) { language in
                        let isPrimary = language == viewModel.primaryLoveLanguage
                        let isSecondary = language == viewModel.secondaryLoveLanguage

                        LoveLanguageCard(
                            language: language,
                            selectionState: isPrimary ? .primary : (isSecondary ? .secondary : .unselected),
                            isDisabled: isPrimary
                        ) {
                            selectSecondary(language)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }
        }
        .onAppear {
            viewModel.validateCurrentStep()
        }
        .onChange(of: viewModel.secondaryLoveLanguage) { _, _ in
            viewModel.validateCurrentStep()
        }
    }

    private var headerSection: some View {
        OnboardingStepHeader(
            title: "And what's their secondary?",
            subtitle: "Pick a different language from their primary."
        )
        .padding(.top, 4)
    }

    private func selectSecondary(_ language: String) {
        guard language != viewModel.primaryLoveLanguage else { return }
        if language == viewModel.secondaryLoveLanguage {
            viewModel.secondaryLoveLanguage = ""
        } else {
            viewModel.secondaryLoveLanguage = language
        }
    }
}

#Preview {
    let vm = OnboardingViewModel()
    vm.primaryLoveLanguage = "quality_time"
    return OnboardingSecondaryLoveLanguageView()
        .background(Theme.backgroundGradient.ignoresSafeArea())
        .environment(vm)
}
