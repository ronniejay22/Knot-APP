//
//  KnotApp.swift
//  Knot
//
//  Created on February 3, 2026.
//  Relational Excellence on Autopilot.
//

import SwiftUI
import SwiftData

@main
struct KnotApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            PartnerVaultLocal.self,
            HintLocal.self,
            MilestoneLocal.self,
            RecommendationLocal.self,
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
        }
        .modelContainer(sharedModelContainer)
    }
}
