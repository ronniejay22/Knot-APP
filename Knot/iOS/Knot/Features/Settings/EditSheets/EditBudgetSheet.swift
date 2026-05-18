//
//  EditBudgetSheet.swift
//  Knot
//
//  Edit-only composite that surfaces all three budget tiers in one screen.
//  Used by the Settings → Edit Vault flow. Onboarding uses the per-tier
//  one-question-per-screen views instead.
//

import SwiftUI
import LucideIcons

struct EditBudgetSheet: View {
    @Environment(OnboardingViewModel.self) private var viewModel

    var body: some View {
        VStack(spacing: 0) {
            headerSection
                .padding(.horizontal, 24)
                .padding(.bottom, 20)

            ScrollView {
                VStack(spacing: 16) {
                    justBecauseTier
                    minorOccasionTier
                    majorMilestoneTier
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

    private var justBecauseTier: some View {
        BudgetTierCard(
            title: "Just Because",
            subtitle: "Spontaneous dates & small surprises",
            icon: Lucide.coffee,
            accentColor: Color(hue: 0.50, saturation: 0.45, brightness: 0.75),
            options: BudgetPresets.justBecause,
            selectedIDs: viewModel.justBecauseRanges,
            onToggle: { option in
                toggleBudgetRange(option, in: &viewModel.justBecauseRanges)
                syncEffectiveBudget(
                    viewModel.justBecauseRanges,
                    options: BudgetPresets.justBecause,
                    setMin: { viewModel.justBecauseMin = $0 },
                    setMax: { viewModel.justBecauseMax = $0 }
                )
            },
            onSelectAll: {
                BudgetPresets.justBecause.forEach { viewModel.justBecauseRanges.insert($0.id) }
                syncEffectiveBudget(
                    viewModel.justBecauseRanges,
                    options: BudgetPresets.justBecause,
                    setMin: { viewModel.justBecauseMin = $0 },
                    setMax: { viewModel.justBecauseMax = $0 }
                )
            }
        )
    }

    private var minorOccasionTier: some View {
        BudgetTierCard(
            title: "Minor Occasion",
            subtitle: "Smaller holidays & celebrations",
            icon: Lucide.gift,
            accentColor: Color(hue: 0.08, saturation: 0.50, brightness: 0.85),
            options: BudgetPresets.minorOccasion,
            selectedIDs: viewModel.minorOccasionRanges,
            onToggle: { option in
                toggleBudgetRange(option, in: &viewModel.minorOccasionRanges)
                syncEffectiveBudget(
                    viewModel.minorOccasionRanges,
                    options: BudgetPresets.minorOccasion,
                    setMin: { viewModel.minorOccasionMin = $0 },
                    setMax: { viewModel.minorOccasionMax = $0 }
                )
            },
            onSelectAll: {
                BudgetPresets.minorOccasion.forEach { viewModel.minorOccasionRanges.insert($0.id) }
                syncEffectiveBudget(
                    viewModel.minorOccasionRanges,
                    options: BudgetPresets.minorOccasion,
                    setMin: { viewModel.minorOccasionMin = $0 },
                    setMax: { viewModel.minorOccasionMax = $0 }
                )
            }
        )
    }

    private var majorMilestoneTier: some View {
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
    }
}

#Preview("Default") {
    EditBudgetSheet()
        .background(Theme.backgroundGradient.ignoresSafeArea())
        .environment(OnboardingViewModel())
}
