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

    /// Title of the date plan most recently marked done, used to drive the
    /// celebratory "reward moment" overlay. Cleared once the overlay dismisses.
    var lastCelebratedTitle: String?

    /// Backend client for recording the post-date "rated" learning signal.
    private let service: RecommendationService

    init(service: RecommendationService = RecommendationService()) {
        self.service = service
    }

    /// Active items still to be done — shown in the "Saved" section.
    var activeItems: [SavedRecommendation] {
        savedRecommendations.filter { !$0.isCompleted }
    }

    /// Completed date plans — shown in the "Moments" section, newest first.
    var completedItems: [SavedRecommendation] {
        savedRecommendations
            .filter { $0.isCompleted }
            .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
    }

    /// Loads all saved recommendations from SwiftData.
    ///
    /// `ModelContext.fetch` is bound to the main actor, but yielding once before
    /// the fetch lets SwiftUI complete its initial layout pass so the tab feels
    /// responsive to taps the moment it appears. Without the yield, the fetch
    /// runs in the same render tick as the view's first appear and can stall
    /// hit testing for hundreds of milliseconds on a real device.
    func loadSavedRecommendations(modelContext: ModelContext) async {
        await Task.yield()

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

    /// Marks a saved date plan as done with a post-date reflection.
    ///
    /// Persists the completion locally (moving the item from "Saved" to
    /// "Moments"), triggers the celebratory reward overlay, and fires a
    /// best-effort `"rated"` feedback signal so date plans finally feed the
    /// recommendation-learning loop (mirrors the fire-and-forget pattern used
    /// elsewhere in the recommendations flow).
    func markCompleted(
        _ saved: SavedRecommendation,
        rating: Int,
        note: String?,
        modelContext: ModelContext
    ) {
        saved.completedAt = Date()
        saved.rating = rating
        saved.reflectionNote = note
        try? modelContext.save()

        lastCelebratedTitle = saved.title

        let id = saved.recommendationId
        let service = self.service
        Task {
            // Re-fetch so the item moves from the Saved section to Moments.
            await loadSavedRecommendations(modelContext: modelContext)
            try? await service.recordFeedback(
                recommendationId: id,
                action: "rated",
                rating: rating,
                feedbackText: note
            )
        }
    }

    /// Clears the reward overlay after it has been shown.
    func clearCelebration() {
        lastCelebratedTitle = nil
    }
}
