//
//  SavedRecommendation+Detail.swift
//  Knot
//
//  Bridges a locally-saved recommendation snapshot back into the detail-view DTO
//  so tapping a card on the Saved tab opens the same `RecommendationDetailView`
//  used by the For You feed.
//

import Foundation

extension SavedRecommendation {
    /// Rebuilds the detail-view DTO (`RecommendationItemResponse`) from this local
    /// snapshot.
    ///
    /// `SavedRecommendation` is an offline snapshot (Step 6.6) that carries only the
    /// fields shown on a card, so scoring / personalization / location fields are
    /// absent — `RecommendationDetailView` already hides the "Why Knot picked this"
    /// block and location row when those are empty, so the detail degrades cleanly.
    /// Structured Knot Original content is restored by decoding `contentSectionsData`,
    /// mirroring the encode in `RecommendationsViewModel.saveRecommendation`.
    func toDetailItem() -> RecommendationItemResponse {
        let sections: [IdeaContentSection]? = contentSectionsData.flatMap {
            try? JSONDecoder().decode([IdeaContentSection].self, from: $0)
        }

        return RecommendationItemResponse(
            id: recommendationId,
            recommendationType: recommendationType,
            title: title,
            description: descriptionText,
            priceCents: priceCents,
            currency: currency,
            externalUrl: externalURL,
            imageUrl: imageURL,
            merchantName: merchantName,
            isIdea: isIdea,
            contentSections: sections
        )
    }
}
