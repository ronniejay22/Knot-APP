//
//  OnboardingLoveLanguagesView.swift
//  Knot
//
//  Combined love languages onboarding step. Captures both the primary and
//  secondary love language on a single screen using a guided sequential tap:
//  the first tap sets the primary, the second sets the secondary, and a
//  dynamic subtitle guides the user. Replaces the former two-screen split
//  (OnboardingPrimaryLoveLanguageView + OnboardingSecondaryLoveLanguageView).
//

import SwiftUI

/// Single-screen love language selection.
///
/// Selection model (`select(_:)`):
/// - Tap an unselected card → fills the primary first, then the secondary.
/// - Tap the PRIMARY card → promotes the secondary up to primary (or clears
///   primary if there's no secondary), keeping the badges contiguous.
/// - Tap the SECONDARY card → clears the secondary.
///
/// This lets the user freely change either pick without any disabled cards.
struct OnboardingLoveLanguagesView: View {
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
                            selectionState: isPrimary ? .primary : (isSecondary ? .secondary : .unselected)
                        ) {
                            select(language)
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
        .onChange(of: viewModel.secondaryLoveLanguage) { _, _ in
            viewModel.validateCurrentStep()
        }
    }

    private var headerSection: some View {
        let name = viewModel.partnerName.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = name.isEmpty ? "your partner" : name

        return OnboardingStepHeader(
            title: "How does \(displayName) feel most loved?",
            subtitle: subtitle
        )
        .padding(.top, 4)
    }

    /// Guides the user through the two-step pick with a single line of copy.
    private var subtitle: String {
        if viewModel.primaryLoveLanguage.isEmpty {
            return "Pick their primary love language."
        } else if viewModel.secondaryLoveLanguage.isEmpty {
            return "Now pick their secondary."
        } else {
            return "Tap any card to change your picks."
        }
    }

    /// Applies the guided sequential selection rules described in the type doc.
    private func select(_ language: String) {
        if language == viewModel.primaryLoveLanguage {
            // Deselect primary; promote secondary up so PRIMARY always
            // precedes SECONDARY (secondary may be "" — that just clears it).
            viewModel.primaryLoveLanguage = viewModel.secondaryLoveLanguage
            viewModel.secondaryLoveLanguage = ""
        } else if language == viewModel.secondaryLoveLanguage {
            viewModel.secondaryLoveLanguage = ""
        } else if viewModel.primaryLoveLanguage.isEmpty {
            viewModel.primaryLoveLanguage = language
        } else {
            // Fills the secondary, or replaces an existing one.
            viewModel.secondaryLoveLanguage = language
        }
    }
}
