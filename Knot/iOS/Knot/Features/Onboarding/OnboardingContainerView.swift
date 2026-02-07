//
//  OnboardingContainerView.swift
//  Knot
//
//  Created on February 7, 2026.
//  Step 3.1: Multi-step onboarding navigation container.
//

import SwiftUI
import LucideIcons

/// The root container for the onboarding flow. Manages step transitions,
/// a progress bar, and Back/Next navigation buttons.
///
/// Creates and owns the `OnboardingViewModel`, injecting it into the SwiftUI
/// environment so all child step views share the same state. Data entered
/// in any step persists when navigating back and forth.
///
/// The container displays:
/// - A progress bar at the top (animated)
/// - The current step's view in the center
/// - Back (chevron) and Next/Get Started buttons at the bottom
///
/// The `onComplete` closure is called when the user taps "Get Started" on the
/// completion step, signaling `ContentView` to transition to the Home screen.
struct OnboardingContainerView: View {
    /// Called when the user finishes onboarding (taps "Get Started" on the last step).
    var onComplete: () -> Void

    @State private var viewModel = OnboardingViewModel()

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

            // MARK: - Navigation Buttons
            navigationButtons
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
        }
        .background(Theme.backgroundGradient.ignoresSafeArea())
        .environment(viewModel)
        .animation(.easeInOut(duration: 0.3), value: viewModel.currentStep)
    }

    // MARK: - Progress Bar

    private var progressBar: some View {
        VStack(spacing: 6) {
            // Step indicator text
            HStack {
                Text(viewModel.currentStep.title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(Theme.textSecondary)

                Spacer()

                Text("Step \(viewModel.currentStep.rawValue + 1) of \(OnboardingStep.totalSteps)")
                    .font(.caption)
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
        case .completion:
            OnboardingCompletionView()
        }
    }

    // MARK: - Navigation Buttons

    private var navigationButtons: some View {
        HStack(spacing: 12) {
            // Back button (hidden on first step)
            if !viewModel.currentStep.isFirst {
                Button {
                    viewModel.goToPreviousStep()
                } label: {
                    HStack(spacing: 6) {
                        Image(uiImage: Lucide.chevronLeft)
                            .renderingMode(.template)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 18, height: 18)

                        Text("Back")
                            .font(.body.weight(.medium))
                    }
                    .frame(height: 50)
                    .padding(.horizontal, 20)
                }
                .buttonStyle(.bordered)
                .tint(.white)
            }

            Spacer()

            // Next / Get Started button
            if viewModel.currentStep.isLast {
                // Completion step — "Get Started" button
                Button {
                    onComplete()
                } label: {
                    HStack(spacing: 8) {
                        Text("Get Started")
                            .font(.body.weight(.semibold))

                        Image(uiImage: Lucide.arrowRight)
                            .renderingMode(.template)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 18, height: 18)
                    }
                    .frame(height: 50)
                    .padding(.horizontal, 28)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
            } else {
                // Normal step — "Next" button
                Button {
                    viewModel.goToNextStep()
                } label: {
                    HStack(spacing: 6) {
                        Text("Next")
                            .font(.body.weight(.semibold))

                        Image(uiImage: Lucide.chevronRight)
                            .renderingMode(.template)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 18, height: 18)
                    }
                    .frame(height: 50)
                    .padding(.horizontal, 28)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .disabled(!viewModel.canProceed)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    OnboardingContainerView {
        print("Onboarding complete!")
    }
}
