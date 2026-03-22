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
    @Environment(\.colorScheme) private var colorScheme

    enum AppTab: Int {
        case forYou = 0
        case hints = 1
        case saved = 2
        case profile = 3
    }

    init() {
        Self.updateTabBarAppearance()
    }

    static func updateTabBarAppearance() {
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
            ForYouView()
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
        .onChange(of: colorScheme) { _, _ in
            Self.updateTabBarAppearance()
            // Force the existing tab bar to pick up the new appearance.
            // UITabBar.appearance() only affects new instances, so we must
            // also update live ones after a theme change.
            let appearance = UITabBar.appearance().standardAppearance
            let edgeAppearance = UITabBar.appearance().scrollEdgeAppearance
            for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
                for window in scene.windows {
                    Self.findTabBars(in: window).forEach { tabBar in
                        tabBar.standardAppearance = appearance
                        tabBar.scrollEdgeAppearance = edgeAppearance
                    }
                }
            }
        }
    }

    /// Recursively finds all `UITabBar` instances in a view hierarchy.
    private static func findTabBars(in view: UIView) -> [UITabBar] {
        var results: [UITabBar] = []
        if let tabBar = view as? UITabBar {
            results.append(tabBar)
        }
        for subview in view.subviews {
            results.append(contentsOf: findTabBars(in: subview))
        }
        return results
    }
}
