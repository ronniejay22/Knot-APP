//
//  OnboardingMilestonesView.swift
//  Knot
//
//  Created on February 7, 2026.
//  Step 3.1: Placeholder for onboarding Step 5 — Milestones.
//  Full implementation in Step 3.5.
//

import SwiftUI
import LucideIcons

/// Step 5: Set up milestones — birthday (required), anniversary (optional),
/// holiday quick-add, and custom milestones.
///
/// This is a placeholder view for Step 3.1 navigation wiring.
/// Full date pickers, holiday toggles, and custom milestone sheet
/// will be built in Step 3.5.
struct OnboardingMilestonesView: View {
    @Environment(OnboardingViewModel.self) private var viewModel

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(uiImage: Lucide.calendar)
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 48, height: 48)
                .foregroundStyle(.pink)

            Text("Important Dates")
                .font(.title2.weight(.bold))

            Text("Add their birthday, anniversary,\nand other milestones to remember.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)

            // Placeholder for date pickers and milestone list (Step 3.5)
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray6))
                .frame(height: 200)
                .overlay {
                    Text("Date pickers coming in Step 3.5")
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
    OnboardingMilestonesView()
        .environment(OnboardingViewModel())
}
