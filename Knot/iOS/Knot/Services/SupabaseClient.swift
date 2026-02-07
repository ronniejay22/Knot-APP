//
//  SupabaseClient.swift
//  Knot
//
//  Created on February 6, 2026.
//  Step 2.2: Supabase client singleton for auth and database access.
//

import Foundation
import Supabase

/// Provides a shared Supabase client for the entire app.
///
/// The client automatically stores auth sessions in the iOS Keychain.
/// Uses the anon (publishable) key — Row Level Security (RLS) in the
/// database enforces per-user access control based on the JWT.
enum SupabaseManager {
    /// Shared Supabase client instance.
    static let client = SupabaseClient(
        supabaseURL: Constants.Supabase.projectURL,
        supabaseKey: Constants.Supabase.anonKey
    )
}
