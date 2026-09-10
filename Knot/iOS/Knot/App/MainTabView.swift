//
//  MainTabView.swift
//  Knot
//
//  Created on February 26, 2026.
//  Bottom tab bar navigation — segments Journal, Saved, and Profile.
//

import SwiftUI

/// Cross-cutting visibility of the app's bottom tab chrome.
///
/// `KnotTabBar` is a custom bar mounted by `MainTabView` via `.safeAreaInset`,
/// so there is no `.toolbar(.hidden, for: .tabBar)` to reach it — that API only
/// governs a SwiftUI `TabView`. A pushed screen that needs the whole viewport
/// therefore has to tell `MainTabView` to stand down, and the signal has to
/// travel *up* from inside a `navigationDestination`, which is exactly the
/// direction `safeAreaInset` already fails to cross (see the clearance comment
/// in `RecommendationsView`). Environment flows *down* reliably, so the owner
/// publishes this object and the pushed screen mutates it.
///
/// Deliberately absent from the environment in the two hosts that have no tab
/// bar — the full-screen recommendation cover and onboarding — which is why
/// every reader binds it as an optional and no-ops when it is missing.
@MainActor
@Observable
final class AppChrome {
    /// Hides `KnotTabBar` and gives its safe-area inset back to the content.
    var isTabBarHidden = false
}

/// Root tab container for the authenticated + onboarded state.
///
/// Sits between `ContentView`'s auth routing and the individual tab views.
/// Hosts the `NetworkMonitor` and injects it into the environment so all
/// tabs can access connectivity state.
///
/// Uses a custom `KnotTabBar` mounted via `.safeAreaInset(edge: .bottom)`
/// over a `ZStack` that keeps all three destinations alive (matching
/// `TabView`'s default of preserving each tab's view-tree across switches).
struct MainTabView: View {
    @State private var selectedTab: AppTab = .journal
    @State private var networkMonitor = NetworkMonitor()
    @State private var chrome = AppChrome()

    enum AppTab: Int, Hashable {
        case journal = 0
        case saved = 1
        case profile = 2
    }

    private var tabBarItems: [KnotTabBar<AppTab>.Item] {
        [
            .init(id: .journal, title: "Journal", systemImage: "book"),
            .init(id: .saved,   title: "Saved",   systemImage: "bookmark"),
            .init(id: .profile, title: "Profile", systemImage: "person.crop.circle"),
        ]
    }

    var body: some View {
        ZStack {
            tabContent(.journal) { ForYouView() }
            tabContent(.saved)   { SavedView() }
            tabContent(.profile) { SettingsView(isTabEmbedded: true) }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            // Conditional rather than merely transparent: a hidden bar must
            // also give its inset back, or a full-bleed screen keeps a ~97pt
            // dead strip along the bottom.
            if !chrome.isTabBarHidden {
                KnotTabBar(selection: $selectedTab, items: tabBarItems)
                    .transition(.move(edge: .bottom))
            }
        }
        .animation(Theme.Motion.standard, value: chrome.isTabBarHidden)
        .environment(networkMonitor)
        .environment(chrome)
    }

    @ViewBuilder
    private func tabContent<Content: View>(
        _ tab: AppTab,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let isActive = selectedTab == tab
        content()
            .opacity(isActive ? 1 : 0)
            .allowsHitTesting(isActive)
            .accessibilityHidden(!isActive)
    }
}
