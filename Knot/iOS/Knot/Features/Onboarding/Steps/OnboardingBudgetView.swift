//
//  OnboardingBudgetView.swift
//  Knot
//
//  Single consolidated budget step: all three tiers (Just Because, Minor
//  Occasion, Major Milestone) on one page, each with a dual-thumb range slider.
//  Replaces the former three per-tier screens.
//

import SwiftUI
import LucideIcons

struct OnboardingBudgetView: View {
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
                        icon: Lucide.coffee,
                        accent: Color(hue: 0.50, saturation: 0.45, brightness: 0.75),
                        tier: BudgetTierConfig.justBecause,
                        minCents: $vm.justBecauseMin,
                        maxCents: $vm.justBecauseMax
                    )

                    BudgetTierSliderCard(
                        title: "Minor Occasion",
                        subtitle: "Smaller holidays & celebrations",
                        icon: Lucide.gift,
                        accent: Color(hue: 0.08, saturation: 0.50, brightness: 0.85),
                        tier: BudgetTierConfig.minorOccasion,
                        minCents: $vm.minorOccasionMin,
                        maxCents: $vm.minorOccasionMax
                    )

                    BudgetTierSliderCard(
                        title: "Major Milestone",
                        subtitle: "Birthdays, anniversaries & big holidays",
                        icon: Lucide.sparkles,
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
        let name = viewModel.partnerName.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = name.isEmpty ? "your partner" : name

        return OnboardingStepHeader(
            title: "What feels right to spend?",
            subtitle: "Set a comfortable range for each kind of occasion with \(displayName)."
        )
        .padding(.top, 4)
    }
}

#Preview {
    OnboardingBudgetView()
        .background(Theme.backgroundGradient.ignoresSafeArea())
        .environment(OnboardingViewModel())
}
