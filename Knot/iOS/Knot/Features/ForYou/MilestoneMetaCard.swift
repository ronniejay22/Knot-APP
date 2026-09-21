//
//  MilestoneMetaCard.swift
//  Knot
//
//  Step 19.63 — the event's DATE · COUNTDOWN · RECIPIENT card, lifted out of
//  `MilestoneDetailView` (Step 19.55, Figma node 579:421) unchanged so the
//  detail screen and the recent-picks sheet render the same card and cannot
//  drift. Pure move: the body, the column/divider helpers and the two static
//  formatters below are the detail view's, verbatim.
//

import SwiftUI

/// Date · countdown · recipient, in three divider-separated columns.
struct MilestoneMetaCard: View {

    let milestone: MilestoneItemResponse
    let partnerName: String
    /// Urgency tier for the countdown's colour, computed by `ForYouViewModel`.
    let urgency: MilestoneUrgency

    var body: some View {
        KnotCard(padding: .lg, radius: Theme.Radius.xl) {
            HStack(alignment: .top, spacing: 0) {
                metaColumn(label: "DATE") {
                    Text(Self.fullDate(from: milestone.milestoneDate))
                        .knotFont(Theme.Typography.cta)
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }

                metaDivider

                metaColumn(label: "COUNTDOWN") {
                    // The urgency ramp Step 19.31 kept on the card carries
                    // through here — a milestone three days out should not read
                    // the same as one 175 days out.
                    //
                    // `daysUntilText(nil)` is "", which a past one-time
                    // milestone really does produce, so the column falls back to
                    // the same "—" placeholder `fullDate` and `budgetTierLabel`
                    // use rather than leaving a labelled column blank. The card
                    // can drop its countdown entirely; a fixed three-column grid
                    // cannot without stranding a divider.
                    Text(Self.countdownText(for: milestone.daysUntil))
                        .knotFont(Theme.Typography.cta)
                        .foregroundStyle(MilestoneCard.countdownColor(for: urgency))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }

                metaDivider

                metaColumn(label: "RECIPIENT") {
                    HStack(spacing: 6) {
                        PartnerInitialAvatar(name: partnerName, diameter: 18)

                        Text(partnerName)
                            .knotFont(Theme.Typography.cta)
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
            }
        }
    }

    private func metaColumn<Content: View>(
        label: String,
        @ViewBuilder value: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .knotFont(Theme.Typography.label)
                .tracking(0.8)
                .foregroundStyle(Theme.textSecondary)

            value()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var metaDivider: some View {
        Rectangle()
            .fill(Theme.surfaceBorder)
            .frame(width: 1, height: 32)
            .padding(.horizontal, 8)
            .accessibilityHidden(true)
    }
}

// MARK: - Pure Helpers

extension MilestoneMetaCard {

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

    /// The countdown column's value, never blank.
    ///
    /// `MilestonesViewModel.daysUntilText(nil)` returns "" — which the backend
    /// genuinely produces for a past one-time milestone — and an empty string
    /// under a "COUNTDOWN" label reads as a rendering failure.
    static func countdownText(for daysUntil: Int?) -> String {
        let text = MilestonesViewModel.daysUntilText(daysUntil)
        return text.isEmpty ? "—" : text
    }
}
