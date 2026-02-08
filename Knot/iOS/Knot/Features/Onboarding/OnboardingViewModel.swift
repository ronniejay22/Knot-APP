//
//  OnboardingViewModel.swift
//  Knot
//
//  Created on February 7, 2026.
//  Step 3.1: Onboarding flow navigation — shared state across all 9 steps.
//  Step 3.2: Added validation for Partner Basic Info (name required).
//  Step 3.3: Added validation for Interests (exactly 5 likes required).
//  Step 3.4: Added validation for Dislikes (exactly 5, no overlap with likes).
//  Step 3.5: Added CustomMilestone model, milestone validation (birthday required).
//  Step 3.6: Added vibes validation (min 1 selection required).
//          Added validationMessage for user-facing error feedback on Next tap.
//  Step 3.7: Added budget validation (max >= min for all three tiers).
//  Step 3.8: Added love languages validation (both primary and secondary required).
//

import Foundation

/// A user-created milestone (e.g., "First Date", "Gotcha Day").
///
/// Used by the milestones onboarding step (Step 3.5) to hold custom
/// milestones that don't fit the predefined birthday/anniversary/holiday slots.
struct CustomMilestone: Identifiable, Sendable {
    let id = UUID()
    var name: String
    var month: Int
    var day: Int
    var recurrence: String  // "yearly" or "one_time"
}

/// Predefined US holidays available for quick-add during onboarding.
///
/// Each holiday has a display name, a stable identifier for storage,
/// and a fixed month/day (or computed date for floating holidays).
struct HolidayOption: Identifiable, Sendable {
    let id: String          // stable key, e.g. "valentines_day"
    let displayName: String
    let month: Int
    let day: Int
    let iconName: String    // SF Symbol name

    /// The predefined US major holidays available during onboarding.
    static let allHolidays: [HolidayOption] = [
        HolidayOption(id: "valentines_day", displayName: "Valentine's Day", month: 2, day: 14, iconName: "heart.fill"),
        HolidayOption(id: "mothers_day", displayName: "Mother's Day", month: 5, day: 11, iconName: "figure.and.child.holdinghands"),
        HolidayOption(id: "fathers_day", displayName: "Father's Day", month: 6, day: 15, iconName: "figure.and.child.holdinghands"),
        HolidayOption(id: "christmas", displayName: "Christmas", month: 12, day: 25, iconName: "gift.fill"),
        HolidayOption(id: "new_years_eve", displayName: "New Year's Eve", month: 12, day: 31, iconName: "party.popper.fill"),
    ]
}

/// Defines the ordered steps in the onboarding flow.
///
/// The raw value provides the zero-based index of each step, used
/// for progress bar calculation and array indexing.
enum OnboardingStep: Int, CaseIterable, Sendable {
    case welcome = 0
    case basicInfo = 1
    case interests = 2
    case dislikes = 3
    case milestones = 4
    case vibes = 5
    case budget = 6
    case loveLanguages = 7
    case completion = 8

    /// Human-readable title for the navigation bar.
    var title: String {
        switch self {
        case .welcome: return "Welcome"
        case .basicInfo: return "Partner Info"
        case .interests: return "Interests"
        case .dislikes: return "Dislikes"
        case .milestones: return "Milestones"
        case .vibes: return "Aesthetic Vibes"
        case .budget: return "Budget"
        case .loveLanguages: return "Love Languages"
        case .completion: return "All Set!"
        }
    }

    /// The total number of onboarding steps.
    static var totalSteps: Int { allCases.count }

    /// Whether this is the very first step (no "Back" button).
    var isFirst: Bool { self == .welcome }

    /// Whether this is the very last step (no "Next" button — shows "Get Started" instead).
    var isLast: Bool { self == .completion }
}

/// Manages all onboarding state across the 9-step flow.
///
/// Created in `OnboardingContainerView` and injected into the SwiftUI environment
/// so all step views share the same data. Data entered in each step persists when
/// navigating back and forth — the view model is never recreated during the flow.
///
/// Steps 3.2–3.8 will add actual data properties (partner name, interests, etc.)
/// to this class. Step 3.1 only establishes the navigation infrastructure.
@Observable
@MainActor
final class OnboardingViewModel {

    // MARK: - Navigation State

    /// The currently displayed onboarding step.
    var currentStep: OnboardingStep = .welcome

