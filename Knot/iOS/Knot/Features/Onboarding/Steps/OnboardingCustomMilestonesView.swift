//
//  OnboardingCustomMilestonesView.swift
//  Knot
//
//  One-question screen: add custom milestones (first date, gotcha day, etc.).
//

import SwiftUI
import LucideIcons

struct OnboardingCustomMilestonesView: View {
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
        VStack(spacing: 8) {
            Image(uiImage: Lucide.star)
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 40, height: 40)
                .foregroundStyle(Theme.accent)

            Text("Any custom milestones?")
                .knotFont(Theme.Typography.cardTitle)
                .multilineTextAlignment(.center)

            Text("Add dates unique to your relationship — first date, gotcha day, anything you want to remember.")
                .knotFont(Theme.Typography.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 8)
    }

    private var customMilestonesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
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
                HStack(spacing: 8) {
                    Image(uiImage: Lucide.circlePlus)
                        .renderingMode(.template)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 20, height: 20)

                    Text("Add Custom Milestone")
                        .knotFont(Theme.Typography.cta)
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

#Preview {
    OnboardingCustomMilestonesView().environment(OnboardingViewModel())
}
