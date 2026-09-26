//
//  SavedViewModel.swift
//  Knot
//
//  Created on February 26, 2026.
//  Manages saved recommendations data for the Saved tab.
//

import Foundation
import SwiftData
import UIKit

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

    /// Backend client for recording the detail view's `"selected"` learning signal.
    private let service: RecommendationService

    init(service: RecommendationService = RecommendationService()) {
        self.service = service
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

    // MARK: - Detail Actions

    /// Opens the merchant/booking page for a saved recommendation from its detail view.
    ///
    /// Mirrors the Saved card's inline open-link button: `RecommendationDetailView`
    /// only shows the "Open in {merchant}" CTA for a real, non-search link, so we can
    /// open the URL directly here. Records a best-effort `"selected"` learning signal,
    /// matching the merchant-handoff behavior elsewhere in the app.
    func openMerchant(_ item: RecommendationItemResponse) {
        guard let urlString = item.externalUrl, let url = URL(string: urlString) else { return }
        UIApplication.shared.open(url)

        let service = self.service
        let itemId = item.id
        Task {
            try? await service.recordFeedback(
                recommendationId: itemId,
                action: "selected"
            )
        }
    }
}
