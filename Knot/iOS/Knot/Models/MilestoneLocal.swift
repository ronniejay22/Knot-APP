//
//  MilestoneLocal.swift
//  Knot
//
//  Created on February 6, 2026.
//  SwiftData model mirroring the partner_milestones table for local storage.
//

import Foundation
import SwiftData

/// Local SwiftData model for Partner Milestones.
///
/// Mirrors the `partner_milestones` table in Supabase. Stores milestones
/// (birthdays, anniversaries, holidays, custom events) locally for the
/// Home screen countdown and notification display.
///
/// Database columns mapped:
/// - `id` → `remoteID` (UUID from Supabase)
/// - `vault_id` → `vaultID`
/// - `milestone_type` → `milestoneType` ("birthday", "anniversary", "holiday", "custom")
/// - `milestone_name` → `milestoneName`
/// - `milestone_date` → `milestoneDate` (year-2000 placeholder for yearly recurrence)
/// - `recurrence` → `recurrence` ("yearly" or "one_time")
/// - `budget_tier` → `budgetTier` ("just_because", "minor_occasion", "major_milestone")
/// - `created_at` → `createdAt`
@Model
final class MilestoneLocal {
    /// The UUID from the Supabase `partner_milestones.id` column.
    var remoteID: UUID?

    /// The vault this milestone belongs to (Supabase `partner_milestones.vault_id`).
    var vaultID: UUID?

    /// Type of milestone: "birthday", "anniversary", "holiday", or "custom".
    var milestoneType: String

    /// Display name for the milestone (e.g., "Partner's Birthday", "Valentine's Day").
    var milestoneName: String

    /// The date of the milestone. For yearly recurrence, year 2000 is used
    /// as a placeholder (e.g., 2000-06-15 for June 15). One-time milestones
    /// store the actual date.
    var milestoneDate: Date

    /// Recurrence pattern: "yearly" or "one_time".
    var recurrence: String

    /// Budget tier: "just_because", "minor_occasion", or "major_milestone".
    /// Auto-defaults based on milestone type in Supabase (via trigger).
    var budgetTier: String

    /// Timestamp when the milestone was created on the backend.
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
        milestoneType: String,
        milestoneName: String,
        milestoneDate: Date,
        recurrence: String = "yearly",
        budgetTier: String = "major_milestone",
        createdAt: Date? = nil,
        syncStatus: SyncStatus = .pendingUpload
    ) {
        self.remoteID = remoteID
        self.vaultID = vaultID
        self.milestoneType = milestoneType
        self.milestoneName = milestoneName
        self.milestoneDate = milestoneDate
        self.recurrence = recurrence
        self.budgetTier = budgetTier
        self.createdAt = createdAt
        self.syncStatusRaw = syncStatus.rawValue
    }
}
