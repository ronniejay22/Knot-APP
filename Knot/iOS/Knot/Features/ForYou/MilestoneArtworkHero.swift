//
//  MilestoneArtworkHero.swift
//  Knot
//
//  Step 19.63 — the event's occasion illustration as a full-width hero,
//  lifted out of `MilestoneDetailView` (Step 19.55) unchanged so the detail
//  screen and the recent-picks sheet share one rendering. Pure move.
//

import SwiftUI

/// The occasion illustration (or the icon placeholder) at hero size.
///
/// Composed as an overlay on `Color.clear` rather than sized directly — a
/// `scaledToFill` image reports a size larger than its proposal and that
/// overflow propagates into *layout*, which is what shifted the whole Journal
/// sideways in Step 19.31. `clipShape` clips pixels; it does not constrain
/// layout.
struct MilestoneArtworkHero: View {

    let milestone: MilestoneItemResponse

    /// Matches `MilestoneCard.artworkHeight`'s reasoning — the occasion
    /// illustrations are 1050×480, so a hero this tall keeps the crop near
    /// their native ratio.
    var height: CGFloat = 140

    var body: some View {
        Group {
            switch MilestoneCard.artwork(for: milestone.occasionCategory) {
            case .illustration(let name):
                Color.clear
                    .overlay {
                        Image(name)
                            .resizable()
                            .scaledToFill()
                    }
            case .placeholder:
                LinearGradient(
                    colors: [Theme.accent.opacity(0.28), Theme.accent.opacity(0.10)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .overlay {
                    Image(systemName: MilestonesViewModel.iconName(for: milestone.milestoneType))
                        .font(.system(size: 52, weight: .light))
                        .foregroundStyle(Theme.accent.opacity(0.55))
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.xl, style: .continuous))
        .accessibilityHidden(true)
    }
}
