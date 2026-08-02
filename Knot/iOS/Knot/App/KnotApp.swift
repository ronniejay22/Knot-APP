//
//  KnotApp.swift
//  Knot
//
//  Created on February 3, 2026.
//  Relational Excellence on Autopilot.
//

import GoogleSignIn
import SwiftUI
import SwiftData
import Supabase

@main
struct KnotApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    // The shared instance (not a fresh one) so AppDelegate's notification-tap
    // writes land on the same object the SwiftUI environment observes.
    @State private var deepLinkHandler = DeepLinkHandler.shared

    init() {
        Theme.registerFonts()
    }

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            PartnerVaultLocal.self,
            HintLocal.self,
            MilestoneLocal.self,
            RecommendationLocal.self,
            SavedRecommendation.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            rootView
                // Knot is a light-appearance app. The former Settings "Dark
                // Mode" toggle (and its `appThemeMode` AppStorage) was removed,
                // so the scheme is pinned to light app-wide.
                .preferredColorScheme(.light)
                .environment(deepLinkHandler)
                .onOpenURL { url in
                    // Google Sign-In callback (reversed client ID scheme)
                    if GIDSignIn.sharedInstance.handle(url) {
                        return
                    }
                    // Supabase auth callback (magic link, etc.)
                    if url.scheme == "com.ronniejay.knot" && url.host == "login-callback" {
                        Task {
                            try? await SupabaseManager.client.auth.session(from: url)
                        }
                    } else {
                        deepLinkHandler.handleURL(url)
                    }
                }
        }
        .modelContainer(sharedModelContainer)
    }

    /// App root. Normally `ContentView` (auth → onboarding → home router). In
    /// DEBUG builds, the `-uiTestOnboarding` launch argument renders the
    /// onboarding flow directly so `PRScreenshotTests` can capture onboarding
    /// screens without a live Supabase session. Never compiled into release.
    /// (Other screenshot targets use `UITestScreenshotHarness` via ContentView.)
    @ViewBuilder
    private var rootView: some View {
        #if DEBUG
        if CommandLine.arguments.contains("-uiTestOnboarding") {
            OnboardingContainerView(onComplete: {})
        } else {
            ContentView()
        }
        #else
        ContentView()
        #endif
    }
}
