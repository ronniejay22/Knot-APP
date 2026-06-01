//
//  OnboardingTenureView.swift
//  Knot
//
//  One-question screen: how long the user and their partner have been together.
//

import SwiftUI
import LucideIcons

struct OnboardingTenureView: View {
    @Environment(OnboardingViewModel.self) private var viewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                headerSection

                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        yearsPicker
                            .frame(maxWidth: .infinity)
                        monthsPicker
                            .frame(maxWidth: .infinity)
                    }

                    Text(tenureSummary)
                        .knotFont(Theme.Typography.label)
                        .foregroundStyle(.tertiary)
                }
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
            Image(uiImage: Lucide.calendar)
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 40, height: 40)
                .foregroundStyle(Theme.accent)

            let name = viewModel.partnerName.trimmingCharacters(in: .whitespacesAndNewlines)
            let displayName = name.isEmpty ? "your partner" : name

            Text("How long have you and \(displayName) been together?")
                .knotFont(Theme.Typography.onboardingHeader)
                .multilineTextAlignment(.center)

            Text("We'll use this to track your relationship milestones.")
                .knotFont(Theme.Typography.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 8)
    }

    private var yearsPicker: some View {
        HStack(spacing: 6) {
            Spacer(minLength: 0)
            Picker("Years", selection: Binding(
                get: { viewModel.relationshipTenureMonths / 12 },
                set: { newYears in
                    let remainingMonths = viewModel.relationshipTenureMonths % 12
                    viewModel.relationshipTenureMonths = newYears * 12 + remainingMonths
                }
            )) {
                ForEach(0..<31, id: \.self) { year in
                    Text("\(year)").tag(year)
                }
            }
            .pickerStyle(.menu)
            .tint(Theme.accent)

            Text(viewModel.relationshipTenureMonths / 12 == 1 ? "year" : "years")
                .knotFont(Theme.Typography.body)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Theme.surfaceBorder, lineWidth: 0.5)
        )
    }

    private var monthsPicker: some View {
        HStack(spacing: 6) {
            Spacer(minLength: 0)
            Picker("Months", selection: Binding(
                get: { viewModel.relationshipTenureMonths % 12 },
                set: { newMonths in
                    let currentYears = viewModel.relationshipTenureMonths / 12
                    viewModel.relationshipTenureMonths = currentYears * 12 + newMonths
                }
            )) {
                ForEach(0..<12, id: \.self) { month in
                    Text("\(month)").tag(month)
                }
            }
            .pickerStyle(.menu)
            .tint(Theme.accent)

            Text(viewModel.relationshipTenureMonths % 12 == 1 ? "month" : "months")
                .knotFont(Theme.Typography.body)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Theme.surfaceBorder, lineWidth: 0.5)
        )
    }

    private var tenureSummary: String {
        let years = viewModel.relationshipTenureMonths / 12
        let months = viewModel.relationshipTenureMonths % 12
        let yearText = years == 1 ? "1 year" : "\(years) years"
        let monthText = months == 1 ? "1 month" : "\(months) months"
        return "\(yearText), \(monthText)"
    }
}

#Preview {
    let vm = OnboardingViewModel()
    vm.partnerName = "Sarah"
    vm.relationshipTenureMonths = 30
    return OnboardingTenureView().environment(vm)
}
