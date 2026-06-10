//
//  OnboardingHolidaysMilestonesView.swift
//  Knot
//
//  One screen combining two date-collection questions: pick US holidays to set
//  reminders for, and add custom milestones (first date, gotcha day, etc.).
//

import SwiftUI
import LucideIcons

struct OnboardingHolidaysMilestonesView: View {
    @Environment(OnboardingViewModel.self) private var viewModel

    @State private var showingCustomSheet = false
    @State private var customName = ""
    @State private var customMonth = 1
    @State private var customDay = 1
    @State private var customRecurrence = "yearly"

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

                customMilestonesSection
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .sheet(isPresented: $showingCustomSheet) {
            addCustomMilestoneSheet
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .onAppear {
            viewModel.validateCurrentStep()
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            OnboardingStepHeader(
                title: "Which dates should we remember?",
                subtitle: "Tap holidays to add reminders, and add any milestones unique to your relationship. You can change these later."
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

    private var customMilestonesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Custom milestones")
                .knotFont(Theme.Typography.cta)
                .foregroundStyle(Theme.textSecondary)

            if !viewModel.customMilestones.isEmpty {
                VStack(spacing: 8) {
                    ForEach(viewModel.customMilestones) { milestone in
                        customMilestoneRow(milestone)
                    }
                }
            }

            Button {
                resetCustomSheetState()
                showingCustomSheet = true
            } label: {
                Text("Add Custom Milestone")
                    .knotFont(Theme.Typography.cta)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .foregroundStyle(Theme.accent)
                    .background(Theme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Theme.accent.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
                    )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func customMilestoneRow(_ milestone: CustomMilestone) -> some View {
        HStack(spacing: 12) {
            Image(uiImage: Lucide.star)
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 18, height: 18)
                .foregroundStyle(Theme.accent)

            VStack(alignment: .leading, spacing: 2) {
                Text(milestone.name)
                    .knotFont(Theme.Typography.cta)

                HStack(spacing: 4) {
                    Text(formattedMilestoneDate(month: milestone.month, day: milestone.day))
                    Text("·")
                    Text(milestone.recurrence == "yearly" ? "Yearly" : "One-time")
                }
                .knotFont(Theme.Typography.label)
                .foregroundStyle(Theme.textTertiary)
            }

            Spacer()

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    viewModel.customMilestones.removeAll { $0.id == milestone.id }
                    viewModel.validateCurrentStep()
                }
            } label: {
                Image(uiImage: Lucide.x)
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 16, height: 16)
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .padding(14)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Theme.surfaceBorder, lineWidth: 1)
        )
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
    }

    private var addCustomMilestoneSheet: some View {
        NavigationStack {
            VStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Milestone Name")
                        .knotFont(Theme.Typography.cta)
                        .foregroundStyle(Theme.textSecondary)

                    KnotInput(
                        text: $customName,
                        placeholder: "e.g., First Date, Gotcha Day",
                        style: .singleLine
                    )
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Date")
                        .knotFont(Theme.Typography.cta)
                        .foregroundStyle(Theme.textSecondary)

                    HStack(spacing: 12) {
                        milestoneMonthPicker(
                            selection: Binding(
                                get: { customMonth },
                                set: { newMonth in
                                    customMonth = newMonth
                                    customDay = OnboardingViewModel.clampDay(
                                        customDay, toMonth: newMonth
                                    )
                                }
                            )
                        )

                        milestoneDayPicker(
                            selection: $customDay,
                            daysInMonth: OnboardingViewModel.daysInMonth(customMonth)
                        )
                    }
                    .padding(16)
                    .background(Theme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Theme.surfaceBorder, lineWidth: 1)
                    )
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Recurrence")
                        .knotFont(Theme.Typography.cta)
                        .foregroundStyle(Theme.textSecondary)

                    Picker("Recurrence", selection: $customRecurrence) {
                        Text("Yearly").tag("yearly")
                        Text("One-time").tag("one_time")
                    }
                    .pickerStyle(.segmented)
                }

                Spacer()
            }
            .padding(24)
            .background(Theme.backgroundGradient.ignoresSafeArea())
            .navigationTitle("Add Milestone")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showingCustomSheet = false
                    }
                    .foregroundStyle(Theme.textSecondary)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let trimmedName = customName.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmedName.isEmpty else { return }
                        let milestone = CustomMilestone(
                            name: trimmedName,
                            month: customMonth,
                            day: OnboardingViewModel.clampDay(customDay, toMonth: customMonth),
                            recurrence: customRecurrence
                        )
                        withAnimation(.easeInOut(duration: 0.2)) {
                            viewModel.customMilestones.append(milestone)
                        }
                        viewModel.validateCurrentStep()
                        showingCustomSheet = false
                    }
                    .knotFont(Theme.Typography.cta)
                    .foregroundStyle(Theme.accent)
                    .disabled(customName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func resetCustomSheetState() {
        customName = ""
        customMonth = 1
        customDay = 1
        customRecurrence = "yearly"
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
    OnboardingHolidaysMilestonesView().environment(OnboardingViewModel())
}
