//
//  EditVaultView.swift
//  Knot
//
//  Created on February 8, 2026.
//  Step 3.12: Edit Profile screen — loads existing vault data and allows
//  modifications to any section. Reuses onboarding step views.
//

import SwiftUI
import LucideIcons

/// "Edit Profile" screen that loads the user's existing vault data and
/// presents each section (basic info, interests, vibes, etc.) as editable
/// sub-screens via NavigationStack. Reuses the onboarding step views by
/// creating an `OnboardingViewModel` pre-populated with vault data.
///
/// Accessible from the HomeView until Settings is built in Step 11.1.
struct EditVaultView: View {
    @Environment(\.dismiss) private var dismiss

    /// The onboarding view model pre-populated with existing vault data.
    /// Created during loading and shared with all step views via `.environment()`.
    @State private var viewModel: OnboardingViewModel?

    /// Loading / error state
    @State private var isLoading = true
    @State private var loadError: String?

    /// Saving state
    @State private var isSaving = false
    @State private var saveError: String?
    @State private var showSaveError = false
    @State private var showSaveSuccess = false

    /// Tracks which section sheet to present
    @State private var activeSection: EditSection?

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.backgroundGradient.ignoresSafeArea()

                if isLoading {
                    loadingView
                } else if let error = loadError {
                    errorView(message: error)
                } else if let vm = viewModel {
                    editContentView(vm: vm)
                        .environment(vm)
                }
            }
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .tint(.white)
                }

                if viewModel != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            Task { await saveChanges() }
                        } label: {
                            if isSaving {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Text("Save")
                                    .fontWeight(.semibold)
                            }
                        }
                        .tint(Theme.accent)
                        .disabled(isSaving)
                    }
                }
            }
            .alert("Save Error", isPresented: $showSaveError) {
                Button("Try Again") {
                    Task { await saveChanges() }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text(saveError ?? "An unexpected error occurred.")
            }
            .alert("Profile Updated", isPresented: $showSaveSuccess) {
                Button("OK") {
                    dismiss()
                }
            } message: {
                Text("Your partner profile has been saved successfully.")
            }
            .sheet(item: $activeSection) { section in
                editSheet(for: section)
            }
        }
        .task {
            await loadVaultData()
        }
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.regular)
                .tint(Theme.accent)
            Text("Loading profile...")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Error View

    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(uiImage: Lucide.circleAlert)
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 40, height: 40)
                .foregroundStyle(.red)

            Text("Unable to Load Profile")
                .font(.headline)
                .foregroundStyle(.white)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Button("Try Again") {
                Task { await loadVaultData() }
            }
            .buttonStyle(.bordered)
            .tint(Theme.accent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Edit Content

    private func editContentView(vm: OnboardingViewModel) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                // Partner name header
                VStack(spacing: 4) {
                    Text(vm.partnerName.isEmpty ? "Partner" : vm.partnerName)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.white)
                    Text("Tap any section to edit")
                        .font(.caption)
                        .foregroundStyle(Theme.textTertiary)
                }
                .padding(.top, 8)

                // Sections
                editSectionButton(
                    icon: Lucide.user,
                    title: "Basic Info",
                    subtitle: basicInfoSubtitle(vm: vm),
                    section: .basicInfo
                )

                editSectionButton(
                    icon: Lucide.heart,
                    title: "Interests",
                    subtitle: "\(vm.selectedInterests.count) likes selected",
                    section: .interests
                )

                editSectionButton(
                    icon: Lucide.thumbsDown,
                    title: "Dislikes",
                    subtitle: "\(vm.selectedDislikes.count) dislikes selected",
                    section: .dislikes
                )

                editSectionButton(
                    icon: Lucide.calendar,
                    title: "Milestones",
                    subtitle: milestonesSubtitle(vm: vm),
                    section: .milestones
                )

                editSectionButton(
                    icon: Lucide.sparkles,
                    title: "Aesthetic Vibes",
                    subtitle: vm.selectedVibes.map { OnboardingVibesView.displayName(for: $0) }.joined(separator: ", "),
                    section: .vibes
                )

                editSectionButton(
                    icon: Lucide.wallet,
                    title: "Budget Tiers",
                    subtitle: budgetSubtitle(vm: vm),
                    section: .budget
                )

                editSectionButton(
                    icon: Lucide.heartHandshake,
                    title: "Love Languages",
                    subtitle: loveLanguagesSubtitle(vm: vm),
                    section: .loveLanguages
                )
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
    }

    // MARK: - Section Button

    private func editSectionButton(icon: UIImage, title: String, subtitle: String, section: EditSection) -> some View {
        Button {
            activeSection = section
        } label: {
            HStack(spacing: 14) {
                Image(uiImage: icon)
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 22, height: 22)
                    .foregroundStyle(Theme.accent)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }

                Spacer()

                Image(uiImage: Lucide.chevronRight)
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 16, height: 16)
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Theme.surfaceBorder, lineWidth: 1)
            )
        }
    }

    // MARK: - Sheet Content

    @ViewBuilder
    private func editSheet(for section: EditSection) -> some View {
        if let vm = viewModel {
            NavigationStack {
                Group {
                    switch section {
                    case .basicInfo:
                        OnboardingBasicInfoView()
                    case .interests:
                        OnboardingInterestsView()
                    case .dislikes:
                        OnboardingDislikesView()
                    case .milestones:
                        OnboardingMilestonesView()
                    case .vibes:
                        OnboardingVibesView()
                    case .budget:
                        OnboardingBudgetView()
                    case .loveLanguages:
                        OnboardingLoveLanguagesView()
                    }
                }
                .environment(vm)
                .background(Theme.backgroundGradient.ignoresSafeArea())
                .navigationTitle(section.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") {
                            activeSection = nil
                        }
                        .tint(Theme.accent)
                        .fontWeight(.semibold)
                    }
                }
            }
        }
    }

    // MARK: - Subtitle Helpers

    private func basicInfoSubtitle(vm: OnboardingViewModel) -> String {
        var parts: [String] = []
        if !vm.partnerName.isEmpty { parts.append(vm.partnerName) }
        let years = vm.relationshipTenureMonths / 12
        let months = vm.relationshipTenureMonths % 12
        if years > 0 { parts.append("\(years)y") }
        if months > 0 { parts.append("\(months)m") }
        return parts.joined(separator: " · ")
    }

    private func milestonesSubtitle(vm: OnboardingViewModel) -> String {
        var count = 1  // birthday always present
        if vm.hasAnniversary { count += 1 }
        count += vm.selectedHolidays.count
        count += vm.customMilestones.count
        return "\(count) milestone\(count == 1 ? "" : "s")"
    }

    private func budgetSubtitle(vm: OnboardingViewModel) -> String {
        let jbMin = vm.justBecauseMin / 100
        let jbMax = vm.justBecauseMax / 100
        let mmMin = vm.majorMilestoneMin / 100
        let mmMax = vm.majorMilestoneMax / 100
        return "$\(jbMin)–$\(jbMax) casual · $\(mmMin)–$\(mmMax) major"
    }

    private func loveLanguagesSubtitle(vm: OnboardingViewModel) -> String {
        let primary = OnboardingLoveLanguagesView.displayName(for: vm.primaryLoveLanguage)
        let secondary = OnboardingLoveLanguagesView.displayName(for: vm.secondaryLoveLanguage)
        return "\(primary) · \(secondary)"
    }

    // MARK: - Data Loading

    private func loadVaultData() async {
        isLoading = true
        loadError = nil

        let service = VaultService()
        do {
            let vault = try await service.getVault()
            let vm = OnboardingViewModel()

            // Populate basic info
            vm.partnerName = vault.partnerName
            vm.relationshipTenureMonths = vault.relationshipTenureMonths ?? 12
            vm.cohabitationStatus = vault.cohabitationStatus ?? "living_together"
            vm.locationCity = vault.locationCity ?? ""
            vm.locationState = vault.locationState ?? ""
            vm.locationCountry = vault.locationCountry ?? "US"

            // Populate interests and dislikes
            vm.selectedInterests = Set(vault.interests)
            vm.selectedDislikes = Set(vault.dislikes)

            // Populate milestones
            for milestone in vault.milestones {
                let (month, day) = parseMilestoneDate(milestone.milestoneDate)
                switch milestone.milestoneType {
                case "birthday":
                    vm.partnerBirthdayMonth = month
                    vm.partnerBirthdayDay = day
                    vm.birthdayMilestoneName = milestone.milestoneName
                case "anniversary":
                    vm.hasAnniversary = true
                    vm.anniversaryMonth = month
                    vm.anniversaryDay = day
                    vm.anniversaryMilestoneName = milestone.milestoneName
                case "holiday":
                    // Match to known holiday IDs
                    let matchedHoliday = HolidayOption.allHolidays.first { h in
                        h.month == month && h.day == day
                    }
                    if let match = matchedHoliday {
                        vm.selectedHolidays.insert(match.id)
                    }
                case "custom":
                    vm.customMilestones.append(CustomMilestone(
                        name: milestone.milestoneName,
                        month: month,
                        day: day,
                        recurrence: milestone.recurrence
                    ))
                default:
                    break
                }
            }

            // Populate vibes
            vm.selectedVibes = Set(vault.vibes)

            // Populate budgets
            for budget in vault.budgets {
                switch budget.occasionType {
                case "just_because":
                    vm.justBecauseMin = budget.minAmount
                    vm.justBecauseMax = budget.maxAmount
                    vm.justBecauseRanges = ["\(budget.minAmount)-\(budget.maxAmount)"]
                case "minor_occasion":
                    vm.minorOccasionMin = budget.minAmount
                    vm.minorOccasionMax = budget.maxAmount
                    vm.minorOccasionRanges = ["\(budget.minAmount)-\(budget.maxAmount)"]
                case "major_milestone":
                    vm.majorMilestoneMin = budget.minAmount
                    vm.majorMilestoneMax = budget.maxAmount
                    vm.majorMilestoneRanges = ["\(budget.minAmount)-\(budget.maxAmount)"]
                default:
                    break
                }
            }

            // Populate love languages
            for ll in vault.loveLanguages {
                if ll.priority == 1 { vm.primaryLoveLanguage = ll.language }
                if ll.priority == 2 { vm.secondaryLoveLanguage = ll.language }
            }

            viewModel = vm
            isLoading = false
        } catch {
            loadError = error.localizedDescription
            isLoading = false
        }
    }

    // MARK: - Save Changes

    private func saveChanges() async {
        guard let vm = viewModel else { return }
        isSaving = true

        let payload = vm.buildVaultPayload()
        let service = VaultService()

        do {
            let response = try await service.updateVault(payload)
            print("[Knot] Vault updated successfully: \(response.vaultId)")
            print("[Knot] Partner: \(response.partnerName)")
            isSaving = false
            showSaveSuccess = true
        } catch let error as VaultServiceError {
            isSaving = false
            saveError = error.errorDescription
            showSaveError = true
            print("[Knot] Vault update failed: \(error.errorDescription ?? "Unknown")")
        } catch {
            isSaving = false
            saveError = "An unexpected error occurred. Please try again."
            showSaveError = true
            print("[Knot] Vault update failed: \(error)")
        }
    }

    // MARK: - Helpers

    /// Parses a "2000-MM-DD" date string into (month, day) integers.
    private func parseMilestoneDate(_ dateStr: String) -> (Int, Int) {
        let parts = dateStr.split(separator: "-")
        guard parts.count >= 3,
              let month = Int(parts[1]),
              let day = Int(parts[2]) else {
            return (1, 1)
        }
        return (month, day)
    }
}

// MARK: - Edit Section Enum

/// Identifies which vault section to edit in the sheet.
enum EditSection: String, Identifiable {
    case basicInfo
    case interests
    case dislikes
    case milestones
    case vibes
    case budget
    case loveLanguages

    var id: String { rawValue }

    var title: String {
        switch self {
        case .basicInfo: return "Partner Info"
        case .interests: return "Interests"
        case .dislikes: return "Dislikes"
        case .milestones: return "Milestones"
        case .vibes: return "Aesthetic Vibes"
        case .budget: return "Budget"
        case .loveLanguages: return "Love Languages"
        }
    }
}

// MARK: - Previews

#Preview("Edit Vault") {
    EditVaultView()
}
