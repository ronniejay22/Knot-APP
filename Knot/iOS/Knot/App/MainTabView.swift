//
//  MainTabView.swift
//  Knot
//
//  Created on February 26, 2026.
//  Bottom tab bar navigation — segments For You, Hints, Saved, and Profile.
//

import SwiftUI
import LucideIcons

/// Root tab container for the authenticated + onboarded state.
///
/// Sits between `ContentView`'s auth routing and the individual tab views.
/// Hosts the `NetworkMonitor` and injects it into the environment so all
/// tabs can access connectivity state.
struct MainTabView: View {
    @State private var selectedTab: AppTab = .forYou
    @State private var networkMonitor = NetworkMonitor()

    enum AppTab: Int {
        case forYou = 0
        case hints = 1
        case saved = 2
        case profile = 3
    }

    init() {
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(Theme.backgroundBottom)

        let normalColor = UIColor(Theme.textTertiary)
        appearance.stackedLayoutAppearance.normal.iconColor = normalColor
        appearance.stackedLayoutAppearance.normal.titleTextAttributes = [
            .foregroundColor: normalColor
        ]

        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            RecommendationsView(isTabEmbedded: true)
                .tabItem {
                    Label {
                        Text("For You")
                    } icon: {
                        Image(uiImage: Lucide.sparkles)
                            .renderingMode(.template)
                    }
                }
                .tag(AppTab.forYou)

            HintsTabView()
                .tabItem {
                    Label {
                        Text("Hints")
                    } icon: {
                        Image(uiImage: Lucide.lightbulb)
                            .renderingMode(.template)
                    }
                }
                .tag(AppTab.hints)

            SavedView()
                .tabItem {
                    Label {
                        Text("Saved")
                    } icon: {
                        Image(uiImage: Lucide.bookmark)
                            .renderingMode(.template)
                    }
                }
                .tag(AppTab.saved)

            SettingsView(isTabEmbedded: true)
                .tabItem {
                    Label {
                        Text("Profile")
                    } icon: {
                        Image(uiImage: Lucide.user)
                            .renderingMode(.template)
                    }
                }
                .tag(AppTab.profile)
        }
        .tint(Theme.accent)
        .environment(networkMonitor)
    }
}
