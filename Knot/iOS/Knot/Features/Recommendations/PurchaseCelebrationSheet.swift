//
//  PurchaseCelebrationSheet.swift
//  Knot
//
//  Created on July 30, 2026.
//  Celebratory beat shown right after the user confirms a purchase, before the
//  "How was this pick?" rating step.
//

import SwiftUI
import LucideIcons

/// Bottom sheet that celebrates a confirmed purchase before the rating prompt.
///
/// Shown after the user taps "Yes, I bought it!" in the purchase prompt. It reads
/// "{Partner} is going to love it! Good choice!" and auto-advances into the rating
/// sheet after a short beat (see `RecommendationsViewModel.confirmPurchase`), so it
/// is a display-only view with no buttons.
struct PurchaseCelebrationSheet: View {
    /// Partner's name; falls back to neutral wording when unknown.
    let partnerName: String?

    /// "{Partner} is going to love it!" when a name is available, else a neutral
    /// phrasing matching the app's "your partner" fallback elsewhere.
    private var headline: String {
        if let name = partnerName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return "\(name) is going to love it!"
        }
        return "They're going to love it!"
    }

    var body: some View {
        ZStack {
            Theme.backgroundGradient.ignoresSafeArea()

            VStack(spacing: 16) {
                Image(uiImage: Lucide.heart)
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 40, height: 40)
                    .foregroundStyle(Theme.accent)

                Text(headline)
                    .knotFont(Theme.Typography.cardTitle)
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.center)

                Text("Good choice!")
                    .knotFont(Theme.Typography.body)
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(.horizontal, 20)
        }
    }
}

// MARK: - Previews

#Preview("With partner name") {
    PurchaseCelebrationSheet(partnerName: "Alex")
}

#Preview("No partner name") {
    PurchaseCelebrationSheet(partnerName: nil)
}
