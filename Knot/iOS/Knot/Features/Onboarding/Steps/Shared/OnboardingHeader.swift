//
//  OnboardingHeader.swift
//  Knot
//
//  Step 18.30: Reusable left-aligned onboarding step header.
//

import SwiftUI

/// The serif title + optional gray subtitle shown at the top of each onboarding
/// step, left-aligned to the leading edge of the 24pt onboarding container (per
/// the approved Figma flow, file `pSH5gTc4J24uMA7GI3Wcyl`, node `86:39`).
///
/// Replaces the per-step centered `headerSection` blocks that were duplicated
/// across the standard form steps. Centralizing the header means every step
/// shares one alignment, spacing, and typography treatment — and any future
/// step inherits it for free.
///
/// The Welcome and Completion screens are intentionally NOT migrated here: they
/// are centered "hero" moments (welcome illustration / "You're All Set!"
/// celebration) and keep their own bespoke headers.
struct OnboardingHeader: View {
    let title: String
    let subtitle: String?

    init(title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        // `frame(maxWidth: .infinity, alignment: .leading)` on each Text makes
        // the block fill the container width and pin to the left, instead of
        // shrink-wrapping its content and centering. The 12pt spacing matches
        // the Figma `gap-[12px]` between title and subtitle.
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .knotFont(Theme.Typography.onboardingHeader)
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
    }
}

#Preview("Title + subtitle") {
    OnboardingHeader(
        title: "Do you celebrate an anniversary?",
        subtitle: "Optional — flip the toggle if you want a reminder."
    )
    .padding(24)
}

#Preview("Title only") {
    OnboardingHeader(title: "Do you live together?")
        .padding(24)
}
