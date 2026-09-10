//
//  ForYouView.swift
//  Knot
//
//  Created on March 20, 2026.
//  The Journal tab — a header plus a card feed of upcoming milestones.
//

import SwiftUI

/// The Journal tab (labelled "Journal" in `KnotTabBar`; the type keeps its
/// original `ForYouView` name).
///
/// Layout:
/// - "YOUR JOURNAL" eyebrow + partner name + initial avatar
/// - "Just Because" recommendation card
/// - "Upcoming" header with a "View all" link into milestone management
/// - A `MilestoneCard` per upcoming milestone, whose footer carries two
///   destinations: a "See details" button opening `MilestoneDetailView` for that
///   event, and a recommendation icon button raising
///   `MilestoneRecommendationSheet` — which names the occasion and asks before
///   pushing `RecommendationsView`, since an unlabelled icon otherwise gives no
///   hint about what it is about to do
struct ForYouView: View {

    @State private var viewModel = ForYouViewModel()
    @State private var milestoneFormViewModel = MilestonesViewModel()

    /// Navigation destination for programmatic push.
    @State private var navigationDestination: RecommendationDestination?

    /// Presents the full milestone list (add / edit / delete) from "View all".
    @State private var showMilestoneManagement = false

    /// The event whose detail screen is open, set by a card's "See details".
    ///
    /// `MilestoneItemResponse` is already `Identifiable`, so this drives
    /// `.fullScreenCover(item:)` directly with no wrapper type.
    @State private var detailMilestone: MilestoneItemResponse?

    /// The event whose recommendation sheet is open, set by a card's
    /// recommendation icon. Drives `.sheet(item:)` on the same terms.
    @State private var sheetMilestone: MilestoneItemResponse?

    /// Set when the sheet's "Get recommendations" or the detail screen's "Get
    /// more ideas" is tapped, consumed by whichever presentation was open so the
    /// push happens after it is really gone.
    @State private var pendingIdeasMilestone: MilestoneItemResponse?

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.backgroundGradient.ignoresSafeArea()

