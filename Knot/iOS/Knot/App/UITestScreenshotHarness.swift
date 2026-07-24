//
//  UITestScreenshotHarness.swift
//  Knot
//
//  Test-only launch seam for the Autonomous Feature Workflow's PR screenshot
//  step (see Knot/CLAUDE.md and iOS/scripts/capture-ui-screenshot.sh).
//
//  Several screens — notably the onboarding flow — sit behind a real
//  authenticated Supabase session, so a cold-launch UI test can't deterministically
//  reach them to take a screenshot. When the app is launched with
//  `-uiTestScreenshot <key>`, ContentView renders that screen standalone with
//  representative state, bypassing auth/onboarding gating, so the screenshot test
//  can capture the exact changed view. It has no effect on normal launches.
//

import SwiftUI
import SwiftData

#if DEBUG
enum UITestScreenshotHarness {
    /// The screen key passed via `-uiTestScreenshot <key>`, or `nil` on a normal launch.
    static var activeScreen: String? {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "-uiTestScreenshot"),
              index + 1 < args.count else {
            return nil
        }
        return args[index + 1]
    }

    /// The standalone view for a screen key. Unknown keys render nothing.
    /// `@MainActor`: builds SwiftUI views whose `@MainActor` view-models init on
    /// construction; only ever called from `ContentView.body` (already main-actor).
    @ViewBuilder
    @MainActor
    static func rootView(for key: String) -> some View {
        switch key {
        case "forYou":
            ForYouView()
        case "forYouTimeline":
            ForYouTimelineScreenshotHarnessView()
        case "interests":
            InterestsScreenshotHarnessView()
        case "recDetail":
            RecDetailScreenshotHarnessView()
        case "recDetailStale":
            RecDetailStaleLinkHarnessView()
        case "savedMoments":
            SavedMomentsScreenshotHarnessView()
        case "settings":
            // Profile/Settings screen standalone — proves the Appearance/Dark
            // Mode row is gone. `authViewModel` (injected by ContentView) and the
            // model container (from KnotApp's WindowGroup) are already in scope,
            // so no extra environment injection is needed. The view-model's async
            // email/notification loads no-op without a live session; the sections
            // still render.
            SettingsView(isTabEmbedded: true)
        case "forYouCard":
            ForYouCardScreenshotHarnessView()
        case "onboardingPaywall":
            OnboardingPaywallScreenshotHarnessView()
        default:
            EmptyView()
        }
    }
}

/// Renders the end-of-onboarding subscription paywall standalone so a screenshot
/// shows the live purchase CTA ("Start Free Trial") and trial copy. The paywall
/// normally appears only after a full authenticated onboarding run; this drops it
/// in directly with a fresh `SubscriptionManager` (products resolve from the local
/// `Knot.storekit` catalog when the scheme provides one, otherwise the cards show
/// their placeholder copy).
private struct OnboardingPaywallScreenshotHarnessView: View {
    var body: some View {
        OnboardingPaywallView(
            subscriptionManager: SubscriptionManager(),
            onContinue: {},
            onClose: {}
        )
    }
}

/// Renders the Saved tab seeded with one active purchasable (a merchant/price
/// row that previously carried the external-link icon — now removed), one active
/// date plan (showing the "We did this" reflection action), and one completed
/// date plan in the "Moments" section (showing its rating + reflection note).
/// SavedView normally reads from the app's SwiftData store; this injects an
/// isolated in-memory container with representative sample data so the
/// screenshot is deterministic.
@MainActor
private struct SavedMomentsScreenshotHarnessView: View {
    private let container: ModelContainer = {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        // Force-unwrap is acceptable in this DEBUG-only screenshot seam.
        let container = try! ModelContainer(for: SavedRecommendation.self, configurations: config)
        let context = container.mainContext

        // Active purchasable with a valid (non-search) merchant link — the card
        // type that used to show the open-link icon, proving it's now gone.
        context.insert(SavedRecommendation(
            recommendationId: "harness-purchasable",
            recommendationType: "experience",
            title: "Cooking Class: Thai Cuisine",
            descriptionText: "A hands-on evening class for two.",
            externalURL: "https://republiqueculinary.com/classes/thai",
            priceCents: 14000,
            merchantName: "Republique Culinary Classes",
            isIdea: false
        ))

        context.insert(SavedRecommendation(
            recommendationId: "harness-active",
            recommendationType: "date",
            title: "Sunset Picnic in the Park",
            descriptionText: "A low-key evening for two.",
            isIdea: true
        ))

        context.insert(SavedRecommendation(
            recommendationId: "harness-moment",
            recommendationType: "date",
            title: "Movie Night: Directors' Conversation",
            descriptionText: "A film + soundtrack deep-dive.",
            isIdea: true,
            completedAt: Date(timeIntervalSince1970: 1_700_000_000),
            rating: 5,
            reflectionNote: "We stayed up talking about the soundtrack for an hour."
        ))

        try? context.save()
        return container
    }()