    /// Normalized progress value (0.0 to 1.0) for the progress bar.
    /// Step 0 (welcome) = 0.0, step 8 (completion) = 1.0.
    var progress: Double {
        guard OnboardingStep.totalSteps > 1 else { return 1.0 }
        return Double(currentStep.rawValue) / Double(OnboardingStep.totalSteps - 1)
    }

    /// Whether the "Next" button should be enabled.
    /// Each step view can override this by setting `canProceed`.
    /// The welcome and completion steps always allow proceeding.
    var canProceed: Bool = true

    /// User-facing error message shown when the user taps Next while `canProceed` is false.
    /// Returns `nil` when the current step is valid. Used by `OnboardingContainerView`
    /// to display a brief error banner.
    var validationMessage: String? {
        guard !canProceed else { return nil }
        switch currentStep {
        case .basicInfo:
            return "Please enter your partner's name."
        case .interests:
            let remaining = Constants.Validation.requiredInterests - selectedInterests.count
            return "Select \(remaining) more interest\(remaining == 1 ? "" : "s") to continue."
        case .dislikes:
            if !selectedDislikes.isDisjoint(with: selectedInterests) {
                return "A dislike can't also be a like. Please fix the overlap."
            }
            let remaining = Constants.Validation.requiredDislikes - selectedDislikes.count
            return "Select \(remaining) more dislike\(remaining == 1 ? "" : "s") to continue."
        case .vibes:
            return "Pick at least 1 vibe to continue."
        case .milestones:
            return "Custom milestone names can't be empty."
        case .budget:
            return "Maximum budget must be at least the minimum for each tier."
        case .loveLanguages:
            if primaryLoveLanguage.isEmpty {
                return "Choose your partner's primary love language."
            }
            return "Now choose a secondary love language."
        default:
            return nil
        }
    }

    // MARK: - Partner Basic Info (Step 3.2)

    var partnerName: String = ""
    var relationshipTenureMonths: Int = 12
    var cohabitationStatus: String = "living_together"
    var locationCity: String = ""
    var locationState: String = ""
    var locationCountry: String = "US"

    // MARK: - Interests & Dislikes (Steps 3.3, 3.4)

    var selectedInterests: Set<String> = []
    var selectedDislikes: Set<String> = []

    // MARK: - Milestones (Step 3.5)

    /// Birthday month (1–12). Required milestone.
    var partnerBirthdayMonth: Int = 1
    /// Birthday day (1–31). Required milestone.
    var partnerBirthdayDay: Int = 1
    /// Whether the user has toggled the anniversary section on.
    var hasAnniversary: Bool = false
    /// Anniversary month (1–12). Only used when `hasAnniversary` is true.
    var anniversaryMonth: Int = 1
    /// Anniversary day (1–31). Only used when `hasAnniversary` is true.
    var anniversaryDay: Int = 1
    /// Set of holiday IDs the user has toggled on (e.g., "valentines_day", "christmas").
    var selectedHolidays: Set<String> = []
    /// User-created custom milestones (e.g., "First Date", "Gotcha Day").
    var customMilestones: [CustomMilestone] = []

    /// Returns the valid day range for a given month (accounts for month length).
    /// Does not account for leap years — uses a fixed 28 days for February
    /// since milestones store month+day only (year is computed dynamically).
    static func daysInMonth(_ month: Int) -> Int {
        switch month {
        case 1, 3, 5, 7, 8, 10, 12: return 31
        case 4, 6, 9, 11: return 30
        case 2: return 29
        default: return 31
        }
    }

    /// Clamp a day value to the valid range for the given month.
    static func clampDay(_ day: Int, toMonth month: Int) -> Int {
        min(day, daysInMonth(month))
    }

    // MARK: - Vibes (Step 3.6)

    var selectedVibes: Set<String> = []

    // MARK: - Budget (Step 3.7)

    /// Effective budget bounds (computed from selected ranges).
    /// These are what get submitted to the backend.
    var justBecauseMin: Int = 2000     // cents
    var justBecauseMax: Int = 5000     // cents
    var minorOccasionMin: Int = 5000   // cents
    var minorOccasionMax: Int = 15000  // cents
    var majorMilestoneMin: Int = 10000 // cents
    var majorMilestoneMax: Int = 50000 // cents

