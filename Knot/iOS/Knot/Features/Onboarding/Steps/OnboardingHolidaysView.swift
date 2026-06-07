//
//  OnboardingHolidaysView.swift
//  Knot
//
//  One-question screen: pick US holidays to set reminders for.
//

import SwiftUI
import LucideIcons

struct OnboardingHolidaysView: View {
    @Environment(OnboardingViewModel.self) private var viewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                headerSection

                VStack(spacing: 8) {
                    ForEach(HolidayOption.allHolidays) { holiday in
                        HolidayChip(
                            holiday: holiday,
                            isSelected: viewModel.selectedHolidays.contains(holiday.id),
                            onToggle: {
                                if viewModel.selectedHolidays.contains(holiday.id) {
                                    viewModel.selectedHolidays.remove(holiday.id)
                                } else {
                                    viewModel.selectedHolidays.insert(holiday.id)
                                }
                            }
                        )
                    }
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
        VStack(alignment: .leading, spacing: 8) {
            OnboardingStepHeader(
                title: "Which holidays should we remind you about?",
                subtitle: "Tap to add reminders. You can change these later."
            )

            if !viewModel.selectedHolidays.isEmpty {
                Text("\(viewModel.selectedHolidays.count) selected")
                    .knotFont(Theme.Typography.label)
                    .foregroundStyle(Theme.accent)
                    .padding(.top, 2)
            }
        }
        .padding(.top, 8)
    }
}

// MARK: - Holiday Chip Component

private struct HolidayChip: View {
    let holiday: HolidayOption
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 10) {
                Image(systemName: holiday.iconName)
                    .font(.body)
                    .foregroundStyle(isSelected ? Theme.accent : Theme.textSecondary)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 1) {
                    Text(holiday.displayName)
                        .knotFont(Theme.Typography.cta)
                        .foregroundStyle(isSelected ? Theme.textPrimary : Theme.textSecondary)

                    Text(formattedMilestoneDate(month: holiday.month, day: holiday.day))
                        .knotFont(Theme.Typography.label)
                        .foregroundStyle(isSelected ? Theme.textSecondary : Theme.textTertiary)
                }

                Spacer()

                Image(uiImage: isSelected ? Lucide.circleCheck : Lucide.circle)
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 20, height: 20)
                    .foregroundStyle(isSelected ? Theme.accent : Theme.textTertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(isSelected ? Theme.accent.opacity(0.12) : Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Theme.accent.opacity(0.5) : Theme.surfaceBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }
}

#Preview {
    OnboardingHolidaysView().environment(OnboardingViewModel())
}
