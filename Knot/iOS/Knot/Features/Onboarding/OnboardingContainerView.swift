//
//  OnboardingContainerView.swift
//  Knot
//
//  Created on February 7, 2026.
//  Step 3.1: Multi-step onboarding navigation container.
//  Step 3.6: Added validation error banner when tapping Next before step is valid.
//  Step 3.11: Connected "Get Started" to vault submission API with loading overlay.
//

import SwiftUI
import LucideIcons

/// The root container for the onboarding flow. Manages step transitions,
/// a progress bar, and the forward navigation button.
///
/// Creates and owns the `OnboardingViewModel`, injecting it into the SwiftUI
/// environment so all child step views share the same state.
///
/// The container displays:
/// - A progress bar at the top (animated)
/// - The current step's view in the center
/// - A full-width Next / Get Started button at the bottom
///
/// The `onComplete` closure is called when the user taps "Get Started" on the
/// completion step, signaling `ContentView` to transition to the Home screen.
struct OnboardingContainerView: View {
    /// Called when the user finishes onboarding (taps "Get Started" on the last step).
    var onComplete: () -> Void

    @State private var viewModel = OnboardingViewModel()
    @State private var showValidationError = false
    @State private var validationErrorText = ""
    @State private var dismissTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            // MARK: - Progress Bar
            progressBar
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .padding(.bottom, 8)

            // MARK: - Step Content
            stepContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
                .id(viewModel.currentStep)

            // MARK: - Validation Error Banner
            if showValidationError {
                Text(validationErrorText)
                    .knotFont(Theme.Typography.cta)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Color.red.opacity(0.85))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal, 24)
                    .padding(.bottom, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // MARK: - Navigation Buttons
            navigationButtons
                .padding(.horizontal, 24)
        }
        .background(Theme.backgroundGradient.ignoresSafeArea())
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .environment(viewModel)
        .animation(.easeInOut(duration: 0.3), value: viewModel.currentStep)
        .animation(.easeInOut(duration: 0.25), value: showValidationError)
        .onChange(of: viewModel.currentStep) { _, _ in
            // Dismiss any lingering error and cancel pending dismiss when switching steps
            dismissTask?.cancel()
            dismissTask = nil
            showValidationError = false
        }
        // MARK: - Vault Submission Loading Overlay (Step 3.11)
        .overlay {
            if viewModel.isSubmitting {
                KnotProgressIndicator.Overlay(
                    message: "Creating your partner vault...\nThis may take a moment"
                )
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: viewModel.isSubmitting)
        // MARK: - Vault Submission Error Alert (Step 3.11)
        .alert("Unable to Save", isPresented: $viewModel.showSubmissionError) {
            Button("Try Again") {
                Task {
                    let success = await viewModel.submitVault()
                    if success {
                        onComplete()
                    }
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text(viewModel.submissionError ?? "An unexpected error occurred. Please try again.")
        }
    }

    // MARK: - Progress Bar

    private var progressBar: some View {
        VStack(spacing: 6) {
            // Step indicator text
            HStack {
                Text(viewModel.currentStep.title)
                    .knotFont(Theme.Typography.label)
                    .foregroundStyle(Theme.textSecondary)

                Spacer()

                Text("Step \(viewModel.currentStep.rawValue + 1) of \(OnboardingStep.totalSteps)")
                    .knotFont(Theme.Typography.label)
                    .foregroundStyle(Theme.textTertiary)
            }

            // Animated progress track
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background track
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Theme.progressTrack)
                        .frame(height: 6)

                    // Filled progress
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Theme.progressFill)
                        .frame(
                            width: geometry.size.width * viewModel.progress,
                            height: 6
                        )
                        .animation(.easeInOut(duration: 0.3), value: viewModel.progress)
                }
            }
            .frame(height: 6)
        }
    }

    // MARK: - Step Content

    @ViewBuilder
    private var stepContent: some View {
        switch viewModel.currentStep {
        case .welcome:
            OnboardingWelcomeView()
        case .partnerName:
            OnboardingPartnerNameView()
        case .tenure:
            OnboardingTenureView()
        case .cohabitation:
            OnboardingCohabitationView()
        case .location:
            OnboardingLocationView()
        case .interests:
            OnboardingInterestsView()
        case .dislikes:
            OnboardingDislikesView()
        case .birthday:
            OnboardingBirthdayView()
        case .anniversary:
            OnboardingAnniversaryView()
        case .holidays:
            OnboardingHolidaysView()
        case .customMilestones:
            OnboardingCustomMilestonesView()
        case .vibes:
            OnboardingVibesView()
        case .budgetJustBecause:
            OnboardingJustBecauseBudgetView()
        case .budgetMinorOccasion:
            OnboardingMinorOccasionBudgetView()
        case .budgetMajorMilestone:
            OnboardingMajorMilestoneBudgetView()
        case .primaryLoveLanguage:
            OnboardingPrimaryLoveLanguageView()
        case .secondaryLoveLanguage:
            OnboardingSecondaryLoveLanguageView()
        case .completion:
            OnboardingCompletionView()
        }
    }

    // MARK: - Navigation Buttons

    @ViewBuilder
    private var navigationButtons: some View {
        if viewModel.currentStep.isLast {
            KnotButton(
                "Get Started",
                variant: .primary,
                size: .lg,
                trailingIcon: Lucide.arrowRight,
                action: {
                    Task {
                        let success = await viewModel.submitVault()
                        if success {
                            onComplete()
                        }
                    }
                }
            )
            .frame(maxWidth: .infinity)
            .disabled(viewModel.isSubmitting)
        } else {
            KnotButton(
                "Next",
                variant: .primary,
                size: .lg,
                trailingIcon: Lucide.chevronRight,
                action: {
                    if viewModel.canProceed {
                        showValidationError = false
                        viewModel.goToNextStep()
                    } else if let message = viewModel.validationMessage {
                        validationErrorText = message
                        showValidationError = true
                        dismissTask?.cancel()
                        dismissTask = Task {
                            try? await Task.sleep(for: .seconds(3))
                            guard !Task.isCancelled else { return }
                            showValidationError = false
                        }
                    }
                }
            )
            .frame(maxWidth: .infinity)
            .opacity(viewModel.canProceed ? 1.0 : 0.4)
        }
    }
}

// MARK: - Preview

#Preview {
    OnboardingContainerView {
        print("Onboarding complete!")
    }
}
