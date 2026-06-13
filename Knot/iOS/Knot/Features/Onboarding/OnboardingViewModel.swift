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
/// for progress bar calculation and array indexing. The flow is split
/// into one question per screen — the four BasicInfo/Milestones/Budget/
/// LoveLanguages sections each expand into multiple consecutive steps.
enum OnboardingStep: Int, CaseIterable, Sendable {
    case welcome = 0
    case partnerName = 1
    case tenure = 2
    case cohabitation = 3
    case location = 4
    case interests = 5
    case dislikes = 6
    case birthday = 7
    case anniversary = 8
    case vibes = 9
    case loveLanguages = 10
    case completion = 11

    /// Human-readable title for the progress bar. Sibling questions
    /// share the same category title (e.g., all four partner-info
    /// screens show "Partner Info").
    var title: String {
        switch self {
        case .welcome: return "Welcome"
        case .partnerName, .tenure, .cohabitation, .location: return "Partner Info"
        case .interests: return "Interests"
        case .dislikes: return "Dislikes"
        case .birthday, .anniversary: return "Milestones"
        case .vibes: return "Aesthetic Vibes"
        case .loveLanguages: return "Love Languages"
        case .completion: return "Your Picks"
        }
    }

    /// The total number of onboarding steps.
    static var totalSteps: Int { allCases.count }

    /// Whether this is the very first step (the welcome screen).
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

    /// Creates the onboarding view model.
    ///
    /// - Parameter seedDefaultHolidays: When `true`, every predefined holiday is
    ///   pre-selected so the onboarding flow adds them all to the partner's
    ///   milestones (and thus the reminder queue) by default — there is no longer
    ///   a holidays step where the user picks them. The Settings edit flow uses
    ///   the default (`false`) and hydrates `selectedHolidays` from the backend
    ///   instead, so pre-seeding must not leak into editing.
    init(seedDefaultHolidays: Bool = false) {
        if seedDefaultHolidays {
            selectedHolidays = Set(HolidayOption.allHolidays.map { $0.id })
        }
    }

    // MARK: - Navigation State

    /// The currently displayed onboarding step.
    var currentStep: OnboardingStep = .welcome

    /// Normalized progress value (0.0 to 1.0) for the progress bar.
    /// Step 0 (welcome) = 0.0, step 8 (completion) = 1.0.
    var progress: Double {
        guard OnboardingStep.totalSteps > 1 else { return 1.0 }
        return Double(currentStep.rawValue) / Double(OnboardingStep.totalSteps - 1)
    }

    /// Whether the header back button should be shown for the current step.
    /// Hidden on the Welcome step (no header) and on the first post-Welcome
    /// step (Partner Name), where the only step to return to is the Welcome
    /// intro. Visible from the third step onward.
    var showsBackButton: Bool {
        currentStep.rawValue > OnboardingStep.partnerName.rawValue
    }

