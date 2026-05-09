//
//  MainTabView.swift
//  Knot
//
//  Created on February 26, 2026.
//  Bottom tab bar navigation — segments For You, Saved, and Profile.
//

import SwiftUI

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
    @State private var selectedTab: AppTab = .forYou
    @State private var networkMonitor = NetworkMonitor()

    enum AppTab: Int, Hashable {
        case forYou = 0
        case saved = 1
        case profile = 2
    }

    private var tabBarItems: [KnotTabBar<AppTab>.Item] {
        [
            .init(id: .forYou,  title: "For You", systemImage: "sparkles"),
            .init(id: .saved,   title: "Saved",   systemImage: "bookmark"),
            .init(id: .profile, title: "Profile", systemImage: "person.crop.circle"),
        ]
    }

    var body: some View {
        ZStack {
            tabContent(.forYou)  { ForYouView() }
            tabContent(.saved)   { SavedView() }
            tabContent(.profile) { SettingsView(isTabEmbedded: true) }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            KnotTabBar(selection: $selectedTab, items: tabBarItems)
        }
        .environment(networkMonitor)
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
