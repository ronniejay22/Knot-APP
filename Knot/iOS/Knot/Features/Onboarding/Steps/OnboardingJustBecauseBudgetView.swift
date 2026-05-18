//
//  OnboardingJustBecauseBudgetView.swift
//  Knot
//
//  One-question screen: budget for spontaneous "just because" gestures.
//

import SwiftUI
import LucideIcons

struct OnboardingJustBecauseBudgetView: View {
    @Environment(OnboardingViewModel.self) private var viewModel

    private let accent = Color(hue: 0.50, saturation: 0.45, brightness: 0.75)

    var body: some View {
        VStack(spacing: 0) {
            headerSection
                .padding(.horizontal, 24)
                .padding(.bottom, 20)

            ScrollView {
                BudgetTierCard(
                    title: "Just Because",
                    subtitle: "Spontaneous dates & small surprises",
                    icon: Lucide.coffee,
                    accentColor: accent,
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

            Text("Just because, what feels right?")
                .knotFont(Theme.Typography.sectionHeader)
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)

            Text("Set a spending range for small, spontaneous things for \(displayName).")
                .knotFont(Theme.Typography.body)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
        }
        .padding(.top, 4)
    }
}

#Preview {
    OnboardingJustBecauseBudgetView()
        .background(Theme.backgroundGradient.ignoresSafeArea())
        .environment(OnboardingViewModel())
}
