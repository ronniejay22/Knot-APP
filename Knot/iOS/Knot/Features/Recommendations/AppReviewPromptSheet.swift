//
//  AppReviewPromptSheet.swift
//  Knot
//
//  Created on February 15, 2026.
//  Step 10.4: Prompt shown after a 5-star rating to ask about App Store review.
//

import SwiftUI
import LucideIcons

/// Bottom sheet asking the user if they'd like to share their experience
/// via the App Store review mechanism.
///
/// Shown after a 5-star purchase rating, with a 2-second delay.
/// Rate-limited to once per 90 days.
struct AppReviewPromptSheet: View {
    let onAccept: @MainActor @Sendable () -> Void
    let onDecline: @MainActor @Sendable () -> Void

    var body: some View {
        ZStack {
            Theme.backgroundGradient.ignoresSafeArea()

            VStack(spacing: 20) {
                // Header
                VStack(spacing: 12) {
                    Image(uiImage: Lucide.heart)
                        .renderingMode(.template)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 36, height: 36)
                        .foregroundStyle(Theme.accent)

                    Text("Glad you loved it!")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)

                    Text("Would you like to share your experience with others?")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 16)

                Divider()
                    .overlay(Theme.surfaceBorder)

                // Action buttons
                VStack(spacing: 12) {
                    Button(action: onAccept) {
                        HStack(spacing: 8) {
                            Image(uiImage: Lucide.star)
                                .renderingMode(.template)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 16, height: 16)

                            Text("Yes, let's do it!")
                                .font(.subheadline.weight(.semibold))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(Theme.accent)
                        )
                    }
                    .buttonStyle(.plain)

                    Button(action: onDecline) {
                        Text("Not now")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Theme.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(Theme.surface)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14)
                                            .stroke(Theme.surfaceBorder, lineWidth: 1)
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            .padding(.horizontal, 20)
        }
    }
}

// MARK: - Previews

#Preview("App Review Prompt") {
    AppReviewPromptSheet(
        onAccept: {},
        onDecline: {}
    )
    .preferredColorScheme(.dark)
}
