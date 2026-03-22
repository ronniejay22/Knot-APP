//
//  MilestonesManagementView.swift
//  Knot
//
//  Created on March 12, 2026.
//  Post-onboarding milestone management — add, edit, and delete milestones.
//

import SwiftUI
import LucideIcons

/// Full-screen view for managing partner milestones after onboarding.
/// Accessible from Settings → Milestones.
struct MilestonesManagementView: View {

    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = MilestonesViewModel()

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.backgroundGradient.ignoresSafeArea()

                if viewModel.isLoading && viewModel.milestones.isEmpty {
                    ProgressView()
                        .tint(Theme.accent)
                } else if viewModel.milestones.isEmpty {
                    emptyState
                } else {
                    milestoneList
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(uiImage: Lucide.arrowLeft)
                            .renderingMode(.template)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 20, height: 20)
                    }
                    .tint(Theme.textPrimary)
                }

                ToolbarItem(placement: .principal) {
                    Text("Milestones")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        viewModel.prepareAdd()
                    } label: {
                        Image(uiImage: Lucide.plus)
                            .renderingMode(.template)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 20, height: 20)
                    }
                    .tint(Theme.accent)
                }
            }
            .task {
                await viewModel.loadMilestones()
            }
            .sheet(isPresented: $viewModel.showAddSheet) {
                MilestoneFormSheet(viewModel: viewModel)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
            .alert("Delete Milestone", isPresented: $viewModel.showDeleteConfirmation) {
                Button("Cancel", role: .cancel) {
                    viewModel.milestoneToDelete = nil
                }
                Button("Delete", role: .destructive) {
                    Task { await viewModel.deleteMilestone() }
                }
            } message: {
                if let milestone = viewModel.milestoneToDelete {
                    Text("Are you sure you want to delete \"\(milestone.milestoneName)\"? Upcoming notifications for this milestone will also be removed.")
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 48))
                .foregroundStyle(Theme.textTertiary)

            Text("No Milestones")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)

            Text("Add important dates like birthdays, anniversaries, and holidays to get proactive recommendations.")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button {
                viewModel.prepareAdd()
            } label: {
                Text("Add Milestone")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Capsule().fill(Theme.accent))
            }
            .padding(.top, 8)
        }
    }

    // MARK: - Milestone List

    private var milestoneList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(viewModel.milestones) { milestone in
                    milestoneRow(milestone)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 80)
        }
        .refreshable {
            await viewModel.loadMilestones()
        }
    }

    // MARK: - Milestone Row

    private func milestoneRow(_ milestone: MilestoneItemResponse) -> some View {
        HStack(spacing: 14) {
            // Type icon
            Image(systemName: MilestonesViewModel.iconName(for: milestone.milestoneType))
                .font(.title3)
                .foregroundStyle(milestoneColor(milestone))
                .frame(width: 36, height: 36)
                .background(
                    Circle()
                        .fill(milestoneColor(milestone).opacity(0.15))
                )

            // Name + details
            VStack(alignment: .leading, spacing: 3) {
                Text(milestone.milestoneName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(formattedDate(milestone.milestoneDate))
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)

                    if milestone.recurrence == "yearly" {
                        Text("Yearly")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(Theme.textTertiary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule().fill(Theme.surface)
                            )
                    }
                }
            }

            Spacer()

            // Days until badge
            if let days = milestone.daysUntil {
                VStack(spacing: 2) {
                    Text("\(days)")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(daysColor(days))

                    Text(days == 1 ? "day" : "days")
                        .font(.caption2)
                        .foregroundStyle(Theme.textTertiary)
                }
                .frame(width: 44)
            }

            // Actions menu
            Menu {
                Button {
                    viewModel.prepareEdit(milestone)
                } label: {
                    Label("Edit", systemImage: "pencil")
                }

                Button(role: .destructive) {
                    viewModel.confirmDelete(milestone)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            } label: {
                Image(uiImage: Lucide.ellipsisVertical)
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 18, height: 18)
                    .foregroundStyle(Theme.textTertiary)
                    .padding(8)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Theme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Theme.surfaceBorder, lineWidth: 1)
                )
        )
    }

    // MARK: - Helpers

    private func milestoneColor(_ milestone: MilestoneItemResponse) -> Color {
        switch milestone.milestoneType {
        case "birthday": return .pink
        case "anniversary": return .red
        case "holiday": return .orange
        case "custom": return Theme.accent
        default: return Theme.accent
        }
    }

    private func daysColor(_ days: Int) -> Color {
        switch days {
        case 0...3: return .red
        case 4...7: return .orange
        case 8...14: return .yellow
        default: return Theme.textSecondary
        }
    }

    private func formattedDate(_ dateString: String) -> String {
        // Parse "2000-MM-DD" format and display as "Month Day"
        let components = dateString.split(separator: "-")
        guard components.count >= 3,
              let month = Int(components[1]),
              let day = Int(components[2]) else {
            return dateString
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM d"

        var dateComponents = DateComponents()
        dateComponents.month = month
        dateComponents.day = day
        dateComponents.year = 2000

        if let date = Calendar.current.date(from: dateComponents) {
            return formatter.string(from: date)
        }
        return dateString
    }
}

// MARK: - Milestone Form Sheet

/// Sheet for adding or editing a milestone.
struct MilestoneFormSheet: View {
    @Bindable var viewModel: MilestonesViewModel
    @Environment(\.dismiss) private var dismiss

    private let milestoneTypes = [
        ("birthday", "Birthday"),
        ("anniversary", "Anniversary"),
        ("holiday", "Holiday"),
        ("custom", "Custom"),
    ]

    private let budgetTiers = [
        ("just_because", "Just Because"),
        ("minor_occasion", "Minor Occasion"),
        ("major_milestone", "Major Milestone"),
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("e.g., Birthday, Valentine's Day", text: $viewModel.formName)
                }

                if viewModel.editingMilestone == nil {
                    Section("Type") {
                        Picker("Milestone Type", selection: $viewModel.formType) {
                            ForEach(milestoneTypes, id: \.0) { type in
                                Text(type.1).tag(type.0)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                }

                Section("Date") {
                    Picker("Month", selection: $viewModel.formMonth) {
                        ForEach(1...12, id: \.self) { month in
                            Text(DateFormatter().monthSymbols[month - 1]).tag(month)
                        }
                    }

                    Picker("Day", selection: $viewModel.formDay) {
                        ForEach(1...31, id: \.self) { day in
                            Text("\(day)").tag(day)
                        }
                    }
                }

                Section("Recurrence") {
                    Picker("Repeats", selection: $viewModel.formRecurrence) {
                        Text("Every Year").tag("yearly")
                        Text("One Time").tag("one_time")
                    }
                    .pickerStyle(.segmented)
                }

                Section("Budget Tier") {
                    Picker("Budget", selection: $viewModel.formBudgetTier) {
                        ForEach(budgetTiers, id: \.0) { tier in
                            Text(tier.1).tag(tier.0)
                        }
                    }
                }
            }
            .navigationTitle(viewModel.editingMilestone != nil ? "Edit Milestone" : "Add Milestone")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        Task {
                            await viewModel.saveMilestone()
                        }
                    }
                    .fontWeight(.semibold)
                    .disabled(!viewModel.isFormValid)
                }
            }
        }
    }
}
