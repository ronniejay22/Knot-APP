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
        default:
            EmptyView()
        }
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
