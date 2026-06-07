//
//  OnboardingPrimaryLoveLanguageView.swift
//  Knot
//
//  One-question screen: pick the partner's primary love language.
//

import SwiftUI

struct OnboardingPrimaryLoveLanguageView: View {
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
                            selectionState: language == viewModel.primaryLoveLanguage ? .primary : .unselected
                        ) {
                            selectPrimary(language)
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
        .onChange(of: viewModel.primaryLoveLanguage) { _, _ in
            viewModel.validateCurrentStep()
        }
    }

    private var headerSection: some View {
        let name = viewModel.partnerName.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = name.isEmpty ? "your partner" : name

        return OnboardingStepHeader(
            title: "How does \(displayName) feel most loved?",
            subtitle: "Pick their primary love language."
        )
        .padding(.top, 4)
    }

    private func selectPrimary(_ language: String) {
        if language == viewModel.primaryLoveLanguage {
            viewModel.primaryLoveLanguage = ""
            viewModel.secondaryLoveLanguage = ""
        } else {
            if language == viewModel.secondaryLoveLanguage {
                viewModel.secondaryLoveLanguage = ""
            }
            viewModel.primaryLoveLanguage = language
        }
    }
}

#Preview {
    OnboardingPrimaryLoveLanguageView()
        .background(Theme.backgroundGradient.ignoresSafeArea())
        .environment(OnboardingViewModel())
}
