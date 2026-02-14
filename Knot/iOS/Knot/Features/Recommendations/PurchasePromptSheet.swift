//
//  PurchasePromptSheet.swift
//  Knot
//
//  Created on February 14, 2026.
//  Step 9.4: Return-to-app purchase confirmation prompt shown after merchant handoff.
//

import SwiftUI
import LucideIcons

/// Bottom sheet shown when the user returns to Knot after a merchant handoff.
/// Asks "Did you complete your purchase?" with Yes/No options.
///
/// - "Yes, I bought it!" records a "purchased" feedback action and opens the rating prompt
/// - "No, save for later" saves the recommendation locally via SwiftData
struct PurchasePromptSheet: View {
    let title: String
    let merchantName: String?
    let onConfirmPurchase: @MainActor @Sendable () -> Void
    let onSaveForLater: @MainActor @Sendable () -> Void
    let onDismiss: @MainActor @Sendable () -> Void

    var body: some View {
        ZStack {
            Theme.backgroundGradient.ignoresSafeArea()

            VStack(spacing: 20) {
                // Header
                VStack(spacing: 12) {
                    Image(uiImage: Lucide.shoppingBag)
                        .renderingMode(.template)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 36, height: 36)
                        .foregroundStyle(Theme.accent)

                    Text("Did you complete your purchase?")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 16)

                // Item summary
                VStack(spacing: 4) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)

                    if let merchantName, !merchantName.isEmpty {
                        HStack(spacing: 4) {
                            Image(uiImage: Lucide.store)
                                .renderingMode(.template)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 12, height: 12)
                            Text("from \(merchantName)")
                                .font(.caption)
                        }
                        .foregroundStyle(Theme.textSecondary)
                    }
                }

                Divider()
                    .overlay(Theme.surfaceBorder)

                // Action buttons
                VStack(spacing: 12) {
                    Button(action: onConfirmPurchase) {
                        HStack(spacing: 8) {
                            Image(uiImage: Lucide.check)
                                .renderingMode(.template)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 16, height: 16)
                            Text("Yes, I bought it!")
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

                    Button(action: onSaveForLater) {
                        HStack(spacing: 8) {
                            Image(uiImage: Lucide.bookmark)
                                .renderingMode(.template)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 16, height: 16)
                            Text("No, save for later")
                                .font(.subheadline.weight(.medium))
                        }
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

#Preview("Purchase Prompt") {
    PurchasePromptSheet(
        title: "Personalized Star Map Print",
        merchantName: "Amazon",
        onConfirmPurchase: {},
        onSaveForLater: {},
        onDismiss: {}
    )
    .preferredColorScheme(.dark)
}

#Preview("No Merchant") {
    PurchasePromptSheet(
        title: "Sunset Helicopter Tour",
        merchantName: nil,
        onConfirmPurchase: {},
        onSaveForLater: {},
        onDismiss: {}
    )
    .preferredColorScheme(.dark)
}
