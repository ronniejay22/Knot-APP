//
//  OnboardingWelcomeView.swift
//  Knot
//

import SwiftUI

struct OnboardingWelcomeView: View {
    @Environment(OnboardingViewModel.self) private var viewModel

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                Text("Build Your Partner Vault")
                    .knotFont(Theme.Typography.onboardingHeader)
                    .tracking(-0.5)
                    .multilineTextAlignment(.center)

                Text("Tell us about your partner so we can find\nperfect gifts, dates, and experiences.")
                    .knotFont(Theme.Typography.body)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }
            .padding(.horizontal, 24)
            .padding(.top, 64)

            Spacer().frame(height: 40)

            Image("Onboarding/onboarding-0")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(maxWidth: .infinity)
                .frame(height: 340)
                .clipped()

            Spacer(minLength: 24)
        }
    }
}

#Preview {
    OnboardingWelcomeView()
        .environment(OnboardingViewModel())
}
