//
//  OnboardingBudgetView.swift
//  Knot
//
//  Created on February 7, 2026.
//  Step 3.1: Placeholder for onboarding Step 7 — Budget Tiers.
//  Full implementation in Step 3.7.
//

import SwiftUI
import LucideIcons

/// Step 7: Set budget ranges for three occasion types:
/// Just Because, Minor Occasion, and Major Milestone.
///
/// This is a placeholder view for Step 3.1 navigation wiring.
/// Full slider/range inputs with dollar display and defaults
/// will be built in Step 3.7.
struct OnboardingBudgetView: View {
    @Environment(OnboardingViewModel.self) private var viewModel

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(uiImage: Lucide.wallet)
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 48, height: 48)
                .foregroundStyle(Theme.accent)

            Text("Budget Ranges")
                .font(.title2.weight(.bold))

            Text("Set spending ranges for different\ntypes of occasions.")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)

            // Placeholder for budget sliders (Step 3.7)
            RoundedRectangle(cornerRadius: 12)
                .fill(Theme.surface)
                .frame(height: 200)
                .overlay {
                    Text("Budget sliders coming in Step 3.7")
                        .font(.caption)
                        .foregroundStyle(Theme.textTertiary)
                }
                .padding(.horizontal, 24)

            Spacer()
        }
        .padding(.horizontal, 24)
    }
}

#Preview {
    OnboardingBudgetView()
        .environment(OnboardingViewModel())
}
