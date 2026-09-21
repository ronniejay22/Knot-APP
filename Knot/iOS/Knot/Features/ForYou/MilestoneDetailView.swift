//
//  MilestoneDetailView.swift
//  Knot
//
//  Created on September 6, 2026.
//  Journal tab — the destination behind a milestone card's "See details".
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

    var body: some View {
        ZStack {
            Theme.backgroundGradient.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    headerRow
                    // The hero and the meta card are shared with
                    // `RecentPicksSheet` (Step 19.63) so the two screens
                    // cannot drift.
                    MilestoneArtworkHero(milestone: milestone)
                    MilestoneMetaCard(milestone: milestone, partnerName: partnerName, urgency: urgency)
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

    // `fullDate(from:)` and `countdownText(for:)` moved to `MilestoneMetaCard`
    // with the card that renders them (Step 19.63).

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
