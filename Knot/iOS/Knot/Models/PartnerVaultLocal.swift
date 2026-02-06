//
//  PartnerVaultLocal.swift
//  Knot
//
//  Created on February 6, 2026.
//  SwiftData model mirroring the partner_vaults table for local storage.
//

import Foundation
import SwiftData

/// Local SwiftData model for the Partner Vault.
///
/// Mirrors the `partner_vaults` table in Supabase. Stores partner profile data
/// locally for fast access and offline-capable display.
///
/// Database columns mapped:
/// - `id` → `remoteID` (UUID from Supabase)
/// - `user_id` → `userID`
/// - `partner_name` → `partnerName`
/// - `relationship_tenure_months` → `relationshipTenureMonths`
/// - `cohabitation_status` → `cohabitationStatus`
/// - `location_city` → `locationCity`
/// - `location_state` → `locationState`
/// - `location_country` → `locationCountry`
/// - `created_at` → `createdAt`
/// - `updated_at` → `updatedAt`
@Model
final class PartnerVaultLocal {
    /// The UUID from the Supabase `partner_vaults.id` column.
    var remoteID: UUID?

    /// The UUID of the authenticated user who owns this vault.
    var userID: UUID?

    /// The partner's display name (required in Supabase, NOT NULL).
    var partnerName: String

    /// How many months the user has been in this relationship.
    var relationshipTenureMonths: Int?

    /// Living arrangement: "living_together", "separate", or "long_distance".
    var cohabitationStatus: String?

    /// Partner's city (e.g., "San Francisco").
    var locationCity: String?

    /// Partner's state or region (e.g., "CA").
    var locationState: String?

    /// Partner's country (defaults to "US" in Supabase).
    var locationCountry: String?

    /// Timestamp when the vault was created on the backend.
    var createdAt: Date?

    /// Timestamp when the vault was last updated on the backend.
    var updatedAt: Date?

    /// Local sync status with the Supabase backend.
    var syncStatusRaw: String

    /// Computed accessor for the sync status enum.
    var syncStatus: SyncStatus {
        get { SyncStatus(rawValue: syncStatusRaw) ?? .pendingUpload }
        set { syncStatusRaw = newValue.rawValue }
    }

    init(
        remoteID: UUID? = nil,
        userID: UUID? = nil,
        partnerName: String,
        relationshipTenureMonths: Int? = nil,
        cohabitationStatus: String? = nil,
        locationCity: String? = nil,
        locationState: String? = nil,
        locationCountry: String? = nil,
        createdAt: Date? = nil,
        updatedAt: Date? = nil,
        syncStatus: SyncStatus = .pendingUpload
    ) {
        self.remoteID = remoteID
        self.userID = userID
        self.partnerName = partnerName
        self.relationshipTenureMonths = relationshipTenureMonths
        self.cohabitationStatus = cohabitationStatus
        self.locationCity = locationCity
        self.locationState = locationState
        self.locationCountry = locationCountry
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.syncStatusRaw = syncStatus.rawValue
    }
}
