//
//  EditBudgetSheet.swift
//  Knot
//
//  Edit-only composite that surfaces all three budget tiers in one screen.
//  Used by the Settings → Edit Vault flow. Onboarding uses the per-tier
//  one-question-per-screen views instead.
//

import SwiftUI

struct EditBudgetSheet: View {
    @Environment(OnboardingViewModel.self) private var viewModel

    var body: some View {
        @Bindable var vm = viewModel

        VStack(spacing: 0) {
            headerSection
                .padding(.horizontal, 24)
                .padding(.bottom, 20)

            ScrollView {
                VStack(spacing: 16) {
                    BudgetTierSliderCard(
                        title: "Just Because",
                        subtitle: "Spontaneous dates & small surprises",
                        accent: Color(hue: 0.50, saturation: 0.45, brightness: 0.75),
                        tier: BudgetTierConfig.justBecause,
                        minCents: $vm.justBecauseMin,
                        maxCents: $vm.justBecauseMax
                    )

                    BudgetTierSliderCard(
                        title: "Minor Occasion",
                        subtitle: "Smaller holidays & celebrations",
                        accent: Color(hue: 0.08, saturation: 0.50, brightness: 0.85),
                        tier: BudgetTierConfig.minorOccasion,
                        minCents: $vm.minorOccasionMin,
                        maxCents: $vm.minorOccasionMax
                    )

                    BudgetTierSliderCard(
                        title: "Major Milestone",
                        subtitle: "Birthdays, anniversaries & big holidays",
                        accent: Theme.accent,
                        tier: BudgetTierConfig.majorMilestone,
                        minCents: $vm.majorMilestoneMin,
                        maxCents: $vm.majorMilestoneMax
                    )
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }
        }
        .onAppear {
            viewModel.validateCurrentStep()
        }
    }

    private var headerSection: some View {
        VStack(spacing: 8) {
            let name = viewModel.partnerName.trimmingCharacters(in: .whitespacesAndNewlines)
            let displayName = name.isEmpty ? "your partner" : name

            Text("Budget for \(displayName)")
                .knotFont(Theme.Typography.sectionHeader)
                .foregroundStyle(Theme.textPrimary)

            Text("Set comfortable spending ranges\nfor each type of occasion.")
                .knotFont(Theme.Typography.body)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
        }
        .padding(.top, 4)
    }
}

#Preview("Default") {
    EditBudgetSheet()
        .background(Theme.backgroundGradient.ignoresSafeArea())
        .environment(OnboardingViewModel())
}
