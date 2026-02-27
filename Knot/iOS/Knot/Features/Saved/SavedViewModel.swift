//
//  SavedViewModel.swift
//  Knot
//
//  Created on February 26, 2026.
//  Manages saved recommendations data for the Saved tab.
//

import Foundation
import SwiftData

/// Manages data for the Saved tab.
///
/// Loads all saved recommendations from SwiftData (no limit) and provides
/// delete functionality. Replaces the saved recommendation methods that
/// were previously in `HomeViewModel`.
@Observable
@MainActor
final class SavedViewModel {

    /// All saved recommendations, sorted by most recently saved.
    var savedRecommendations: [SavedRecommendation] = []

    /// Loads all saved recommendations from SwiftData.
    func loadSavedRecommendations(modelContext: ModelContext) {
        let descriptor = FetchDescriptor<SavedRecommendation>(
            sortBy: [SortDescriptor(\.savedAt, order: .reverse)]
        )

        do {
            savedRecommendations = try modelContext.fetch(descriptor)
        } catch {
            print("[Knot] SavedViewModel: Failed to load saved recommendations — \(error)")
        }
    }

    /// Deletes a saved recommendation from SwiftData and the local array.
    func deleteSavedRecommendation(_ saved: SavedRecommendation, modelContext: ModelContext) {
        modelContext.delete(saved)
        try? modelContext.save()
        savedRecommendations.removeAll { $0.recommendationId == saved.recommendationId }
    }
}
