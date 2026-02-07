//
//  OnboardingCompletionView.swift
//  Knot
//
//  Created on February 7, 2026.
//  Step 3.1: Placeholder for onboarding Step 9 — Completion / Transition to Home.
//  Full implementation in Step 3.9.
//

import SwiftUI
import LucideIcons

/// Step 9: Onboarding complete — shows a success message and summary.
///
/// This is a placeholder view for Step 3.1 navigation wiring.
/// Full partner profile summary (name, vibes, upcoming milestone)
/// and "Get Started" CTA will be built in Step 3.9.
/// The "Get Started" button is in `OnboardingContainerView`'s navigation bar.
struct OnboardingCompletionView: View {
    @Environment(OnboardingViewModel.self) private var viewModel

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // MARK: - Success Icon
            Image(uiImage: Lucide.partyPopper)
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 80, height: 80)
                .foregroundStyle(.pink)

            // MARK: - Title & Message
            VStack(spacing: 12) {
                Text("You're All Set!")
                    .font(.system(size: 28, weight: .bold))
                    .tracking(-0.5)

                Text("Your Partner Vault is ready.\nKnot will start finding personalized\ngifts, dates, and experiences.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }

            Spacer()

            // MARK: - Profile Summary Placeholder
            VStack(alignment: .leading, spacing: 12) {
                if !viewModel.partnerName.isEmpty {
                    HStack(spacing: 8) {
                        Image(uiImage: Lucide.user)
                            .renderingMode(.template)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 16, height: 16)
                            .foregroundStyle(.secondary)
                        Text(viewModel.partnerName)
                            .font(.subheadline)
                    }
                }

                if !viewModel.selectedVibes.isEmpty {
                    HStack(spacing: 8) {
                        Image(uiImage: Lucide.palette)
                            .renderingMode(.template)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 16, height: 16)
                            .foregroundStyle(.secondary)
                        Text(viewModel.selectedVibes.sorted().joined(separator: ", "))
                            .font(.subheadline)
                    }
                }

                if !viewModel.selectedInterests.isEmpty {
                    HStack(spacing: 8) {
                        Image(uiImage: Lucide.sparkles)
                            .renderingMode(.template)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 16, height: 16)
                            .foregroundStyle(.secondary)
                        Text("\(viewModel.selectedInterests.count) interests selected")
                            .font(.subheadline)
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 24)

            Spacer()

            Text("Tap 'Get Started' below to begin")
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 24)
    }
}

#Preview {
    OnboardingCompletionView()
        .environment(OnboardingViewModel())
}
