//
//  OnboardingVibesView.swift
//  Knot
//
//  Created on February 7, 2026.
//  Step 3.1: Placeholder for onboarding Step 6 — Aesthetic Vibes.
//  Full implementation in Step 3.6.
//

import SwiftUI
import LucideIcons

/// Step 6: Select 1–4 aesthetic vibes that describe the partner's style.
///
/// This is a placeholder view for Step 3.1 navigation wiring.
/// Full visual cards/chips with Lucide icons and selection limits
/// will be built in Step 3.6.
struct OnboardingVibesView: View {
    @Environment(OnboardingViewModel.self) private var viewModel

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(uiImage: Lucide.palette)
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 48, height: 48)
                .foregroundStyle(Theme.accent)

            Text("Their Aesthetic")
                .font(.title2.weight(.bold))

            Text("What vibes match their style?\nSelect 1 to 4 options.\n\(viewModel.selectedVibes.count) selected")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)

            // Placeholder for vibe cards (Step 3.6)
            RoundedRectangle(cornerRadius: 12)
                .fill(Theme.surface)
                .frame(height: 200)
                .overlay {
                    Text("Vibe cards coming in Step 3.6")
                        .font(.caption)
                        .foregroundStyle(Theme.textTertiary)
                }
                .padding(.horizontal, 24)

            Spacer()
        }
        .padding(.horizontal, 24)
    }
}

#Preview {
    OnboardingVibesView()
        .environment(OnboardingViewModel())
}
