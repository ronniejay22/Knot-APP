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
    @State private var deepLinkHandler = DeepLinkHandler()

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
            ContentView()
                .preferredColorScheme(.dark)
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
}