    /// Whether the onboarding header (back button + progress bar) should be shown
    /// for the current step. Hidden on the final recommendation-reveal step: the
    /// vault is already submitted by the time we land there, so there is nothing
    /// to navigate back to or re-edit, and the "Step 12 of 12" indicator no longer
    /// makes sense once the user is looking at their first recommendations.
    var showsProgressHeader: Bool {
        currentStep != .completion
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
        case .partnerName:
            return "Please enter your partner's name."
        case .location:
            return "Please enter your city and state."
        case .interests:
            let remaining = Constants.Validation.minInterests - selectedInterests.count
            return "Select \(remaining) more interest\(remaining == 1 ? "" : "s") to continue."
        case .dislikes:
            if !selectedDislikes.isDisjoint(with: selectedInterests) {
                return "A dislike can't also be a like. Please fix the overlap."
            }
            let remaining = Constants.Validation.minDislikes - selectedDislikes.count
            return "Select \(remaining) more dislike\(remaining == 1 ? "" : "s") to continue."
        case .vibes:
            return "Pick at least 1 vibe to continue."
        case .tenure:
            return "Please set how long you've been together."
        case .birthday:
            return "Please set your partner's birthday."
        case .anniversary:
            return "Set the anniversary date or turn off the toggle."
        case .loveLanguages:
            return primaryLoveLanguage.isEmpty
                ? "Choose your partner's primary love language."
                : "Choose a secondary love language (different from primary)."
        default:
            return nil
        }
    }

    // MARK: - Partner Basic Info (Step 3.2)

    var partnerName: String = ""
    var relationshipTenureMonths: Int = 12
    /// Whether the user has explicitly chosen a relationship length. The
    /// tenure above carries a default, but the tenure step won't let the user
    /// proceed until this flips true (via the stepper modal) so no length is
    /// silently saved.
    var hasSetTenure: Bool = false
    var cohabitationStatus: String = "living_together"
    var locationCity: String = ""
    var locationState: String = ""
    var locationCountry: String = "US"

    // MARK: - Interests & Dislikes (Steps 3.3, 3.4)

    var selectedInterests: Set<String> = []
    var selectedDislikes: Set<String> = []

    /// User-created interests that don't appear in `Constants.interestCategories`.
    /// Surfaced as additional cards on the interests onboarding screen so the
    /// user can deselect and re-select them. Persisted to the backend like any
    /// other interest (migration 00025 dropped the DB allowlist constraint).
    var customInterests: Set<String> = []

    /// User-created dislikes. Same treatment as `customInterests`.
    var customDislikes: Set<String> = []

    /// Maximum length of a custom interest/dislike name. Must match
    /// `MAX_INTEREST_NAME_LENGTH` in backend/app/models/vault.py.
    static let maxCustomInterestLength = 50

    /// Result of attempting to add a custom interest or dislike.
    enum CustomInterestAddResult: Equatable, Sendable {
        case added(String)
        case empty
        case tooLong
        case duplicate
        case overlapsLikes
    }

    /// Adds a user-typed name to the interests catalog and auto-selects it.
    /// Trims whitespace, enforces the length cap, and rejects case-insensitive
    /// duplicates against the predefined catalog, already-selected interests,
    /// and previously-added custom interests.
    @discardableResult
    func addCustomInterest(_ rawName: String) -> CustomInterestAddResult {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return .empty }
        guard name.count <= Self.maxCustomInterestLength else { return .tooLong }
        let lower = name.lowercased()
        let takenLikes = Constants.interestCategories.map { $0.lowercased() }
            + customInterests.map { $0.lowercased() }
            + selectedInterests.map { $0.lowercased() }
        if takenLikes.contains(lower) { return .duplicate }
        customInterests.insert(name)
        selectedInterests.insert(name)
        validateCurrentStep()
        return .added(name)
    }

    /// Adds a user-typed name to the dislikes catalog and auto-selects it.
    /// Same rules as `addCustomInterest`, plus: cannot match an interest the
    /// user has already chosen as a like (the two lists must stay disjoint).
    @discardableResult
    func addCustomDislike(_ rawName: String) -> CustomInterestAddResult {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return .empty }
        guard name.count <= Self.maxCustomInterestLength else { return .tooLong }
        let lower = name.lowercased()
        if selectedInterests.map({ $0.lowercased() }).contains(lower) {
            return .overlapsLikes
        }
        let takenDislikes = Constants.interestCategories.map { $0.lowercased() }
            + customDislikes.map { $0.lowercased() }
            + selectedDislikes.map { $0.lowercased() }
        // Predefined names that the user already chose as likes are excluded
        // from the dislikes catalog elsewhere, but a fresh custom name still
        // needs to be checked against the predefined list to prevent typing
        // e.g. "travel" as a new dislike when "Travel" is in the catalog.
        if takenDislikes.contains(lower) { return .duplicate }
        customDislikes.insert(name)
        selectedDislikes.insert(name)
        validateCurrentStep()
        return .added(name)
    }

    // MARK: - Milestones (Step 3.5)

    /// Birthday month (1–12). Required milestone.
    var partnerBirthdayMonth: Int = 1
    /// Birthday day (1–31). Required milestone.
    var partnerBirthdayDay: Int = 1
    /// Whether the user has explicitly chosen a birthday. The month/day above
    /// carry defaults, but the birthday step won't let the user proceed until
    /// this flips true (via the date modal) so no date is silently saved.
    var hasSetBirthday: Bool = false
    /// Whether the user has toggled the anniversary section on.
    var hasAnniversary: Bool = false
    /// Anniversary month (1–12). Only used when `hasAnniversary` is true.
    var anniversaryMonth: Int = 1
    /// Anniversary day (1–31). Only used when `hasAnniversary` is true.
    var anniversaryDay: Int = 1
    /// Whether the user has explicitly chosen an anniversary date. Only
    /// meaningful when `hasAnniversary` is true; gates proceeding the same way
    /// `hasSetBirthday` does for the birthday step.
    var hasSetAnniversary: Bool = false
    /// Set of holiday IDs the user has toggled on (e.g., "valentines_day", "christmas").
    var selectedHolidays: Set<String> = []
    /// User-created custom milestones (e.g., "First Date", "Gotcha Day").
    var customMilestones: [CustomMilestone] = []

    /// Original birthday milestone name from the backend (set during edit flow).
    /// When `nil` (initial onboarding), `buildVaultPayload()` auto-generates
    /// the name as "\(partnerName)'s Birthday". When set (edit flow), the
    /// original name is preserved so changing the partner name doesn't
    /// silently rename the milestone.
    var birthdayMilestoneName: String?

    /// Original anniversary milestone name from the backend (set during edit flow).
    /// When `nil` (initial onboarding), `buildVaultPayload()` uses "Anniversary".
    /// When set (edit flow), the original name is preserved.
    var anniversaryMilestoneName: String?

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
    var justBecauseMin: Int = 5000     // cents ($50)
    var justBecauseMax: Int = 15000    // cents ($150)
    var minorOccasionMin: Int = 12500  // cents ($125)
    var minorOccasionMax: Int = 37500  // cents ($375)
    var majorMilestoneMin: Int = 25000 // cents ($250)
    var majorMilestoneMax: Int = 75000 // cents ($750)

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
        // Use the stored name from the backend (edit flow) if available,
        // otherwise auto-generate from the partner name (onboarding flow).
        let birthdayName = birthdayMilestoneName
            ?? "\(partnerName.trimmingCharacters(in: .whitespacesAndNewlines))'s Birthday"
        milestones.append(MilestonePayload(
            milestoneType: "birthday",
            milestoneName: birthdayName,
            milestoneDate: formatMilestoneDate(month: partnerBirthdayMonth, day: partnerBirthdayDay),
            recurrence: "yearly",
            budgetTier: nil  // DB trigger sets major_milestone
        ))

        // Anniversary (optional)
        // Use the stored name from the backend (edit flow) if available,
        // otherwise default to "Anniversary" (onboarding flow).
        if hasAnniversary {
            let anniversaryName = anniversaryMilestoneName ?? "Anniversary"
            milestones.append(MilestonePayload(
                milestoneType: "anniversary",
                milestoneName: anniversaryName,
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
            locationCity: trimmedCity,
            locationState: trimmedState,
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
    /// Each one-question step validates only its own input. Steps without
    /// validation (welcome, completion, picker-defaulted screens, optional
    /// screens) default to `canProceed = true`.
    ///
    /// This method is called after every step transition. Individual step views may also
    /// call it via `.onChange` modifiers when the user modifies form data (see architecture
    /// note #24 for the view-based validation pattern).
    func validateCurrentStep() {
        switch currentStep {
        case .partnerName:
            canProceed = !partnerName
                .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .location:
            canProceed = !locationCity
                .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !locationState
                .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .interests:
            canProceed = selectedInterests.count >= Constants.Validation.minInterests
        case .dislikes:
            canProceed = selectedDislikes.count >= Constants.Validation.minDislikes
                && selectedDislikes.isDisjoint(with: selectedInterests)
        case .vibes:
            canProceed = selectedVibes.count >= Constants.Validation.minVibes
        case .tenure:
            canProceed = hasSetTenure
        case .birthday:
            canProceed = hasSetBirthday
        case .anniversary:
            canProceed = !hasAnniversary || hasSetAnniversary
        case .loveLanguages:
            canProceed = !primaryLoveLanguage.isEmpty
                && !secondaryLoveLanguage.isEmpty
                && secondaryLoveLanguage != primaryLoveLanguage
        default:
            // welcome, cohabitation, completion all proceed freely
            // (defaults or no validation needed).
            canProceed = true
        }
    }
}
