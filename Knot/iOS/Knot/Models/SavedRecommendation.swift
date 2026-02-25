//
//  SavedRecommendation.swift
//  Knot
//
//  Created on February 11, 2026.
//  Step 6.6: SwiftData model for locally saved recommendations.
//  Step 14.6: Made externalURL optional for Knot Originals. Added isIdea + contentSectionsData.
//

import Foundation
import SwiftData

/// Local SwiftData model for saved recommendations.
///
/// Stores recommendations the user explicitly saved from the Choice-of-Three UI
/// for later reference. Each saved recommendation captures a snapshot of the
/// recommendation data at save time (title, price, URL, etc.) so it remains
/// accessible even if the backend recommendation is later removed.
///
/// Surfaced on the Home screen in the "Saved" section between the Recommendations
/// button and Recent Hints.
@Model
final class SavedRecommendation {
    /// The recommendation ID from the backend (for deduplication).
    @Attribute(.unique) var recommendationId: String

    /// Type of recommendation: "gift", "experience", or "date".
    var recommendationType: String

    /// Display title (e.g., "Ceramic Pottery Class for Two").
    var title: String

    /// Short description shown on the recommendation card (nullable).
    var descriptionText: String?

    /// URL to the merchant/booking page for purchase handoff.
    /// NULL for Knot Originals (ideas) which have no external link.
    var externalURL: String?

    /// Price in cents (e.g., 4999 = $49.99). NULL if price is unknown.
    var priceCents: Int?

    /// Currency code (e.g., "USD").
    var currency: String

    /// Name of the merchant or venue (nullable).
    var merchantName: String?

    /// URL to the hero image for the recommendation card (nullable).
    var imageURL: String?

    /// Whether this is a Knot Original (AI-generated idea with no external link).
    var isIdea: Bool

    /// Serialized JSON content sections for Knot Originals (offline reading).
    /// Decode as `[IdeaContentSection]` when displaying the idea detail view.
    var contentSectionsData: Data?

    /// Timestamp when the user saved this recommendation.
    var savedAt: Date

    init(
        recommendationId: String,
        recommendationType: String,
        title: String,
        descriptionText: String? = nil,
        externalURL: String? = nil,
        priceCents: Int? = nil,
        currency: String = "USD",
        merchantName: String? = nil,
        imageURL: String? = nil,
        isIdea: Bool = false,
        contentSectionsData: Data? = nil,
        savedAt: Date = Date()
    ) {
        self.recommendationId = recommendationId
        self.recommendationType = recommendationType
        self.title = title
        self.descriptionText = descriptionText
        self.externalURL = externalURL
        self.priceCents = priceCents
        self.currency = currency
        self.merchantName = merchantName
        self.imageURL = imageURL
        self.isIdea = isIdea
        self.contentSectionsData = contentSectionsData
        self.savedAt = savedAt
    }
}
