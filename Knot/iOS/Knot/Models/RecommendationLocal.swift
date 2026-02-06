//
//  RecommendationLocal.swift
//  Knot
//
//  Created on February 6, 2026.
//  SwiftData model mirroring the recommendations table for local storage.
//

import Foundation
import SwiftData

/// Local SwiftData model for Recommendations.
///
/// Mirrors the `recommendations` table in Supabase. Stores AI-generated
/// recommendations locally for fast display in the Choice-of-Three UI.
///
/// Database columns mapped:
/// - `id` → `remoteID` (UUID from Supabase)
/// - `vault_id` → `vaultID`
/// - `milestone_id` → `milestoneID` (nullable — "just because" recommendations)
/// - `recommendation_type` → `recommendationType` ("gift", "experience", "date")
/// - `title` → `title`
/// - `description` → `descriptionText`
/// - `external_url` → `externalURL`
/// - `price_cents` → `priceCents` (nullable, integer in cents)
/// - `merchant_name` → `merchantName`
/// - `image_url` → `imageURL`
/// - `created_at` → `createdAt`
///
/// Note: `description` is renamed to `descriptionText` to avoid conflict
/// with Swift's built-in `CustomStringConvertible.description`.
@Model
final class RecommendationLocal {
    /// The UUID from the Supabase `recommendations.id` column.
    var remoteID: UUID?

    /// The vault this recommendation was generated for.
    var vaultID: UUID?

    /// The milestone that triggered this recommendation (nullable).
    /// NULL for "just because" browsing recommendations.
    var milestoneID: UUID?

    /// Type of recommendation: "gift", "experience", or "date".
    var recommendationType: String

    /// Display title (e.g., "Ceramic Pottery Class for Two").
    var title: String

    /// Short description shown on the recommendation card (nullable).
    var descriptionText: String?

    /// URL to the merchant/booking page for purchase handoff (nullable).
    var externalURL: String?

    /// Price in cents (e.g., 4999 = $49.99). NULL if price is unknown.
    var priceCents: Int?

    /// Name of the merchant or venue (e.g., "Amazon", "Yelp") (nullable).
    var merchantName: String?

    /// URL to the hero image for the recommendation card (nullable).
    var imageURL: String?

    /// Timestamp when the recommendation was generated.
    var createdAt: Date?

    /// Local sync status with the Supabase backend.
    var syncStatusRaw: String

    /// Computed accessor for the sync status enum.
    var syncStatus: SyncStatus {
        get { SyncStatus(rawValue: syncStatusRaw) ?? .pendingUpload }
        set { syncStatusRaw = newValue.rawValue }
    }

    init(
        remoteID: UUID? = nil,
        vaultID: UUID? = nil,
        milestoneID: UUID? = nil,
        recommendationType: String,
        title: String,
        descriptionText: String? = nil,
        externalURL: String? = nil,
        priceCents: Int? = nil,
        merchantName: String? = nil,
        imageURL: String? = nil,
        createdAt: Date? = nil,
        syncStatus: SyncStatus = .pendingUpload
    ) {
        self.remoteID = remoteID
        self.vaultID = vaultID
        self.milestoneID = milestoneID
        self.recommendationType = recommendationType
        self.title = title
        self.descriptionText = descriptionText
        self.externalURL = externalURL
        self.priceCents = priceCents
        self.merchantName = merchantName
        self.imageURL = imageURL
        self.createdAt = createdAt
        self.syncStatusRaw = syncStatus.rawValue
    }
}
