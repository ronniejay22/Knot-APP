//
//  MilestoneDetailView.swift
//  Knot
//
//  Created on September 6, 2026.
//  Journal tab — the destination behind a milestone card's "See details".
//
//  Implements Figma node 579:421 (`christmas-detail`): a back/title header, the
//  occasion hero, a three-column meta card (date / countdown / recipient), and
//  the ideas saved for this event, with a CTA back into its recommendations.
//
//  Two deliberate deviations from the comp, both recorded in progress.md:
//  the `⋯` more button is omitted (edit and delete already live in
//  `MilestonesManagementView`, and a menu with nothing behind it is worse than
//  no menu), and the comp's "Gift Ideas" / "Add gift idea" wording is replaced
//  with "Saved ideas" / "Get more ideas" — saved items can be dates,
//  experiences or Knot Originals, and the button opens the recommendation flow
//  rather than a manual entry form.
//

import SwiftUI
import SwiftData
import LucideIcons

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

                    // Last element of the scroll, as in the comp — not a pinned
                    // bottom bar. A `safeAreaInset` here floated the pill over
                    // the cards with nothing behind it, so they bled through.
                    KnotButton(
                        "Get more ideas",
                        variant: .primary,
                        size: .lg,
                        shape: .pill,
                        action: onGetIdeas
                    )
                    .padding(.top, 4)
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
            KnotIconButton(icon: Lucide.arrowLeft, variant: .ghost, size: .md, action: onDismiss)
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
                Image(uiImage: Lucide.bookmark)
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 32, height: 32)
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

// MARK: - Saved Idea Card

/// One saved idea, mirroring the comp's `Gift Card Item`: photo, title + price,
/// note, then a "SAVED" tag opposite a control that removes it.
private struct SavedIdeaCard: View {

    let saved: SavedRecommendation
    let onOpen: @MainActor () -> Void
    let onRemove: @MainActor () -> Void

    private static let imageHeight: CGFloat = 110

    var body: some View {
        KnotCard(padding: .md, radius: Theme.Radius.xl) {
            VStack(alignment: .leading, spacing: 12) {
                image
                titleRow
                notes

                Divider()
                    .overlay(Theme.surfaceBorder)

                actionsRow
            }
        }
        // `.onTapGesture` rather than a wrapping `Button` so the remove control
        // inside keeps hit-testing (the Step 19.9 pattern from `SavedView`).
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        .accessibilityElement(children: .contain)
    }

    /// The bundled per-type photo is an always-present base beneath the remote
    /// image, so a card is never blank in any `AsyncImage` phase — the Step
    /// 19.13 rule. No gradient fallbacks on recommendation surfaces.
    private var image: some View {
        RecommendationFallbackImage(recommendationType: saved.recommendationType)
            .overlay {
                if let urlString = saved.imageURL, let url = URL(string: urlString) {
                    AsyncImage(url: url) { phase in
                        if case .success(let remote) = phase {
                            Color.clear
                                .overlay { remote.resizable().scaledToFill() }
                                .clipped()
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: Self.imageHeight)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
            .accessibilityHidden(true)
    }

    private var titleRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(saved.title)
                .knotFont(Theme.Typography.cta)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            Spacer(minLength: 8)

            if let priceCents = saved.priceCents {
                Text(RecommendationCard.formattedPrice(cents: priceCents, currency: saved.currency))
                    .knotFont(Theme.Typography.cta)
                    .foregroundStyle(Theme.accent)
                    .lineLimit(1)
                    .fixedSize()
                    .layoutPriority(1)
            }
        }
    }

    @ViewBuilder
    private var notes: some View {
        if let text = saved.descriptionText, !text.isEmpty {
            Text(text)
                .knotFont(Theme.Typography.bodySmall)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var actionsRow: some View {
        HStack {
            KnotBadge("SAVED", variant: .accent, size: .sm)

            Spacer(minLength: 8)

            Button(action: onRemove) {
                Image(uiImage: Lucide.bookmarkCheck)
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 20, height: 20)
                    .foregroundStyle(Theme.accent)
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(saved.title) from saved ideas")
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
