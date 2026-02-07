//
//  OnboardingInterestsView.swift
//  Knot
//
//  Created on February 7, 2026.
//  Step 3.1: Placeholder for onboarding Step 3 — Interests (5 likes).
//  Full implementation in Step 3.3.
//

import SwiftUI
import LucideIcons

/// Step 3: Select 5 interests the partner likes.
///
/// This is a placeholder view for Step 3.1 navigation wiring.
/// Full chip-grid UI with selection counter and validation (exactly 5)
/// will be built in Step 3.3.
struct OnboardingInterestsView: View {
    @Environment(OnboardingViewModel.self) private var viewModel

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(uiImage: Lucide.sparkles)
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 48, height: 48)
                .foregroundStyle(.pink)

            Text("What Do They Love?")
                .font(.title2.weight(.bold))

            Text("Select 5 interests your partner enjoys.\n\(viewModel.selectedInterests.count) of 5 selected")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)

            // Placeholder for chip grid (Step 3.3)
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray6))
                .frame(height: 240)
                .overlay {
                    Text("Interest chips coming in Step 3.3")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 24)

            Spacer()
        }
        .padding(.horizontal, 24)
    }
}

#Preview {
    OnboardingInterestsView()
        .environment(OnboardingViewModel())
}
