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

    @State private var viewModel = OnboardingViewModel(seedDefaultHolidays: true)
    @State private var showValidationError = false
    @State private var validationErrorText = ""
    @State private var dismissTask: Task<Void, Never>?

    /// Tracks the direction of the last step change so the slide transition
    /// can reverse for back navigation (in from leading / out to trailing).
    @State private var isNavigatingBack = false

    var body: some View {
        VStack(spacing: 0) {
            // MARK: - Header: Back Button + Progress Bar
            // Hidden on the Welcome step (per the Figma design) and on the final
            // recommendation-reveal step (the vault is already submitted — there's
            // nothing to navigate back to, and "Step 12 of 12" no longer applies).
            if viewModel.showsProgressHeader && !viewModel.currentStep.isFirst {
                HStack(spacing: 16) {
                    // On the first post-Welcome step (Partner Name) the only step
                    // to return to is the Welcome intro, so the back button is
                    // absent and the progress bar spans the full container width.
                    // From step 3 (Tenure) onward the button appears and pushes
                    // the progress bar to the right, shrinking its width.
                    if viewModel.showsBackButton {
                        backButton
                            .transition(.move(edge: .leading).combined(with: .opacity))
                    }
                    progressBar
                }
                // Pin the header row to the back button's height so the progress
                // bar's vertical (Y) position stays identical on every step —
                // only its width changes when the button appears/disappears.
                .frame(height: KnotIconButton.Size.lg.diameter)
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .padding(.bottom, 8)
                // Animate the width change (button push) at the Partner Name ↔
                // Tenure boundary. Keyed to `showsBackButton` so it fires only
                // when visibility changes and never touches the nav buttons
                // (see Step 18.18).
                .animation(.easeInOut(duration: 0.25), value: viewModel.showsBackButton)
            }

            // MARK: - Step Content
            //
            // Animation is scoped to the step content here (not the outer
            // VStack) so the slide+fade transition between steps does not
            // bleed into the navigation buttons below. Wrapping the Next
            // button in an animated subtree noticeably delayed first taps on
            // the new step on real devices — keeping the buttons outside the
            // animated region restores immediate hit testing.
            stepContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.asymmetric(
                    insertion: .move(edge: isNavigatingBack ? .leading : .trailing).combined(with: .opacity),
                    removal: .move(edge: isNavigatingBack ? .trailing : .leading).combined(with: .opacity)
                ))
                .id(viewModel.currentStep)
                .animation(.easeInOut(duration: 0.25), value: viewModel.currentStep)

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
        .animation(.easeInOut(duration: 0.25), value: showValidationError)
        .onChange(of: viewModel.currentStep) { _, _ in
            // Dismiss any lingering error and cancel pending dismiss when switching steps
            dismissTask?.cancel()
            dismissTask = nil
            showValidationError = false
        }
    }

    // MARK: - Back Button

    /// Returns to the previous onboarding step. Sits to the left of the progress
    /// bar in the header per the Figma design (node 107:4315). Uses the app's
    /// standard accent-tinted ghost icon button.
    private var backButton: some View {
        KnotIconButton(
            icon: Lucide.chevronLeft,
            variant: .ghost,
            size: .lg
        ) {
            isNavigatingBack = true
            viewModel.goToPreviousStep()
        }
        // Offset the ghost button's transparent inset so the chevron glyph
        // aligns with the 24pt content margin.
        .padding(.leading, -10)
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
        case .vibes:
            OnboardingVibesView()
        case .loveLanguages:
            OnboardingLoveLanguagesView()
        case .completion:
            OnboardingCompletionView()
        }
    }

    // MARK: - Navigation Buttons

    @ViewBuilder
    private var navigationButtons: some View {
        if viewModel.currentStep.isLast {
            // Final recommendation-reveal step. The vault is already submitted and
            // the user is looking at their first picks, so "Continue" simply
            // finishes onboarding. Always enabled and visible — independent of the
            // reveal's loading/error/empty state — so the user is never trapped.
            KnotButton(
                "Continue",
                variant: .primary,
                size: .lg,
                action: { onComplete() }
            )
            .frame(maxWidth: .infinity)
        } else {
            // Every data-entry step (including the final Love Languages step)
            // simply advances forward. The vault is submitted on the next
            // (`.completion`) step, behind a single loading screen — see
            // `OnboardingCompletionView`.
            KnotButton(
                viewModel.currentStep == .welcome ? "Get Started" : "Next",
                variant: .primary,
                size: .lg,
                action: {
                    if viewModel.canProceed {
                        showValidationError = false
                        isNavigatingBack = false
                        viewModel.goToNextStep()
                    } else {
                        presentValidationError()
                    }
                }
            )
            .frame(maxWidth: .infinity)
            .opacity(viewModel.canProceed ? 1.0 : 0.4)
        }
    }

    /// Shows the inline validation banner with the current step's message and
    /// schedules its auto-dismiss after 3 seconds. Used when the user taps Next
    /// before the current step's inputs are valid.
    private func presentValidationError() {
        guard let message = viewModel.validationMessage else { return }
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

// MARK: - Preview

#Preview {
    OnboardingContainerView {
        print("Onboarding complete!")
    }
}
