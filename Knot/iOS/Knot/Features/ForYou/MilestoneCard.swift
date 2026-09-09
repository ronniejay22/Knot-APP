//
//  MilestoneCard.swift
//  Knot
//
//  Created on September 5, 2026.
//  Journal tab — one upcoming milestone rendered as a full-width artwork card.
//

import SwiftUI

/// A single upcoming milestone on the Journal tab.
///
/// Replaces the vertical-timeline row (`TimelineEntryView`) with a card:
///
/// ```
/// ┌───────────────────────────────┐
/// │  [ occasion artwork, 140pt ]  │
/// │  DEC 25            in 175 days│
/// │  Christmas                    │
/// │  ─────────────────────────────│
/// │  (J) For Jas  [See details][✦]│
/// └───────────────────────────────┘
/// ```
///
/// Both footer controls lead to the same place — that event's recommendations —
/// but they frame it differently: "See details" raises
/// `MilestoneRecommendationSheet`, which names the occasion and says what will
/// happen before pushing, while the sparkle icon pushes straight through for
/// anyone who already knows what it does.
///
/// The artwork comes from the occasion illustrations already bundled for
/// `OccasionEntryModal` (Step 19.25), keyed by the milestone's
/// `occasionCategory` — so per-milestone art needs no new assets and no new
/// data plumbing. Only the `default` category ships no illustration; that
/// falls back to a tinted gradient carrying the milestone-type glyph.
struct MilestoneCard: View {

    let milestone: MilestoneItemResponse
    let partnerName: String
    /// Pre-formatted "MMM d" date from `ForYouViewModel.formattedDate(_:)`.
    let formattedDate: String
    let urgency: MilestoneUrgency
    /// Raises the milestone's recommendation sheet. Optional so the card still
    /// renders where no destination is wired (previews, harnesses).
    ///
    /// `@MainActor` matches the convention `JustBecauseCard.onGenerate` and
    /// `KnotIconButton.action` already use — without it, handing the closure to
    /// `KnotButton` (whose `action` is `@MainActor`) is a non-Sendable
    /// conversion warning under strict concurrency.
    let onSeeDetails: (@MainActor () -> Void)?
    let onGetRecommendations: (() -> Void)?

    /// Was 200pt, which let only one card and a sliver of the next fit on screen —
    /// the feed read as a stack of posters rather than a list of what's coming up.
    /// The illustrations are 1050×480, so at this height the crop stays close to
    /// their native aspect ratio and the figures aren't cut.
    private static let artworkHeight: CGFloat = 140

    var body: some View {
        KnotCard(padding: .md, radius: Theme.Radius.xl) {
            VStack(alignment: .leading, spacing: 12) {
                artwork
                metaRow
                title
                Divider()
                    .overlay(Theme.surfaceBorder)
                footerRow
            }
        }
    }

    // MARK: - Artwork

    /// The illustration is composed as an overlay on `Color.clear` rather than
    /// sized directly — the same idiom `SpotlightCard` uses (Step 18.45).
    /// A `.resizable().scaledToFill()` image reports a size larger than the
    /// proposal to preserve its aspect ratio, and that overflow *propagates
    /// into layout*: sized directly, a 1050×480 illustration widened the card
    /// past the viewport and shifted the entire screen sideways. `Color.clear`
    /// accepts whatever it is proposed, so the frame below is authoritative and
    /// the image can only overflow visually, where `clipShape` catches it.
    @ViewBuilder
    private var artwork: some View {
        Group {
            switch Self.artwork(for: milestone.occasionCategory) {
            case .illustration(let name):
                Color.clear
                    .overlay {
                        Image(name)
                            .resizable()
                            .scaledToFill()
                    }
            case .placeholder:
                artworkPlaceholder
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: Self.artworkHeight)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
        .accessibilityHidden(true)
    }

    /// Shown only for the `default` occasion category, which ships no illustration.
    private var artworkPlaceholder: some View {
        LinearGradient(
            colors: [Theme.accent.opacity(0.28), Theme.accent.opacity(0.10)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay {
            Image(systemName: MilestonesViewModel.iconName(for: milestone.milestoneType))
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Theme.accent.opacity(0.55))
        }
    }

    // MARK: - Meta Row

    private var metaRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(Self.dateLabel(from: formattedDate))
                .knotFont(Theme.Typography.label)
                .tracking(0.8)
                .foregroundStyle(Theme.textSecondary)

            Spacer(minLength: 8)

            if let days = milestone.daysUntil {
                Text(MilestonesViewModel.daysUntilText(days))
                    .knotFont(Theme.Typography.label)
                    .foregroundStyle(Self.countdownColor(for: urgency))
                    .lineLimit(1)
                    .fixedSize()
            }
        }
    }

    // MARK: - Title

