//
//  OnboardingTenureView.swift
//  Knot
//
//  One-question screen: how long the user and their partner have been together.
//

import SwiftUI

struct OnboardingTenureView: View {
    @Environment(OnboardingViewModel.self) private var viewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                headerSection

                RelationshipLengthField(
                    months: Binding(
                        get: { viewModel.relationshipTenureMonths },
                        set: { viewModel.relationshipTenureMonths = $0 }
                    ),
                    required: true,
                    hasSelection: Binding(
                        get: { viewModel.hasSetTenure },
                        set: { viewModel.hasSetTenure = $0 }
                    )
                )
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .onAppear {
            viewModel.validateCurrentStep()
        }
        .onChange(of: viewModel.hasSetTenure) {
            viewModel.validateCurrentStep()
        }
    }

    private var headerSection: some View {
        let name = viewModel.partnerName.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = name.isEmpty ? "your partner" : name

        return OnboardingStepHeader(
            title: "How long have you and \(displayName) been together?",
            subtitle: "We'll use this to track your relationship milestones."
        )
        .padding(.top, 8)
    }
}

#Preview {
    let vm = OnboardingViewModel()
    vm.partnerName = "Sarah"
    vm.relationshipTenureMonths = 30
    vm.hasSetTenure = true
    return OnboardingTenureView().environment(vm)
}
