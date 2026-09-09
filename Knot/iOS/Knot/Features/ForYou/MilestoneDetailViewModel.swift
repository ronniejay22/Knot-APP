//
//  MilestoneDetailViewModel.swift
//  Knot
//
//  Journal tab — the saved ideas belonging to one event.
//

import Foundation
import SwiftData
import UIKit

/// Loads the recommendations the user saved for a single milestone.
///
/// Saves are attributed to an event by `RecommendationsViewModel`, which stamps
/// `SavedRecommendation.milestoneId` whenever the recommendations surface was
/// opened with milestone context (the Journal card's idea button, or a milestone
/// push tap-through). Everything saved elsewhere carries a `nil` milestone and
/// never appears here.
@Observable
@MainActor
final class MilestoneDetailViewModel {

    /// Ideas saved for this event, newest first.
    var savedIdeas: [SavedRecommendation] = []

    /// Backend client for the merchant-open learning signal.
    private let service: RecommendationService

    init(service: RecommendationService = RecommendationService()) {
        self.service = service
    }

    /// Loads the saved ideas for one milestone.
    ///
    /// Filters in Swift rather than with a `#Predicate`. SwiftData predicates
    /// over an optional `String` are unreliable, and the saved set is small
    /// enough that `SavedViewModel` already fetches it unbounded — so the cost
    /// of reading all rows is one the app is paying anyway.
    ///
    /// The `Task.yield()` before the fetch is the Step 18.18 rule: `ModelContext`
    /// is main-actor bound, so a fetch in the same render tick as first appear
    /// stalls hit testing. Yielding lets SwiftUI finish its layout pass first.
    func load(milestoneId: String, modelContext: ModelContext) async {
        await Task.yield()

        let descriptor = FetchDescriptor<SavedRecommendation>(
            sortBy: [SortDescriptor(\.savedAt, order: .reverse)]
        )

        do {
            savedIdeas = try modelContext
                .fetch(descriptor)
                .filter { $0.milestoneId == milestoneId }
        } catch {
            print("[Knot] MilestoneDetailViewModel: Failed to load saved ideas — \(error)")
        }
    }

    /// Removes a saved idea, dropping it from this event and from the Saved tab.
    ///
    /// Mirrors `SavedViewModel.deleteSavedRecommendation` — the saved library is
    /// one store, so "remove" here is the same delete the Saved tab performs,
    /// not a detach that would leave an orphaned row the user can't see.
    func remove(_ saved: SavedRecommendation, modelContext: ModelContext) {
        let removedId = saved.recommendationId
        modelContext.delete(saved)
        try? modelContext.save()
        savedIdeas.removeAll { $0.recommendationId == removedId }
    }

    /// Opens the merchant/booking page from a saved idea's detail view.
    ///
    /// Mirrors `SavedViewModel.openMerchant` — the same detail page, opened over
    /// the same kind of local snapshot. `RecommendationDetailView` only shows
    /// the "Open in {merchant}" CTA for a real, non-search link, so the URL can
    /// be opened directly here. The `"selected"` signal is best-effort.
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
