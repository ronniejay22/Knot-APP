//
//  MilestonesViewModel.swift
//  Knot
//
//  Created on March 12, 2026.
//  State management for the milestone management screen.
//

import Foundation

@MainActor
@Observable
final class MilestonesViewModel {

    // MARK: - State

    var milestones: [MilestoneItemResponse] = []
    var isLoading = false
    var errorMessage: String?

    // MARK: - Add/Edit Sheet State

    var showAddSheet = false
    var editingMilestone: MilestoneItemResponse?

    // Add form fields
    var formName = ""
    var formType: String = "custom"
    var formMonth = 1
    var formDay = 1
    var formRecurrence: String = "yearly"
    var formBudgetTier: String = "just_because"

    // MARK: - Delete Confirmation

    var milestoneToDelete: MilestoneItemResponse?
    var showDeleteConfirmation = false

    // MARK: - Dependencies

    private let service: MilestoneService

    init(service: MilestoneService = MilestoneService()) {
        self.service = service
    }

    // MARK: - Load

    func loadMilestones() async {
        isLoading = true
        errorMessage = nil

        do {
            let response = try await service.listMilestones()
            milestones = response.milestones
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    // MARK: - Add

    func prepareAdd() {
        editingMilestone = nil
        formName = ""
        formType = "custom"
        formMonth = 1
        formDay = 1
        formRecurrence = "yearly"
        formBudgetTier = "just_because"
        showAddSheet = true
    }

    func prepareEdit(_ milestone: MilestoneItemResponse) {
        editingMilestone = milestone
        formName = milestone.milestoneName
        formType = milestone.milestoneType
        formRecurrence = milestone.recurrence
        formBudgetTier = milestone.budgetTier ?? "just_because"

        // Parse month/day from milestone_date (format: "2000-MM-DD" or "YYYY-MM-DD")
        let components = milestone.milestoneDate.split(separator: "-")
        if components.count >= 3 {
            formMonth = Int(components[1]) ?? 1
            formDay = Int(components[2]) ?? 1
        }

        showAddSheet = true
    }

    func saveMilestone() async {
        let dateString = String(format: "2000-%02d-%02d", formMonth, formDay)

        if let editing = editingMilestone {
            // Update existing
            let payload = MilestoneUpdatePayload(
                milestoneName: formName,
                milestoneDate: dateString,
                recurrence: formRecurrence,
                budgetTier: formBudgetTier
            )

            do {
                _ = try await service.updateMilestone(id: editing.id, payload)
                showAddSheet = false
                await loadMilestones()
            } catch {
                errorMessage = error.localizedDescription
            }
        } else {
            // Create new
            let payload = MilestoneCreatePayload(
                milestoneType: formType,
                milestoneName: formName,
                milestoneDate: dateString,
                recurrence: formRecurrence,
                budgetTier: formBudgetTier
            )

            do {
                _ = try await service.createMilestone(payload)
                showAddSheet = false
                await loadMilestones()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Delete

    func confirmDelete(_ milestone: MilestoneItemResponse) {
        milestoneToDelete = milestone
        showDeleteConfirmation = true
    }

    func deleteMilestone() async {
        guard let milestone = milestoneToDelete else { return }

        do {
            try await service.deleteMilestone(id: milestone.id)
            milestones.removeAll { $0.id == milestone.id }
            milestoneToDelete = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Helpers

    var isFormValid: Bool {
        !formName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Icon name for a milestone type.
    static func iconName(for type: String) -> String {
        switch type {
        case "birthday": return "birthday.cake.fill"
        case "anniversary": return "heart.fill"
        case "holiday": return "star.fill"
        case "custom": return "calendar"
        default: return "calendar"
        }
    }

    /// Days until text for display.
    static func daysUntilText(_ daysUntil: Int?) -> String {
        guard let days = daysUntil else { return "" }
        switch days {
        case 0: return "Today!"
        case 1: return "Tomorrow"
        default: return "in \(days) days"
        }
    }

    /// Budget tier display name.
    static func budgetTierLabel(_ tier: String?) -> String {
        switch tier {
        case "just_because": return "Just Because"
        case "minor_occasion": return "Minor Occasion"
        case "major_milestone": return "Major Milestone"
        default: return "—"
        }
    }
}
