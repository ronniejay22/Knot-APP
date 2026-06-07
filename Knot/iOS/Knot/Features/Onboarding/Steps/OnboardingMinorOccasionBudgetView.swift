//
//  OnboardingMinorOccasionBudgetView.swift
//  Knot
//
//  One-question screen: budget for smaller holidays and celebrations.
//

import SwiftUI
import LucideIcons

struct OnboardingMinorOccasionBudgetView: View {
    @Environment(OnboardingViewModel.self) private var viewModel

    private let accent = Color(hue: 0.08, saturation: 0.50, brightness: 0.85)

    var body: some View {
        VStack(spacing: 0) {
            headerSection
                .padding(.horizontal, 24)
                .padding(.bottom, 20)

            ScrollView {
                BudgetTierCard(
                    title: "Minor Occasion",
                    subtitle: "Smaller holidays & celebrations",
                    icon: Lucide.gift,
                    accentColor: accent,
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
            title: "And for minor occasions?",
            subtitle: "Set a spending range for smaller holidays and celebrations."
        )
        .padding(.top, 4)
    }
}

#Preview {
    OnboardingMinorOccasionBudgetView()
        .background(Theme.backgroundGradient.ignoresSafeArea())
        .environment(OnboardingViewModel())
}
