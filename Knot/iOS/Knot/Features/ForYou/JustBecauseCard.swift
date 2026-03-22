//
//  JustBecauseCard.swift
//  Knot
//
//  Created on March 20, 2026.
//  "Surprise them today" card for non-milestone recommendation generation.
//

import SwiftUI
import LucideIcons

/// Card displayed at the top of the For You timeline for "just because" recommendations.
struct JustBecauseCard: View {

    let partnerName: String
    let onGenerate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(uiImage: Lucide.sparkles)
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 20, height: 20)
                    .foregroundStyle(Theme.accent)

                Text("Surprise them today")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
            }

            Text("Get personalized gift, date, or experience ideas for \(partnerName) \u{2014} no occasion needed.")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: onGenerate) {
                HStack(spacing: 6) {
                    Image(uiImage: Lucide.sparkles)
                        .renderingMode(.template)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 14, height: 14)

                    Text("Get Recommendations")
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Theme.accent)
                )
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Theme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Theme.surfaceBorder, lineWidth: 1)
                )
        )
    }
}
