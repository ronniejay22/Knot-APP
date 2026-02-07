//
//  OnboardingWelcomeView.swift
//  Knot
//
//  Created on February 7, 2026.
//  Step 3.1: Placeholder for onboarding Step 1 — Welcome / Value Proposition.
//

import SwiftUI
import LucideIcons

/// Step 1: Welcome screen introducing the Partner Vault concept.
///
/// Displays Knot branding and explains what the user is about to set up.
/// This is a read-only informational step — the "Next" button is always enabled.
/// Full design will be refined in future iterations.
struct OnboardingWelcomeView: View {
    @Environment(OnboardingViewModel.self) private var viewModel

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // MARK: - Hero Icon
            Image(uiImage: Lucide.heart)
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 80, height: 80)
                .foregroundStyle(.pink)

            // MARK: - Title & Subtitle
            VStack(spacing: 12) {
                Text("Build Your Partner Vault")
                    .font(.system(size: 28, weight: .bold))
                    .tracking(-0.5)
                    .multilineTextAlignment(.center)

                Text("Tell us about your partner so we can find\nperfect gifts, dates, and experiences.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }

            Spacer()

            // MARK: - What You'll Set Up
            VStack(alignment: .leading, spacing: 16) {
                WelcomeChecklistRow(icon: Lucide.user, text: "Partner basics & location")
                WelcomeChecklistRow(icon: Lucide.sparkles, text: "Their interests & style")
                WelcomeChecklistRow(icon: Lucide.calendar, text: "Important milestones")
                WelcomeChecklistRow(icon: Lucide.wallet, text: "Budget preferences")
                WelcomeChecklistRow(icon: Lucide.heartHandshake, text: "Love languages")
            }
            .padding(.horizontal, 32)

            Spacer()

            Text("Takes about 3 minutes")
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 24)
    }
}

// MARK: - Checklist Row

private struct WelcomeChecklistRow: View {
    let icon: UIImage
    let text: String

    var body: some View {
        HStack(spacing: 14) {
            Image(uiImage: icon)
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 20, height: 20)
                .foregroundStyle(.pink.opacity(0.8))

            Text(text)
                .font(.subheadline)
                .foregroundStyle(.primary)

            Spacer()
        }
    }
}

#Preview {
    OnboardingWelcomeView()
        .environment(OnboardingViewModel())
}
