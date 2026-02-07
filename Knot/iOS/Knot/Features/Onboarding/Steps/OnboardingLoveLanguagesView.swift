//
//  OnboardingLoveLanguagesView.swift
//  Knot
//
//  Created on February 7, 2026.
//  Step 3.1: Placeholder for onboarding Step 8 — Love Languages.
//  Full implementation in Step 3.8.
//

import SwiftUI
import LucideIcons

/// Step 8: Select primary and secondary love languages.
///
/// This is a placeholder view for Step 3.1 navigation wiring.
/// Full two-step selection UI (primary first, then secondary, different
/// from primary) with visual hierarchy will be built in Step 3.8.
struct OnboardingLoveLanguagesView: View {
    @Environment(OnboardingViewModel.self) private var viewModel

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(uiImage: Lucide.heartHandshake)
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 48, height: 48)
                .foregroundStyle(Theme.accent)

            Text("Love Languages")
                .font(.title2.weight(.bold))

            Text("How does your partner prefer\nto receive affection?")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)

            // Placeholder for love language selection (Step 3.8)
            RoundedRectangle(cornerRadius: 12)
                .fill(Theme.surface)
                .frame(height: 200)
                .overlay {
                    VStack(spacing: 8) {
                        Text("Primary: \(viewModel.primaryLoveLanguage.isEmpty ? "Not set" : viewModel.primaryLoveLanguage)")
                            .font(.caption)
                            .foregroundStyle(Theme.textTertiary)
                        Text("Secondary: \(viewModel.secondaryLoveLanguage.isEmpty ? "Not set" : viewModel.secondaryLoveLanguage)")
                            .font(.caption)
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
                .padding(.horizontal, 24)

            Spacer()
        }
        .padding(.horizontal, 24)
    }
}

#Preview {
    OnboardingLoveLanguagesView()
        .environment(OnboardingViewModel())
}