    /// Selected budget range IDs per tier (e.g., "2000-5000").
    /// The budget view supports multi-select — the effective min/max
    /// above are computed as min(selected mins) / max(selected maxes).
    /// Stored here so selections persist when navigating between steps.
    var justBecauseRanges: Set<String> = ["2000-5000"]
    var minorOccasionRanges: Set<String> = ["5000-15000"]
    var majorMilestoneRanges: Set<String> = ["10000-50000"]

    // MARK: - Love Languages (Step 3.8)

    var primaryLoveLanguage: String = ""
    var secondaryLoveLanguage: String = ""

    // MARK: - Vault Submission State (Step 3.11)

    /// Whether the vault is currently being submitted to the backend.
    var isSubmitting = false

    /// Error message from vault submission, shown in an alert.
    var submissionError: String?

    /// Controls the visibility of the submission error alert.
    var showSubmissionError = false

    // MARK: - Navigation Actions

    /// Advances to the next onboarding step.
    /// Does nothing if already on the last step.
    func goToNextStep() {
        guard let nextIndex = OnboardingStep(rawValue: currentStep.rawValue + 1) else { return }
        currentStep = nextIndex
        validateCurrentStep()
    }

    /// Returns to the previous onboarding step.
    /// Does nothing if already on the first step.
    func goToPreviousStep() {
        guard let prevIndex = OnboardingStep(rawValue: currentStep.rawValue - 1) else { return }
        currentStep = prevIndex
        validateCurrentStep()
    }

    // MARK: - Validation

    // MARK: - Vault Submission (Step 3.11)

    /// Submits the vault to the backend API.
    ///
    /// Builds a `VaultCreatePayload` from all collected onboarding data, sends it
    /// to `POST /api/v1/vault`, and returns whether the submission succeeded.
    ///
    /// On success: returns `true`. The caller (container view) navigates to Home.
    /// On failure: sets `submissionError` and `showSubmissionError`, returns `false`.
    /// The user can dismiss the alert and retry.
    ///
    /// - Returns: `true` if the vault was created successfully, `false` otherwise.
    func submitVault() async -> Bool {
        isSubmitting = true
        defer { isSubmitting = false }

        let payload = buildVaultPayload()
        let service = VaultService()

        do {
            let response = try await service.createVault(payload)
            print("[Knot] Vault created successfully: \(response.vaultId)")
            print("[Knot] Partner: \(response.partnerName)")
            print("[Knot] Interests: \(response.interestsCount), Dislikes: \(response.dislikesCount)")
            print("[Knot] Milestones: \(response.milestonesCount), Vibes: \(response.vibesCount)")
            return true
        } catch let error as VaultServiceError {
            submissionError = error.errorDescription
            showSubmissionError = true
            print("[Knot] Vault submission failed: \(error.errorDescription ?? "Unknown error")")
            return false
        } catch {
            submissionError = "An unexpected error occurred. Please try again."
            showSubmissionError = true
            print("[Knot] Vault submission failed: \(error)")
            return false
        }
    }

