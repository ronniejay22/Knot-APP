//
//  OnboardingMilestonesView.swift
//  Knot
//
//  Created on February 7, 2026.
//  Step 3.1: Placeholder for onboarding Step 5 — Milestones.
//  Step 3.5: Full implementation — birthday (required), anniversary (optional),
//            holiday quick-add chips, and custom milestone sheet.
//

import SwiftUI
import LucideIcons

/// Step 5: Set up milestones — birthday (required), anniversary (optional),
/// holiday quick-add, and custom milestones.
///
/// The birthday section is always visible with month/day pickers (required).
/// The anniversary section has a toggle — when enabled, month/day pickers appear.
/// Holiday quick-add provides toggleable chips for US major holidays.
/// Custom milestones are added via a modal sheet with name, date, and recurrence.
///
/// Validation: Always passes (birthday has defaults; custom milestones must have
/// non-empty names if present). See `OnboardingViewModel.validateCurrentStep()`.
struct OnboardingMilestonesView: View {
    @Environment(OnboardingViewModel.self) private var viewModel

    /// Controls the presentation of the "Add Custom Milestone" sheet.
    @State private var showingCustomSheet = false

    /// Temporary state for the custom milestone being created in the sheet.
    @State private var customName = ""
    @State private var customMonth = 1
    @State private var customDay = 1
    @State private var customRecurrence = "yearly"