                // Always render timelineContent so the "Surprise them today"
                // JustBecauseCard is tappable from the moment the screen
                // appears. The timeline section itself handles the loading
                // state inline. Previously this screen showed a bare
                // ProgressView for the first ~second of every visit, leaving
                // no tap target — the user experienced this as "buttons not
                // responding" until milestones finished loading.
                timelineContent
                    // The screen carries its own in-content header, so the
                    // navigation bar stays hidden and the content starts at the
                    // safe-area top.
                    //
                    // Scoped to the scroll content, NOT to the ZStack: the
                    // `.sheet` and `.fullScreenCover` below hang off the ZStack,
                    // and their own NavigationStack toolbars carry the only
                    // Cancel/Save and back affordances those screens have.
                    // Keeping the hidden-bar state off that chain means it
                    // cannot reach them.
                    .toolbar(.hidden, for: .navigationBar)
            }
            .navigationDestination(item: $navigationDestination) { destination in
                // No `.toolbar(...)` here on purpose. This used to restore the
                // bar unconditionally, because the hidden state above
                // propagates into the push and `RecommendationsView` relies on
                // the system back button. But an unconditional `.visible` at
                // the top of the destination's subtree also *outranks*
                // anything the destination declares about itself, which is
                // what kept the bar stuck on over the loading screen.
                // `RecommendationsView` now always declares its own visibility
                // (`navigationBarVisibility`), restoring the bar in every state
                // except the full-bleed loading screen.
                RecommendationsView(
                    milestoneId: destination.milestoneId,
                    milestoneContext: destination.context
                )
            }
            .task {
                await viewModel.loadData()
            }
            .sheet(isPresented: $milestoneFormViewModel.showAddSheet) {
                MilestoneFormSheet(viewModel: milestoneFormViewModel)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                    .onDisappear {
                        Task { await viewModel.refreshMilestones() }
                    }
            }
            .fullScreenCover(isPresented: $showMilestoneManagement) {
                MilestonesManagementView()
                    .onDisappear {
                        Task { await viewModel.refreshMilestones() }
                    }
            }
            // Both hang off the ZStack alongside the presentations above, NOT
            // off `timelineContent` — that subtree carries
            // `.toolbar(.hidden,…)`, which a presentation attached inside it
            // would inherit.
            //
            // Only one can be open at a time (they are raised by two different
            // controls on the same card), so both route their "give me ideas"
            // action through the same `showIdeas` / `pushPendingIdeas` pair.
            .fullScreenCover(item: $detailMilestone, onDismiss: pushPendingIdeas) { milestone in
                MilestoneDetailView(
                    milestone: milestone,
                    partnerName: viewModel.partnerName,
                    urgency: viewModel.urgencyLevel(for: milestone.daysUntil ?? 365),
                    onGetIdeas: { showIdeas(for: milestone) },
                    onDismiss: { detailMilestone = nil }
                )
            }
            .sheet(item: $sheetMilestone, onDismiss: pushPendingIdeas) { milestone in
                MilestoneRecommendationSheet(
                    milestone: milestone,
                    partnerName: viewModel.partnerName,
                    formattedDate: viewModel.formattedDate(milestone.milestoneDate),
                    onGetRecommendations: { showIdeas(for: milestone) },
                    onDismiss: { sheetMilestone = nil }
                )
            }
        }
    }

    // MARK: - Journal Content

    private var timelineContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                journalHeader

                // "Just Because" card
                JustBecauseCard(
                    partnerName: viewModel.partnerName,
                    onGenerate: {
                        navigationDestination = RecommendationDestination(
                            milestoneId: nil,
                            context: nil
                        )
                    }
                )

                // Timeline section
                if viewModel.isLoading && viewModel.milestones.isEmpty {
                    // Inline loading state — keeps the JustBecauseCard above
                    // tappable while milestones load.
                    HStack {
                        Spacer()
                        ProgressView()
                            .tint(Theme.accent)
                        Spacer()
                    }
                    .padding(.vertical, 40)
                } else if viewModel.milestones.isEmpty {
                    emptyTimeline
                } else {
                    milestoneTimeline
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 80)
        }
        .refreshable {
            await viewModel.refreshMilestones()
        }
    }

    // MARK: - Header

    /// Eyebrow + partner name + initial avatar.
    ///
    /// The avatar is a decorative identity mark — the app stores no partner
    /// photo at any layer, so `PartnerInitialAvatar` stands in for it.
    private var journalHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("YOUR JOURNAL")
                    .knotFont(Theme.Typography.label)
                    .tracking(1.2)
                    .foregroundStyle(Theme.textSecondary)

                Text(viewModel.partnerName)
                    .knotFont(Theme.Typography.onboardingHeader)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            Spacer(minLength: 12)

            PartnerInitialAvatar(name: viewModel.partnerName, diameter: 56)
        }
    }

    /// Rendered inline rather than via `KnotSectionHeader`, whose `subhead`
    /// style is DM Sans 17 — the design calls for the large Fraunces title
    /// paired with a trailing accent link. `KnotSectionHeader` is shared by
    /// ~10 other screens and is deliberately left untouched.
    private var upcomingHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            // Title + count read as one element to VoiceOver — a bare "3"
            // announced after "Upcoming" says nothing on its own.
            HStack(alignment: .center, spacing: 8) {
                Text("Upcoming")
                    .knotFont(Theme.Typography.sectionHeaderSemibold)
                    .foregroundStyle(Theme.textPrimary)

                // `.accent`, not `.secondary`: the secondary variant fills with
                // `surfaceElevated` (0.96 grey) on a 0.97 background, so the
                // pill is invisible and the number reads as stray text. Accent
                // gives it the same tinted-pill treatment as
                // `PartnerInitialAvatar`. Centred rather than baseline-aligned —
                // against a 28pt Fraunces title, matching baselines drops the
                // small pill below the title's midline.
                //
                // The count is free: `milestones` is the same array the feed
                // below renders, so the badge cannot disagree with it.
                KnotBadge("\(viewModel.milestones.count)", variant: .accent, size: .sm)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Self.upcomingAccessibilityLabel(count: viewModel.milestones.count))

            Spacer(minLength: 12)

            Button {
                showMilestoneManagement = true
            } label: {
                Text("View all")
                    .knotFont(Theme.Typography.cta)
                    .foregroundStyle(Theme.accent)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("View all milestones")
        }
    }

    /// VoiceOver label for the "Upcoming" header and its count badge.
    ///
    /// Pure and `static` so the singular/plural rule is testable without
    /// rendering the screen.
    static func upcomingAccessibilityLabel(count: Int) -> String {
        count == 1 ? "Upcoming, 1 milestone" : "Upcoming, \(count) milestones"
    }

    // MARK: - Milestone Feed

    private var milestoneTimeline: some View {
        VStack(alignment: .leading, spacing: 16) {
            upcomingHeader

            ForEach(viewModel.milestones, id: \.id) { milestone in
                let daysUntil = milestone.daysUntil ?? 365

                MilestoneCard(
                    milestone: milestone,
                    partnerName: viewModel.partnerName,
                    formattedDate: viewModel.formattedDate(milestone.milestoneDate),
                    urgency: viewModel.urgencyLevel(for: daysUntil),
                    onSeeDetails: { detailMilestone = milestone },
                    onGetRecommendations: { sheetMilestone = milestone }
                )
            }
        }
    }

    // MARK: - Recommendation Navigation

    /// The push target for an event's contextual recommendations. Shared by the
    /// sheet's "Get recommendations" CTA and the detail screen's "Get more
    /// ideas" so the two can never drift.
    private func recommendationDestination(
        for milestone: MilestoneItemResponse
    ) -> RecommendationDestination {
        RecommendationDestination(
            milestoneId: milestone.id,
            context: MilestoneDisplayContext(
                name: milestone.milestoneName,
                type: milestone.milestoneType,
                daysUntil: milestone.daysUntil ?? 365,
                partnerName: viewModel.partnerName,
                occasionType: viewModel.occasionType(for: milestone)
            )
        )
    }

    /// Closes whichever presentation asked for ideas, remembering that a push
    /// should follow. Nils both because only one is ever open — the sheet and
    /// the detail screen are raised by two different controls on the same card
    /// — so one helper serves both without the caller having to say which.
    ///
    /// The push lands on this screen's `NavigationStack`, which both
    /// presentations sit above, so the dismissal has to *finish* first — and it
    /// animates for a few hundred milliseconds. Hopping one runloop turn is
    /// nowhere near long enough and would drop the push; `pushPendingIdeas` runs
    /// from the presentation's own `onDismiss`, which fires when the dismissal
    /// actually completes.
    private func showIdeas(for milestone: MilestoneItemResponse) {
        pendingIdeasMilestone = milestone
        sheetMilestone = nil
        detailMilestone = nil
    }

    /// Pushes the recommendations the sheet or the detail screen asked for, once
    /// it has finished dismissing. A no-op when either was closed any other way.
    private func pushPendingIdeas() {
        guard let milestone = pendingIdeasMilestone else { return }
        pendingIdeasMilestone = nil
        navigationDestination = recommendationDestination(for: milestone)
    }

    // MARK: - Empty Timeline

    private var emptyTimeline: some View {
        KnotCard(padding: .lg, radius: Theme.Radius.xl) {
            emptyTimelineContent
        }
    }

    private var emptyTimelineContent: some View {
        VStack(spacing: 16) {
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 40))
                .foregroundStyle(Theme.textTertiary)

            Text("No milestones yet")
                .knotFont(Theme.Typography.cta)
                .foregroundStyle(Theme.textPrimary)

            Text("Add important dates like birthdays and anniversaries to get proactive reminders and personalized ideas.")
                .knotFont(Theme.Typography.label)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)

            KnotButton(
                "Add Your First Milestone",
                variant: .primary,
                size: .sm,
                shape: .pill,
                action: { milestoneFormViewModel.prepareAdd() }
            )
            .fixedSize()
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

// MARK: - Navigation Destination

/// Identifies a recommendation navigation target for programmatic push.
struct RecommendationDestination: Identifiable, Hashable {
    let id = UUID()
    let milestoneId: String?
    let context: MilestoneDisplayContext?

    static func == (lhs: RecommendationDestination, rhs: RecommendationDestination) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Milestone Display Context

/// Lightweight context passed to RecommendationsView when navigating from a milestone CTA.
struct MilestoneDisplayContext {
    let name: String
    let type: String
    let daysUntil: Int
    let partnerName: String
    let occasionType: String
}
