//
//  HintLocal.swift
//  Knot
//
//  Created on February 6, 2026.
//  SwiftData model mirroring the hints table for local storage.
//

import Foundation
import SwiftData

/// Local SwiftData model for Hints.
///
/// Mirrors the `hints` table in Supabase. Stores captured partner hints
/// locally for fast access and display on the Home screen.
///
/// Database columns mapped:
/// - `id` → `remoteID` (UUID from Supabase)
/// - `vault_id` → `vaultID`
/// - `hint_text` → `hintText`
/// - `source` → `source` ("text_input" or "voice_transcription")
/// - `is_used` → `isUsed`
/// - `created_at` → `createdAt`
///
/// Note: `hint_embedding` (vector(768)) is NOT stored locally —
/// embeddings are only used server-side for semantic search.
@Model
final class HintLocal {
    /// The UUID from the Supabase `hints.id` column.
    var remoteID: UUID?

    /// The vault this hint belongs to (Supabase `hints.vault_id`).
    var vaultID: UUID?

    /// The raw hint text captured by the user (max 500 characters).
    var hintText: String

    /// How the hint was captured: "text_input" or "voice_transcription".
    var source: String

    /// Whether this hint has been used in a recommendation.
    var isUsed: Bool

    /// Timestamp when the hint was captured.
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
        hintText: String,
        source: String = "text_input",
        isUsed: Bool = false,
        createdAt: Date? = nil,
        syncStatus: SyncStatus = .pendingUpload
    ) {
        self.remoteID = remoteID
        self.vaultID = vaultID
        self.hintText = hintText
        self.source = source
        self.isUsed = isUsed
        self.createdAt = createdAt
        self.syncStatusRaw = syncStatus.rawValue
    }
}
