//
//  OnboardingViewModel.swift
//  Knot
//
//  Created on February 7, 2026.
//  Step 3.1: Onboarding flow navigation — shared state across all 9 steps.
//

import Foundation

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

    var partnerBirthdayMonth: Int = 1
    var partnerBirthdayDay: Int = 1
    var hasAnniversary: Bool = false
    var anniversaryMonth: Int = 1
    var anniversaryDay: Int = 1
    var selectedHolidays: Set<String> = []

    // MARK: - Vibes (Step 3.6)

    var selectedVibes: Set<String> = []

    // MARK: - Budget (Step 3.7)

    var justBecauseMin: Int = 2000     // cents
    var justBecauseMax: Int = 5000     // cents
    var minorOccasionMin: Int = 5000   // cents
    var minorOccasionMax: Int = 15000  // cents
    var majorMilestoneMin: Int = 10000 // cents
    var majorMilestoneMax: Int = 50000 // cents

    // MARK: - Love Languages (Step 3.8)

    var primaryLoveLanguage: String = ""
    var secondaryLoveLanguage: String = ""

    // MARK: - Navigation Actions

    /// Advances to the next onboarding step.
    /// Does nothing if already on the last step.
    func goToNextStep() {
        guard let nextIndex = OnboardingStep(rawValue: currentStep.rawValue + 1) else { return }
        currentStep = nextIndex
        // Reset canProceed for the new step — each step view will set it appropriately
        canProceed = true
    }

    /// Returns to the previous onboarding step.
    /// Does nothing if already on the first step.
    func goToPreviousStep() {
        guard let prevIndex = OnboardingStep(rawValue: currentStep.rawValue - 1) else { return }
        currentStep = prevIndex
        // Re-entering a previous step should allow proceeding (data was already entered)
        canProceed = true
    }
}
