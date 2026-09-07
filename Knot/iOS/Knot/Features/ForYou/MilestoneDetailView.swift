//
//  MilestoneDetailView.swift
//  Knot
//
//  Created on September 6, 2026.
//  Journal tab — the destination behind a milestone card's "See details".
//
//  ⚠️ PLACEHOLDER — TO BE REPLACED WHOLESALE.
//
//  The designs for this screen are coming separately. This stands in so the
//  "See details" button has an honest destination rather than being an inert
//  control, and it renders nothing that isn't already stored on
//  `MilestoneItemResponse` — no new endpoint, DTO field, or asset.
//
//  The seam to swap into is `ForYouView.detailMilestone`: a
//  `.fullScreenCover(item:)` that hands this view the milestone, the partner
//  name, and the pre-formatted "MMM d" date. Replacing the body of this file is
//  the whole job; nothing else needs to move.
//

import SwiftUI
import LucideIcons

/// A single Journal event's own screen.
struct MilestoneDetailView: View {

    let milestone: MilestoneItemResponse
    let partnerName: String
    let onDismiss: @MainActor () -> Void

    /// Matches `MilestoneCard.artworkHeight`'s reasoning — the occasion
    /// illustrations are 1050×480, so a hero this tall keeps the crop near
    /// their native ratio.
    private static let artworkHeight: CGFloat = 180

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.backgroundGradient.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        artwork
                        heading
                        factsCard
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("Event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    KnotIconButton(icon: Lucide.x, variant: .ghost, size: .sm, action: onDismiss)
                        .accessibilityLabel("Close")
                }
            }
        }
    }

    // MARK: - Artwork

    /// Composed as an overlay on `Color.clear` rather than sized directly — a
    /// `scaledToFill` image reports a size larger than its proposal and that
    /// overflow propagates into *layout*, which is what shifted the whole
    /// Journal sideways in Step 19.31. `clipShape` clips pixels; it does not
    /// constrain layout.
    @ViewBuilder
    private var artwork: some View {
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
        .frame(height: Self.artworkHeight)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.xl, style: .continuous))
        .accessibilityHidden(true)
    }

    // MARK: - Heading

    private var heading: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(milestone.milestoneName)
                .knotFont(Theme.Typography.onboardingHeader)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(3)
                .minimumScaleFactor(0.7)

            HStack(spacing: 8) {
                PartnerInitialAvatar(name: partnerName, diameter: 22)

                Text("For \(partnerName)")
                    .knotFont(Theme.Typography.label)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Facts

    /// Bare rows in a `VStack(spacing: 10)`, not wrapped in a `KnotCard`:
    /// `KnotListRow` already draws its own surface fill, border, and
    /// `Theme.Radius.md` corner, so nesting them in a card double-draws that
    /// chrome. This matches every other `KnotListRow` call site.
    private var factsCard: some View {
        VStack(spacing: 10) {
            KnotListRow.info(
                icon: Lucide.calendar,
                title: "Date",
                value: Self.fullDate(from: milestone.milestoneDate)
            )

            if let days = milestone.daysUntil {
                KnotListRow.info(
                    icon: Lucide.clock,
                    title: "Countdown",
                    value: MilestonesViewModel.daysUntilText(days)
                )
            }

            KnotListRow.info(
                icon: Lucide.refreshCw,
                title: "Repeats",
                value: Self.recurrenceLabel(milestone.recurrence)
            )

            KnotListRow.info(
                icon: Lucide.star,
                title: "Occasion",
                value: Self.occasionLabel(for: milestone)
            )

            KnotListRow.info(
                icon: Lucide.wallet,
                title: "Budget",
                value: MilestonesViewModel.budgetTierLabel(milestone.budgetTier)
            )
        }
    }
}

// MARK: - Pure Helpers

extension MilestoneDetailView {

    /// "2000-12-25" → "December 25".
    ///
    /// Parses the stored value directly rather than taking the card's short
    /// "MMM d" string as a fallback: `ForYouViewModel.formattedDate(_:)` returns
    /// the *raw* stored string on exactly the same parse failure, so falling
    /// back to it would surface the `2000-MM-DD` storage format to the user.
    /// An unparseable date shows the same "—" `budgetTierLabel` uses for an
    /// unknown value.
    static func fullDate(from milestoneDate: String) -> String {
        let parts = milestoneDate.split(separator: "-")
        guard parts.count >= 3,
              let month = Int(parts[1]),
              let day = Int(parts[2]) else {
            return "—"
        }

        let formatted = formattedMilestoneDate(month: month, day: day)
        return formatted.isEmpty ? "—" : formatted
    }

    static func recurrenceLabel(_ recurrence: String) -> String {
        switch recurrence {
        case "yearly": return "Every year"
        case "one_time": return "Once"
        default: return recurrence.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    /// The occasion's display name, falling back to the milestone type.
    ///
    /// `defaultCategory` is short-circuited deliberately. It *is* in the
    /// catalogue, but its display name is "Something Else" — written as a
    /// picker choice ("my occasion is something else"), not as a label. Every
    /// milestone written before migration 00027 resolves to `default` on read,
    /// so a legacy Christmas would otherwise read "Occasion: Something Else"
    /// where "Occasion: Holiday" is both true and useful.
    static func occasionLabel(for milestone: MilestoneItemResponse) -> String {
        let category = milestone.occasionCategory
        if category != MilestoneOccasionOption.defaultCategory,
           let option = MilestoneOccasionOption.option(id: category) {
            return option.displayName
        }
        return milestone.milestoneType.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Milestone Detail") {
    MilestoneDetailView(
        milestone: MilestoneItemResponse(
            id: "1",
            milestoneType: "holiday",
            milestoneName: "Christmas",
            milestoneDate: "2000-12-25",
            recurrence: "yearly",
            budgetTier: "major_milestone",
            daysUntil: 175,
            createdAt: "2026-07-04",
            occasionCategory: "christmas"
        ),
        partnerName: "Jas",
        onDismiss: {}
    )
}
#endif
