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
    let onGenerate: @MainActor () -> Void

    var body: some View {
        KnotCard(padding: .lg, radius: Theme.Radius.lg) {
            VStack(alignment: .leading, spacing: 12) {
                KnotSectionHeader("Surprise them today", icon: Lucide.sparkles)

                Text("Get personalized gift, date, or experience ideas for \(partnerName) \u{2014} no occasion needed.")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                KnotButton(
                    "Get Recommendations",
                    variant: .primary,
                    size: .md,
                    leadingIcon: Lucide.sparkles,
                    action: onGenerate
                )
            }
        }
    }
}