    var body: some View {
        SavedView()
            .modelContainer(container)
    }
}

/// Renders the For You "Surprise them today" card standalone with a partner name, so a
/// screenshot shows the JustBecauseCard header (now without a leading icon) and the
/// "Get Recommendations" button (also without an icon). The full ForYouView normally sits
/// behind auth and a live backend milestone fetch, so this drops the changed card in
/// directly with representative state on the app's background.
private struct ForYouCardScreenshotHarnessView: View {
    var body: some View {
        JustBecauseCard(partnerName: "Jas", onGenerate: {})
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.top, 24)
            .background(Theme.backgroundGradient.ignoresSafeArea())
    }
}

/// Renders the For You "Upcoming" milestone timeline standalone with a handful of
/// sample milestones, so a screenshot shows each row's new trailing recommendation
/// icon button. The full ForYouView normally sits behind auth and a live backend
/// milestone fetch (which a cold screenshot launch can't deterministically seed),
/// so this composes the timeline directly with representative milestones and a
/// non-nil recommendation action on every row.
private struct ForYouTimelineScreenshotHarnessView: View {
    private static func sample(
        _ id: String, _ type: String, _ name: String, _ days: Int
    ) -> MilestoneItemResponse {
        MilestoneItemResponse(
            id: id,
            milestoneType: type,
            milestoneName: name,
            milestoneDate: "2026-12-25",
            recurrence: "yearly",
            budgetTier: nil,
            daysUntil: days,
            createdAt: "2026-07-04"
        )
    }

    // (milestone, formattedDate, urgency) — mirrors ForYouView's timeline inputs.
    private let entries: [(MilestoneItemResponse, String, MilestoneUrgency)] = [
        (sample("h1", "holiday", "Christmas", 175), "Dec 25", .distant),
        (sample("h2", "holiday", "New Year's Eve", 181), "Dec 31", .distant),
        (sample("h3", "birthday", "Jas's Birthday", 182), "Jan 1", .distant),
        (sample("h4", "holiday", "Valentine's Day", 226), "Feb 14", .distant),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                KnotSectionHeader<EmptyView>("Upcoming")
                    .padding(.bottom, 16)

                ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
                    TimelineEntryView(
                        milestone: entry.0,
                        partnerName: "Jas",
                        isLast: index == entries.count - 1,
                        urgency: entry.2,
                        formattedDate: entry.1,
                        onGetRecommendations: {}
                    )
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.backgroundGradient.ignoresSafeArea())
    }
}

/// Renders the recommendation detail for a bookable purchasable, so a screenshot
/// shows the "Open in <merchant>" CTA that opens a real, dedicated purchase page
/// (never a web search). The detail screen normally sits behind auth + a live
/// backend, so this bypasses both with representative sample data.
private struct RecDetailScreenshotHarnessView: View {
    var body: some View {
        RecommendationDetailView(
            item: PreviewRecommendations.bookablePurchasable,
            partnerName: "Ronnie",
            isSaved: false,
            onOpenMerchant: {},
            onSave: {},
            onShare: {},
            onDismiss: {}
        )
    }
}

/// Renders the recommendation detail for a purchasable whose stored link is a stale
/// Google-Shopping URL. The CTA must degrade to "Save to Library" (not "Open in …"),
/// proving the guard neutralizes a pre-fix link.
private struct RecDetailStaleLinkHarnessView: View {
    var body: some View {
        RecommendationDetailView(
            item: PreviewRecommendations.staleSearchLink,
            partnerName: "Ronnie",
            isSaved: false,
            onOpenMerchant: {},
            onSave: {},
            onShare: {},
            onDismiss: {}
        )
    }
}

/// Renders the onboarding interests screen with a partner name and a handful of
/// preselected interests, so a screenshot shows both selected (tinted) and
/// unselected rows. The harness never mutates the view model after building it,
/// so a plain `let` suffices.
@MainActor
private struct InterestsScreenshotHarnessView: View {
    private let viewModel: OnboardingViewModel = {
        let vm = OnboardingViewModel()
        vm.partnerName = "Alex"
        vm.selectedInterests = ["Travel", "Cooking", "Music", "Coffee", "Hiking"]
        return vm
    }()

    var body: some View {
        OnboardingInterestsView()
            .environment(viewModel)
            .background(Theme.backgroundGradient.ignoresSafeArea())
    }
}
#else
enum UITestScreenshotHarness {
    /// Release builds never expose the screenshot seam.
    static var activeScreen: String? { nil }

    @ViewBuilder
    static func rootView(for key: String) -> some View { EmptyView() }
}
#endif
