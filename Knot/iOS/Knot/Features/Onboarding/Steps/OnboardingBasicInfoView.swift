//
//  OnboardingBasicInfoView.swift
//  Knot
//
//  Created on February 7, 2026.
//  Step 3.1: Placeholder for onboarding Step 2 — Partner Basic Info.
//  Full implementation in Step 3.2.
//

import SwiftUI
import LucideIcons

/// Step 2: Partner basic information — name, tenure, cohabitation, location.
///
/// This is a placeholder view for Step 3.1 navigation wiring.
/// Full input fields, validation (name required), and location autocomplete
/// will be built in Step 3.2.
struct OnboardingBasicInfoView: View {
    @Environment(OnboardingViewModel.self) private var viewModel

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(uiImage: Lucide.user)
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 48, height: 48)
                .foregroundStyle(.pink)

            Text("Partner Info")
                .font(.title2.weight(.bold))

            Text("Name, relationship tenure,\ncohabitation status, and location.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)

            // Placeholder for actual form fields (Step 3.2)
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray6))
                .frame(height: 200)
                .overlay {
                    Text("Form fields coming in Step 3.2")
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
    OnboardingBasicInfoView()
        .environment(OnboardingViewModel())
}
