//
//  PurchaseRatingSheet.swift
//  Knot
//
//  Created on February 14, 2026.
//  Step 9.4: Optional rating prompt shown after the user confirms a purchase.
//

import SwiftUI
import LucideIcons

/// Bottom sheet for rating a purchased recommendation.
///
/// Shown after the user taps "Yes, I bought it!" in the purchase prompt.
/// Features a 5-star selector and an optional text feedback field.
/// The user can submit a rating or skip.
struct PurchaseRatingSheet: View {
    let itemTitle: String
    let onSubmit: @MainActor @Sendable (Int, String?) -> Void
    let onSkip: @MainActor @Sendable () -> Void

    @State private var rating: Int = 0
    @State private var feedbackText: String = ""

    var body: some View {
        ZStack {
            Theme.backgroundGradient.ignoresSafeArea()

            VStack(spacing: 20) {
                // Header
                VStack(spacing: 8) {
                    Image(uiImage: Lucide.star)
                        .renderingMode(.template)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 32, height: 32)
                        .foregroundStyle(Theme.accent)

                    Text("How was this pick?")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)

                    Text(itemTitle)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
                .padding(.top, 16)

                // Star rating row
                HStack(spacing: 12) {
                    ForEach(1...5, id: \.self) { starValue in
                        Button {
                            rating = starValue
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        } label: {
                            Image(systemName: starValue <= rating ? "star.fill" : "star")
                                .font(.title2)
                                .foregroundStyle(starValue <= rating ? .yellow : Theme.textTertiary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 8)

                // Optional feedback text
                TextField("Any notes? (optional)", text: $feedbackText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .padding(12)
                    .lineLimit(3...6)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Theme.surface)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Theme.surfaceBorder, lineWidth: 1)
                            )
                    )
                    .padding(.horizontal, 20)

                // Submit button
                Button {
                    let text = feedbackText.trimmingCharacters(in: .whitespacesAndNewlines)
                    onSubmit(rating, text.isEmpty ? nil : text)
                } label: {
                    Text("Submit")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(Theme.accent)
                        )
                }
                .buttonStyle(.plain)
                .disabled(rating == 0)
                .opacity(rating == 0 ? 0.5 : 1.0)
                .padding(.horizontal, 20)

                // Skip button
                Button(action: onSkip) {
                    Text("Skip")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.textSecondary)
                }
                .padding(.bottom, 20)
            }
            .padding(.horizontal, 20)
        }
    }
}

// MARK: - Previews

#Preview("Rating Sheet") {
    PurchaseRatingSheet(
        itemTitle: "Personalized Star Map Print",
        onSubmit: { rating, text in
            print("Rating: \(rating), Text: \(text ?? "none")")
        },
        onSkip: {}
    )
    .preferredColorScheme(.dark)
}
