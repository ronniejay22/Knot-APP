//
//  OnboardingBirthdayView.swift
//  Knot
//
//  One-question screen: partner's birthday (required milestone).
//

import SwiftUI
import LucideIcons

struct OnboardingBirthdayView: View {
    @Environment(OnboardingViewModel.self) private var viewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                headerSection
                birthdaySection
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .onAppear {
            viewModel.validateCurrentStep()
        }
        .onChange(of: viewModel.hasSetBirthday) {
            viewModel.validateCurrentStep()
        }
    }

    private var headerSection: some View {
        let name = viewModel.partnerName.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = name.isEmpty ? "your partner" : name

        return OnboardingStepHeader(
            title: "When is \(displayName)'s birthday?",
            subtitle: "We'll remind you so you never forget."
        )
        .padding(.top, 8)
    }

    private var birthdaySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("Birthday")
                    .knotFont(Theme.Typography.cardTitle)

                KnotBadge("Required", variant: .accent, size: .sm)
            }

            MilestoneDateField(
                month: Binding(
                    get: { viewModel.partnerBirthdayMonth },
                    set: { viewModel.partnerBirthdayMonth = $0 }
                ),
                day: Binding(
                    get: { viewModel.partnerBirthdayDay },
                    set: { viewModel.partnerBirthdayDay = $0 }
                ),
                hasSelection: Binding(
                    get: { viewModel.hasSetBirthday },
                    set: { viewModel.hasSetBirthday = $0 }
                ),
                title: "Set Birthday"
            )
        }
    }
}

#Preview {
    let vm = OnboardingViewModel()
    vm.partnerName = "Sarah"
    vm.partnerBirthdayMonth = 7
    vm.partnerBirthdayDay = 22
    vm.hasSetBirthday = true
    return OnboardingBirthdayView().environment(vm)
}
