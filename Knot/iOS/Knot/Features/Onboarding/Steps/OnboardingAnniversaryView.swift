//
//  OnboardingAnniversaryView.swift
//  Knot
//
//  One-question screen: anniversary (optional, toggle-gated).
//

import SwiftUI
import LucideIcons

struct OnboardingAnniversaryView: View {
    @Environment(OnboardingViewModel.self) private var viewModel

    var body: some View {
        @Bindable var vm = viewModel

        ScrollView {
            VStack(spacing: 24) {
                headerSection
                anniversarySection
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
            Text("Do you celebrate an anniversary?")
                .knotFont(Theme.Typography.onboardingHeader)
                .multilineTextAlignment(.center)

            Text("Optional — flip the toggle if you want a reminder.")
                .knotFont(Theme.Typography.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 8)
    }

    private var anniversarySection: some View {
        @Bindable var vm = viewModel

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("Anniversary")
                    .knotFont(Theme.Typography.cardTitle)

                Spacer()

                Toggle("", isOn: $vm.hasAnniversary)
                    .labelsHidden()
                    .tint(Theme.accent)
            }

            if viewModel.hasAnniversary {
                HStack(spacing: 12) {
                    milestoneMonthPicker(
                        selection: Binding(
                            get: { viewModel.anniversaryMonth },
                            set: { newMonth in
                                viewModel.anniversaryMonth = newMonth
                                viewModel.anniversaryDay = OnboardingViewModel.clampDay(
                                    viewModel.anniversaryDay, toMonth: newMonth
                                )
                            }
                        )
                    )

                    milestoneDayPicker(
                        selection: Binding(
                            get: { viewModel.anniversaryDay },
                            set: { viewModel.anniversaryDay = $0 }
                        ),
                        daysInMonth: OnboardingViewModel.daysInMonth(viewModel.anniversaryMonth)
                    )
                }
                .padding(16)
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Theme.surfaceBorder, lineWidth: 1)
                )
                .transition(.opacity.combined(with: .move(edge: .top)))

                Text(formattedMilestoneDate(month: viewModel.anniversaryMonth, day: viewModel.anniversaryDay))
                    .knotFont(Theme.Typography.label)
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.leading, 4)
                    .transition(.opacity)
            }
        }
        .padding(16)
        .background(Theme.surface.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Theme.surfaceBorder, lineWidth: 1)
        )
        .animation(.easeInOut(duration: 0.25), value: viewModel.hasAnniversary)
    }
}

#Preview {
    OnboardingAnniversaryView().environment(OnboardingViewModel())
}
