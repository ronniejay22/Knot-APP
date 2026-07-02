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
    @ViewBuilder
    static func rootView(for key: String) -> some View {
        switch key {
        case "interests":
            InterestsScreenshotHarnessView()
        case "recDetail":
            RecDetailScreenshotHarnessView()
        case "recDetailStale":
            RecDetailStaleLinkHarnessView()
        case "savedMoments":
            SavedMomentsScreenshotHarnessView()
        default:
            EmptyView()
        }
    }
}

/// Renders the Saved tab seeded with one active date plan (showing the new
/// "We did this" reflection action) and one completed date plan in the new
/// "Moments" section (showing its rating + reflection note). SavedView normally
/// reads from the app's SwiftData store; this injects an isolated in-memory
/// container with representative sample data so the screenshot is deterministic.
private struct SavedMomentsScreenshotHarnessView: View {
    private let container: ModelContainer = {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        // Force-unwrap is acceptable in this DEBUG-only screenshot seam.
        let container = try! ModelContainer(for: SavedRecommendation.self, configurations: config)
        let context = container.mainContext

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
