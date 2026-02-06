//
//  SyncStatus.swift
//  Knot
//
//  Created on February 6, 2026.
//

import Foundation

/// Sync status for local SwiftData models.
/// Tracks whether a record is in sync with the Supabase backend.
enum SyncStatus: String, Codable, Sendable {
    /// Record is in sync with the backend.
    case synced
    /// Record was created or modified locally and needs to be uploaded.
    case pendingUpload
    /// Record exists on the backend but hasn't been downloaded locally yet.
    case pendingDownload
}