    /// Month names for the date pickers.
    private static let monthNames: [String] = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        return formatter.monthSymbols
    }()

    var body: some View {
        @Bindable var vm = viewModel

        ScrollView {
            VStack(spacing: 24) {
                // MARK: - Header
                headerSection

                // MARK: - Birthday (Required)
                birthdaySection

                // MARK: - Anniversary (Optional)
                anniversarySection

                // MARK: - Holiday Quick-Add
                holidaySection

                // MARK: - Custom Milestones
                customMilestonesSection

                // Bottom spacer for scroll comfort
                Spacer().frame(height: 24)
            }
            .padding(.horizontal, 24)
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

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 8) {
            Image(uiImage: Lucide.calendar)
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 36, height: 36)
                .foregroundStyle(Theme.accent)

            Text("Important Dates")
                .font(.title2.weight(.bold))

            let name = viewModel.partnerName.isEmpty ? "your partner" : viewModel.partnerName
            Text("When should we remind you about \(name)?")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
        }
        .padding(.top, 4)
        .padding(.bottom, 4)
    }

    // MARK: - Birthday Section (Required)

    private var birthdaySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section label
            HStack(spacing: 8) {
                Image(systemName: "birthday.cake.fill")
                    .font(.body)
                    .foregroundStyle(Theme.accent)

                Text("Birthday")
                    .font(.headline.weight(.semibold))

                Text("Required")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Theme.accent.opacity(0.15))
                    .clipShape(Capsule())
            }

            // Month + Day pickers
            HStack(spacing: 12) {
                monthPicker(
                    selection: Binding(
                        get: { viewModel.partnerBirthdayMonth },
                        set: { newMonth in
                            viewModel.partnerBirthdayMonth = newMonth
                            viewModel.partnerBirthdayDay = OnboardingViewModel.clampDay(
                                viewModel.partnerBirthdayDay, toMonth: newMonth
                            )
                        }
                    ),
                    label: "Month"
                )

                dayPicker(
                    selection: Binding(
                        get: { viewModel.partnerBirthdayDay },
                        set: { viewModel.partnerBirthdayDay = $0 }
                    ),
                    daysInMonth: OnboardingViewModel.daysInMonth(viewModel.partnerBirthdayMonth),
                    label: "Day"
                )
            }
            .padding(16)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Theme.surfaceBorder, lineWidth: 1)
            )

            Text(formattedDate(month: viewModel.partnerBirthdayMonth, day: viewModel.partnerBirthdayDay))
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
                .padding(.leading, 4)
        }
    }

    // MARK: - Anniversary Section (Optional)

    private var anniversarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Toggle header
            HStack(spacing: 8) {
                Image(uiImage: Lucide.heart)
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 18, height: 18)
                    .foregroundStyle(Theme.accent)

                Text("Anniversary")
                    .font(.headline.weight(.semibold))

                Spacer()

                Toggle("", isOn: Binding(
                    get: { viewModel.hasAnniversary },
                    set: { viewModel.hasAnniversary = $0 }
                ))
                .labelsHidden()
                .tint(Theme.accent)
            }

            if viewModel.hasAnniversary {
                // Month + Day pickers
                HStack(spacing: 12) {
                    monthPicker(
                        selection: Binding(
                            get: { viewModel.anniversaryMonth },
                            set: { newMonth in
                                viewModel.anniversaryMonth = newMonth
                                viewModel.anniversaryDay = OnboardingViewModel.clampDay(
                                    viewModel.anniversaryDay, toMonth: newMonth
                                )
                            }
                        ),
                        label: "Month"
                    )

                    dayPicker(
                        selection: Binding(
                            get: { viewModel.anniversaryDay },
                            set: { viewModel.anniversaryDay = $0 }
                        ),
                        daysInMonth: OnboardingViewModel.daysInMonth(viewModel.anniversaryMonth),
                        label: "Day"
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

                Text(formattedDate(month: viewModel.anniversaryMonth, day: viewModel.anniversaryDay))
                    .font(.caption)
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

    // MARK: - Holiday Quick-Add

    private var holidaySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(uiImage: Lucide.sparkles)
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 18, height: 18)
                    .foregroundStyle(Theme.accent)

                Text("Holidays")
                    .font(.headline.weight(.semibold))

                Spacer()

                if !viewModel.selectedHolidays.isEmpty {
                    Text("\(viewModel.selectedHolidays.count) selected")
                        .font(.caption)
                        .foregroundStyle(Theme.accent)
                }
            }

            Text("Tap to add reminders for these holidays.")
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)

            // Holiday chips in a vertical list for clean alignment
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
    }

    // MARK: - Custom Milestones

    private var customMilestonesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(uiImage: Lucide.plus)
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 18, height: 18)
                    .foregroundStyle(Theme.accent)

                Text("Custom Milestones")
                    .font(.headline.weight(.semibold))
            }

            Text("Add dates unique to your relationship.")
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)

            // Existing custom milestones
            if !viewModel.customMilestones.isEmpty {
                VStack(spacing: 8) {
                    ForEach(viewModel.customMilestones) { milestone in
                        customMilestoneRow(milestone)
                    }
                }
            }

            // Add Custom button
            Button {
                resetCustomSheetState()
                showingCustomSheet = true
            } label: {
                HStack(spacing: 8) {
                    Image(uiImage: Lucide.circlePlus)
                        .renderingMode(.template)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 20, height: 20)

                    Text("Add Custom Milestone")
                        .font(.subheadline.weight(.medium))
                }
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
    }

    // MARK: - Custom Milestone Row

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
                    .font(.subheadline.weight(.medium))

                HStack(spacing: 4) {
                    Text(formattedDate(month: milestone.month, day: milestone.day))
                    Text("·")
                    Text(milestone.recurrence == "yearly" ? "Yearly" : "One-time")
                }
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
            }

            Spacer()

            // Delete button
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

    // MARK: - Add Custom Milestone Sheet

    private var addCustomMilestoneSheet: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Name field
                VStack(alignment: .leading, spacing: 8) {
                    Text("Milestone Name")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.textSecondary)

                    TextField("e.g., First Date, Gotcha Day", text: $customName)
                        .font(.body)
                        .padding(14)
                        .background(Theme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Theme.surfaceBorder, lineWidth: 1)
                        )
                }

                // Date pickers
                VStack(alignment: .leading, spacing: 8) {
                    Text("Date")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.textSecondary)

                    HStack(spacing: 12) {
                        monthPicker(
                            selection: Binding(
                                get: { customMonth },
                                set: { newMonth in
                                    customMonth = newMonth
                                    customDay = OnboardingViewModel.clampDay(
                                        customDay, toMonth: newMonth
                                    )
                                }
                            ),
                            label: "Month"
                        )

                        dayPicker(
                            selection: $customDay,
                            daysInMonth: OnboardingViewModel.daysInMonth(customMonth),
                            label: "Day"
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

                // Recurrence picker
                VStack(alignment: .leading, spacing: 8) {
                    Text("Recurrence")
                        .font(.subheadline.weight(.medium))
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
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.accent)
                    .disabled(customName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    // MARK: - Reusable Picker Components

    /// A styled month picker (January through December).
    private func monthPicker(selection: Binding<Int>, label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)

            Picker(label, selection: selection) {
                ForEach(1...12, id: \.self) { month in
                    Text(Self.monthNames[month - 1]).tag(month)
                }
            }
            .pickerStyle(.menu)
            .tint(Theme.accent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// A styled day picker (1 through daysInMonth).
    private func dayPicker(selection: Binding<Int>, daysInMonth: Int, label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)

            Picker(label, selection: selection) {
                ForEach(1...daysInMonth, id: \.self) { day in
                    Text("\(day)").tag(day)
                }
            }
            .pickerStyle(.menu)
            .tint(Theme.accent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Helpers

    /// Formats a month/day pair as a human-readable string (e.g., "February 14").
    private func formattedDate(month: Int, day: Int) -> String {
        guard month >= 1, month <= 12 else { return "" }
        return "\(Self.monthNames[month - 1]) \(day)"
    }

    /// Resets the custom sheet fields to defaults.
    private func resetCustomSheetState() {
        customName = ""
        customMonth = 1
        customDay = 1
        customRecurrence = "yearly"
    }
}

// MARK: - Holiday Chip Component

/// A toggleable chip for a predefined holiday.
///
/// When selected, the chip shows a pink border and accent background;
/// when unselected, it shows a neutral surface background.
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
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(isSelected ? .white : Theme.textSecondary)

                    Text(formattedDate(month: holiday.month, day: holiday.day))
                        .font(.caption2)
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

    private func formattedDate(month: Int, day: Int) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        guard month >= 1, month <= 12 else { return "" }
        return "\(formatter.monthSymbols[month - 1]) \(day)"
    }
}

// MARK: - Previews

#Preview("Empty State") {
    OnboardingMilestonesView()
        .environment(OnboardingViewModel())
}

#Preview("With Partner Name") {
    let vm = OnboardingViewModel()
    vm.partnerName = "Sarah"
    return OnboardingMilestonesView()
        .environment(vm)
}

#Preview("With Data") {
    let vm = OnboardingViewModel()
    vm.partnerName = "Sarah"
    vm.partnerBirthdayMonth = 7
    vm.partnerBirthdayDay = 22
    vm.hasAnniversary = true
    vm.anniversaryMonth = 3
    vm.anniversaryDay = 14
    vm.selectedHolidays = ["valentines_day", "christmas"]
    vm.customMilestones = [
        CustomMilestone(name: "First Date", month: 9, day: 15, recurrence: "yearly"),
        CustomMilestone(name: "Trip to Paris", month: 6, day: 1, recurrence: "one_time"),
    ]
    return OnboardingMilestonesView()
        .environment(vm)
}
