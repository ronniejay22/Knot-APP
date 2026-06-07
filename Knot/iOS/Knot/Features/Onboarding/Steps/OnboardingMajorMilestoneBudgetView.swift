//
//  OnboardingMajorMilestoneBudgetView.swift
//  Knot
//
//  One-question screen: budget for major milestones (birthday, anniversary).
//

import SwiftUI
import LucideIcons

struct OnboardingMajorMilestoneBudgetView: View {
    @Environment(OnboardingViewModel.self) private var viewModel

    var body: some View {
        VStack(spacing: 0) {
            headerSection
                .padding(.horizontal, 24)
                .padding(.bottom, 20)

            ScrollView {
                BudgetTierCard(
                    title: "Major Milestone",
                    subtitle: "Birthdays, anniversaries & big holidays",
                    icon: Lucide.sparkles,
                    accentColor: Theme.accent,
                    options: BudgetPresets.majorMilestone,
                    selectedIDs: viewModel.majorMilestoneRanges,
                    onToggle: { option in
                        toggleBudgetRange(option, in: &viewModel.majorMilestoneRanges)
                        syncEffectiveBudget(
                            viewModel.majorMilestoneRanges,
                            options: BudgetPresets.majorMilestone,
                            setMin: { viewModel.majorMilestoneMin = $0 },
                            setMax: { viewModel.majorMilestoneMax = $0 }
                        )
                    },
                    onSelectAll: {
                        BudgetPresets.majorMilestone.forEach { viewModel.majorMilestoneRanges.insert($0.id) }
                        syncEffectiveBudget(
                            viewModel.majorMilestoneRanges,
                            options: BudgetPresets.majorMilestone,
                            setMin: { viewModel.majorMilestoneMin = $0 },
                            setMax: { viewModel.majorMilestoneMax = $0 }
                        )
                    }
                )
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }
        }
        .onAppear {
            viewModel.validateCurrentStep()
        }
    }

    private var headerSection: some View {
        OnboardingHeader(
            title: "And for major milestones?",
            subtitle: "Birthdays, anniversaries, big holidays — set the range that feels right."
        )
        .padding(.top, 4)
    }
}

#Preview {
    OnboardingMajorMilestoneBudgetView()
        .background(Theme.backgroundGradient.ignoresSafeArea())
        .environment(OnboardingViewModel())
}
