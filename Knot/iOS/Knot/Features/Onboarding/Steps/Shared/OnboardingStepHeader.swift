//
//  OnboardingStepHeader.swift
//  Knot
//
//  Shared left-aligned header (title + optional subtitle) for onboarding
//  question steps. Centralizes the style so every step matches the Figma
//  design (node 27:2) — full-width, leading-aligned.
//

import SwiftUI

/// Standard left-aligned title + optional subtitle shown at the top of each
/// onboarding question step. Spans the full container width.
///
/// The hero Welcome step and the Completion celebration step intentionally do
/// not use this — they keep their centered layouts.
struct OnboardingStepHeader: View {
    let title: String
    var subtitle: String? = nil

    /// 28pt Fraunces SemiBold — a step-specific override of the 32pt
    /// `Theme.Typography.onboardingHeader` token (which the Welcome hero and
    /// Completion screens still use at full size). Same family and Dynamic Type
    /// relation as the token, only the point size differs.
    private static let titleFont: Font = .custom("Fraunces", size: 28, relativeTo: .title).weight(.semibold)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .knotFont(Self.titleFont)
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let subtitle {
                Text(subtitle)
                    .knotFont(Theme.Typography.body)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.leading)
                    .lineSpacing(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    VStack(spacing: 32) {
        OnboardingStepHeader(
            title: "How does Ronnie feel most loved?",
            subtitle: "Pick their primary love language."
        )
        OnboardingStepHeader(title: "What's their name?")
    }
    .padding(24)
    .background(Theme.backgroundGradient.ignoresSafeArea())
}