    /// Builds the vault creation payload from all collected onboarding data.
    ///
    /// Serializes partner info, interests, dislikes, milestones, vibes,
    /// budgets, and love languages into a `VaultCreatePayload` matching
    /// the backend's `POST /api/v1/vault` schema.
    func buildVaultPayload() -> VaultCreatePayload {
        // --- Milestones ---
        var milestones: [MilestonePayload] = []

        // Birthday (always present — required milestone)
        milestones.append(MilestonePayload(
            milestoneType: "birthday",
            milestoneName: "\(partnerName.trimmingCharacters(in: .whitespacesAndNewlines))'s Birthday",
            milestoneDate: formatMilestoneDate(month: partnerBirthdayMonth, day: partnerBirthdayDay),
            recurrence: "yearly",
            budgetTier: nil  // DB trigger sets major_milestone
        ))

        // Anniversary (optional)
        if hasAnniversary {
            milestones.append(MilestonePayload(
                milestoneType: "anniversary",
                milestoneName: "Anniversary",
                milestoneDate: formatMilestoneDate(month: anniversaryMonth, day: anniversaryDay),
                recurrence: "yearly",
                budgetTier: nil  // DB trigger sets major_milestone
            ))
        }

        // Holidays
        for holidayID in selectedHolidays {
            if let holiday = HolidayOption.allHolidays.first(where: { $0.id == holidayID }) {
                milestones.append(MilestonePayload(
                    milestoneType: "holiday",
                    milestoneName: holiday.displayName,
                    milestoneDate: formatMilestoneDate(month: holiday.month, day: holiday.day),
                    recurrence: "yearly",
                    budgetTier: nil  // DB trigger sets based on holiday type
                ))
            }
        }

        // Custom milestones
        for custom in customMilestones {
            milestones.append(MilestonePayload(
                milestoneType: "custom",
                milestoneName: custom.name.trimmingCharacters(in: .whitespacesAndNewlines),
                milestoneDate: formatMilestoneDate(month: custom.month, day: custom.day),
                recurrence: custom.recurrence,
                budgetTier: "minor_occasion"  // Default for custom milestones
            ))
        }

        // --- Budgets ---
        let budgets = [
            BudgetPayload(
                occasionType: "just_because",
                minAmount: justBecauseMin,
                maxAmount: justBecauseMax,
                currency: "USD"
            ),
            BudgetPayload(
                occasionType: "minor_occasion",
                minAmount: minorOccasionMin,
                maxAmount: minorOccasionMax,
                currency: "USD"
            ),
            BudgetPayload(
                occasionType: "major_milestone",
                minAmount: majorMilestoneMin,
                maxAmount: majorMilestoneMax,
                currency: "USD"
            ),
        ]

        // --- Build payload ---
        let trimmedName = partnerName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCity = locationCity.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedState = locationState.trimmingCharacters(in: .whitespacesAndNewlines)

        return VaultCreatePayload(
            partnerName: trimmedName,
            relationshipTenureMonths: relationshipTenureMonths,
            cohabitationStatus: cohabitationStatus,
            locationCity: trimmedCity.isEmpty ? nil : trimmedCity,
            locationState: trimmedState.isEmpty ? nil : trimmedState,
            locationCountry: locationCountry,
            interests: Array(selectedInterests),
            dislikes: Array(selectedDislikes),
            milestones: milestones,
            vibes: Array(selectedVibes),
            budgets: budgets,
            loveLanguages: LoveLanguagesPayload(
                primary: primaryLoveLanguage,
                secondary: secondaryLoveLanguage
            )
        )
    }

    /// Formats a month/day pair as an ISO date string with year 2000 placeholder.
    ///
    /// Milestones store month+day only. The year 2000 is used as a placeholder
    /// for yearly recurring milestones; the actual year is computed dynamically
    /// when calculating next occurrences for notifications.
    private func formatMilestoneDate(month: Int, day: Int) -> String {
        String(format: "2000-%02d-%02d", month, day)
    }

    // MARK: - Validation

    /// Validates whether the user can proceed from the current step.
    ///
    /// Steps without validation (welcome, completion, and unimplemented placeholders)
    /// default to `canProceed = true`. Steps with validation rules update `canProceed`
    /// based on their specific requirements.
    ///
    /// This method is called after every step transition. Individual step views may also
    /// call it via `.onChange` modifiers when the user modifies form data (see architecture
    /// note #24 for the view-based validation pattern).
    func validateCurrentStep() {
        switch currentStep {
        case .basicInfo:
            canProceed = !partnerName
                .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .interests:
            canProceed = selectedInterests.count == Constants.Validation.requiredInterests
        case .dislikes:
            canProceed = selectedDislikes.count == Constants.Validation.requiredDislikes
                && selectedDislikes.isDisjoint(with: selectedInterests)
        case .milestones:
            // Birthday is always valid (month+day have defaults).
            // Custom milestones must have non-empty names if they exist.
            let customsValid = customMilestones.allSatisfy {
                !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            canProceed = customsValid
        case .vibes:
            canProceed = selectedVibes.count >= Constants.Validation.minVibes
        case .budget:
            // Auto-correction in the budget view's Binding setters ensures max >= min,
            // so this should always pass. Included as a safety net for programmatic changes.
            canProceed = justBecauseMax >= justBecauseMin
                && minorOccasionMax >= minorOccasionMin
                && majorMilestoneMax >= majorMilestoneMin
        case .loveLanguages:
            canProceed = !primaryLoveLanguage.isEmpty && !secondaryLoveLanguage.isEmpty
        default:
            // Placeholder steps and steps without validation allow proceeding.
            canProceed = true
        }
    }
}
