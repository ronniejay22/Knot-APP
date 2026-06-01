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
    }

    private var headerSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "birthday.cake.fill")
                .font(.system(size: 36))
                .foregroundStyle(Theme.accent)

            let name = viewModel.partnerName.trimmingCharacters(in: .whitespacesAndNewlines)
            let displayName = name.isEmpty ? "your partner" : name

            Text("When is \(displayName)'s birthday?")
                .knotFont(Theme.Typography.onboardingHeader)
                .multilineTextAlignment(.center)

            Text("We'll remind you so you never forget.")
                .knotFont(Theme.Typography.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 8)
    }

    private var birthdaySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("Birthday")
                    .knotFont(Theme.Typography.cardTitle)

                KnotBadge("Required", variant: .accent, size: .sm)
            }

            HStack(spacing: 12) {
                milestoneMonthPicker(
                    selection: Binding(
                        get: { viewModel.partnerBirthdayMonth },
                        set: { newMonth in
                            viewModel.partnerBirthdayMonth = newMonth
                            viewModel.partnerBirthdayDay = OnboardingViewModel.clampDay(
                                viewModel.partnerBirthdayDay, toMonth: newMonth
                            )
                        }
                    )
                )

                milestoneDayPicker(
                    selection: Binding(
                        get: { viewModel.partnerBirthdayDay },
                        set: { viewModel.partnerBirthdayDay = $0 }
                    ),
                    daysInMonth: OnboardingViewModel.daysInMonth(viewModel.partnerBirthdayMonth)
                )
            }
            .padding(16)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Theme.surfaceBorder, lineWidth: 1)
            )

            Text(formattedMilestoneDate(month: viewModel.partnerBirthdayMonth, day: viewModel.partnerBirthdayDay))
                .knotFont(Theme.Typography.label)
                .foregroundStyle(Theme.textTertiary)
                .padding(.leading, 4)
        }
    }
}

#Preview {
    let vm = OnboardingViewModel()
    vm.partnerName = "Sarah"
    vm.partnerBirthdayMonth = 7
    vm.partnerBirthdayDay = 22
    return OnboardingBirthdayView().environment(vm)
}