    /// `cardTitleSemibold` (20pt), not `sectionHeaderSemibold` (28pt): 28 is a
    /// *page* title scale, and at that size the headline competed with the
    /// artwork above it (then 200pt). The card-scale token keeps the semibold weight
    /// so the title still out-weights the meta row and the "For {partner}"
    /// footer, and lands on the same 20pt rung the rest of the app's card
    /// headings already use.
    private var title: some View {
        Text(milestone.milestoneName)
            .knotFont(Theme.Typography.cardTitleSemibold)
            .foregroundStyle(Theme.textPrimary)
            .lineLimit(2)
            .minimumScaleFactor(0.8)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Footer

    /// Three controls share this row and "For {partner}" is variable-length, so
    /// the button takes `.fixedSize()` + `.layoutPriority(1)` and the name gains
    /// a scale floor: the *name* compresses under pressure, never the button —
    /// the same anti-jank recipe `BudgetTierSliderCard` and `LoveLanguageCard`
    /// already use.
    private var footerRow: some View {
        HStack(spacing: 8) {
            PartnerInitialAvatar(name: partnerName, diameter: 22)

            Text("For \(partnerName)")
                .knotFont(Theme.Typography.label)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            Spacer(minLength: 8)

            // `.outline`, not `.primary`: a second pink fill would compete with
            // the countdown and the accent icon on this same row. `.secondary`
            // fills with `surfaceElevated`, which has almost no contrast against
            // the card's own surface (the reason the "Upcoming" count badge is
            // `.accent` rather than `.secondary`).
            if let action = onSeeDetails {
                KnotButton(
                    "See details",
                    variant: .outline,
                    size: .sm,
                    shape: .pill,
                    action: action
                )
                .fixedSize()
                .layoutPriority(1)
                .accessibilityLabel("See details for \(milestone.milestoneName)")
            }

            // The 34pt asset already carries the design's 5pt inset around a
            // 24pt icon, so no extra padding is applied here.
            if let action = onGetRecommendations {
                Button(action: action) {
                    Image("RecommendationBadge")
                        .renderingMode(.template)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 34, height: 34)
                        .foregroundStyle(Theme.accent)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Get recommendations for \(milestone.milestoneName)")
            }
        }
    }
}

// MARK: - Pure Helpers

extension MilestoneCard {

    /// Which image a card should render for a given occasion category.
    enum Artwork: Equatable {
        /// A bundled illustration asset name, ready for `Image(_:)`.
        case illustration(String)
        /// No illustration ships for this category — render the gradient fallback.
        case placeholder
    }

    /// Resolves the bundled occasion illustration for a category.
    ///
    /// Delegates to `OccasionCopy.illustrationName(for:)`, which slugifies the
    /// category and bundle-checks the asset — so an occasion added on the
    /// backend before its artwork lands degrades to the placeholder rather than
    /// rendering a broken image.
    static func artwork(for occasionCategory: String) -> Artwork {
        if let name = OccasionCopy.illustrationName(for: occasionCategory) {
            return .illustration(name)
        }
        return .placeholder
    }

    /// Uppercases the view model's "MMM d" date for the card's meta row
    /// ("Dec 25" → "DEC 25"), matching the design's letterspaced label.
    static func dateLabel(from formatted: String) -> String {
        formatted.uppercased()
    }

    /// The countdown's colour.
    ///
    /// The design renders every countdown in the accent pink, which is right for
    /// the far-out dates it shows. The timeline this card replaced carried a
    /// five-step urgency ramp, and dropping it entirely would lose a real signal
    /// — a milestone three days out should not read the same as one 175 days
    /// out. So only the two genuinely urgent tiers deviate, via the `Theme`
    /// status tokens (the old row used raw `.red` / `.orange`).
    static func countdownColor(for urgency: MilestoneUrgency) -> Color {
        switch urgency {
        case .critical: return Theme.statusError
        case .soon: return Theme.statusWarning
        case .upcoming, .planning, .distant: return Theme.accent
        }
    }
}

// MARK: - Partner Initial Avatar

/// A circular identity mark carrying the partner's first initial.
///
/// The app stores no partner photo at any layer, so this stands in for the
/// avatar in the design. It is decorative — there is nothing behind it to tap —
/// and is hidden from VoiceOver so it isn't announced as a control.
struct PartnerInitialAvatar: View {

    let name: String
    let diameter: CGFloat

    private var initial: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return "?" }
        return String(first).uppercased()
    }

    var body: some View {
        Circle()
            .fill(Theme.accent.opacity(0.14))
            .overlay {
                Circle()
                    .stroke(Theme.surfaceBorder, lineWidth: 1)
            }
            .overlay {
                Text(initial)
                    .font(.system(size: diameter * 0.44, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            }
            .frame(width: diameter, height: diameter)
            .accessibilityHidden(true)
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Milestone Cards") {
    ScrollView {
        VStack(spacing: 20) {
            MilestoneCard(
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
                formattedDate: "Dec 25",
                urgency: .distant,
                onSeeDetails: {},
                onGetRecommendations: {}
            )

            MilestoneCard(
                milestone: MilestoneItemResponse(
                    id: "2",
                    milestoneType: "custom",
                    milestoneName: "Our First Concert",
                    milestoneDate: "2000-03-02",
                    recurrence: "yearly",
                    budgetTier: "minor_occasion",
                    daysUntil: 12,
                    createdAt: "2026-07-04",
                    occasionCategory: "default"
                ),
                partnerName: "Jas",
                formattedDate: "Mar 2",
                urgency: .upcoming,
                onSeeDetails: {},
                onGetRecommendations: {}
            )
        }
        .padding(20)
    }
    .background(Theme.backgroundGradient.ignoresSafeArea())
}
#endif
