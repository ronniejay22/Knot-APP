//
//  MilestoneDetailView.swift
//  Knot
//
//  Created on September 6, 2026.
//  Home tab — the destination behind a milestone card's "See details".
//
//  Implements Figma node 579:421 (`christmas-detail`): a back/title header, the
//  occasion hero, a three-column meta card (date / countdown / recipient), and
//  the ideas saved for this event. The only route back into its recommendations
//  is the empty state's "Get ideas" button — the full-width "Get more ideas"
//  pill that used to close the scroll was removed as redundant with it.
//
//  Two deliberate deviations from the comp, both recorded in progress.md:
//  the `⋯` more button is omitted (edit and delete already live in
//  `MilestonesManagementView`, and a menu with nothing behind it is worse than
//  no menu), and the comp's "Gift Ideas" / "Add gift idea" wording is replaced
//  with "Saved ideas" / "Get ideas" — saved items can be dates, experiences or
//  Knot Originals, and the button opens the recommendation flow rather than a
//  manual entry form.
//
//  Each saved idea renders through the shared `SavedIdeaCard`
//  (Features/Saved/), which the Saved tab uses too.
//

import SwiftUI
import SwiftData

/// A single Journal event's own screen.
struct MilestoneDetailView: View {

    let milestone: MilestoneItemResponse
    let partnerName: String
    /// Urgency tier for the countdown's colour, computed by `ForYouViewModel`.
    let urgency: MilestoneUrgency
    /// Opens this event's contextual recommendations. The host dismisses this
    /// screen first — the Journal pushes the recommendations surface onto its
    /// own navigation stack, which this cover sits above.
    let onGetIdeas: @MainActor () -> Void
    let onDismiss: @MainActor () -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = MilestoneDetailViewModel()

    /// The saved idea whose full detail page is open.
    @State private var selectedDetailItem: RecommendationItemResponse?

    /// Matches `MilestoneCard.artworkHeight`'s reasoning — the occasion
    /// illustrations are 1050×480, so a hero this tall keeps the crop near
    /// their native ratio.
    private static let artworkHeight: CGFloat = 140

    var body: some View {
        ZStack {
            Theme.backgroundGradient.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    headerRow
                    artwork
                    metaCard
                    savedIdeasSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 40)
            }
        }
        .task {
            await viewModel.load(milestoneId: milestone.id, modelContext: modelContext)
        }
        // Reuses the same detail page the For You feed and Saved tab open,
        // rebuilt from the local snapshot (Step 19.9). `partnerName` is nil
        // because a snapshot stores no personalization note — the detail view
        // hides that block, and the "Where" row, when the fields are absent.
        .fullScreenCover(item: $selectedDetailItem) { item in
            RecommendationDetailView(
                item: item,
                partnerName: nil,
                isSaved: true,
                onOpenMerchant: { viewModel.openMerchant(item) },
                onSave: {},
                onDismiss: { selectedDetailItem = nil }
            )
        }
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack(spacing: 12) {
            KnotIconButton(icon: .arrowBackOutlined, variant: .ghost, size: .md, action: onDismiss)
                .accessibilityLabel("Back")

            Text(milestone.milestoneName)
                .knotFont(Theme.Typography.sectionHeaderSemibold)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            Spacer(minLength: 0)
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
                    KnotIconView(MilestonesViewModel.icon(for: milestone.milestoneType), size: 62)
                        .foregroundStyle(Theme.accent.opacity(0.55))
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: Self.artworkHeight)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.xl, style: .continuous))
        .accessibilityHidden(true)
    }

    // MARK: - Meta Card

    /// Date · countdown · recipient, in three divider-separated columns.
    private var metaCard: some View {
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

    // MARK: - Saved Ideas

    private var savedIdeasSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            savedIdeasHeader

            if viewModel.savedIdeas.isEmpty {
                emptyIdeas
            } else {
                ForEach(viewModel.savedIdeas, id: \.recommendationId) { saved in
                    SavedIdeaCard(
                        saved: saved,
                        onOpen: { selectedDetailItem = saved.toDetailItem() },
                        onRemove: { viewModel.remove(saved, modelContext: modelContext) }
                    )
                }
            }
        }
    }

    private var savedIdeasHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Saved ideas")
                .knotFont(Theme.Typography.sectionHeaderSemibold)
                .foregroundStyle(Theme.textPrimary)

            Spacer(minLength: 12)

            // The count reads off the same array the list renders, so it can
            // never disagree with what is on screen.
            if !viewModel.savedIdeas.isEmpty {
                Text("\(viewModel.savedIdeas.count) saved")
                    .knotFont(Theme.Typography.label)
                    .foregroundStyle(Theme.accent)
                    .fixedSize()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.savedIdeasAccessibilityLabel(count: viewModel.savedIdeas.count))
    }

    private var emptyIdeas: some View {
        KnotCard(padding: .lg, radius: Theme.Radius.xl) {
            VStack(spacing: 12) {
                KnotIconView(.bookmarkBorder, size: 32)
                    .foregroundStyle(Theme.textTertiary)

                Text("No ideas saved yet")
                    .knotFont(Theme.Typography.cta)
                    .foregroundStyle(Theme.textPrimary)

                Text("Ideas you save from \(milestone.milestoneName)'s recommendations show up here.")
                    .knotFont(Theme.Typography.label)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)

                KnotButton(
                    "Get ideas",
                    variant: .primary,
                    size: .sm,
                    shape: .pill,
                    action: onGetIdeas
                )
                .fixedSize()
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
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

    /// The countdown column's value, never blank.
    ///
    /// `MilestonesViewModel.daysUntilText(nil)` returns "" — which the backend
    /// genuinely produces for a past one-time milestone — and an empty string
    /// under a "COUNTDOWN" label reads as a rendering failure.
    static func countdownText(for daysUntil: Int?) -> String {
        let text = MilestonesViewModel.daysUntilText(daysUntil)
        return text.isEmpty ? "—" : text
    }

    /// VoiceOver label for the section header and its count.
    ///
    /// Pure and `static` so the singular/plural rule is testable without
    /// rendering the screen — the same treatment `ForYouView`'s "Upcoming"
    /// count badge gets.
    static func savedIdeasAccessibilityLabel(count: Int) -> String {
        switch count {
        case 0: return "Saved ideas, none yet"
        case 1: return "Saved ideas, 1 saved"
        default: return "Saved ideas, \(count) saved"
        }
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
        partnerName: "Jasmine",
        urgency: .distant,
        onGetIdeas: {},
        onDismiss: {}
    )
}
#endif
