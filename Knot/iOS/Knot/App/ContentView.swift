//
//  ContentView.swift
//  Knot
//
//  Created on February 3, 2026.
//  Updated February 6, 2026 — Step 2.1: Show SignInView as the initial screen.
//  Updated February 6, 2026 — Step 2.3: Auth state router with session persistence.
//

import SwiftUI

/// Root view of the app. Routes between Sign-In and Home based on auth state.
///
/// On launch, the Supabase SDK checks the iOS Keychain for an existing session.
/// While checking, a loading indicator is shown. If a valid session is found,
/// the user is taken directly to the Home screen. If no session exists,
/// the Sign-In screen is displayed.
///
/// The `AuthViewModel` is created here and injected into the SwiftUI environment
/// so all child views (SignInView, HomeView) share the same auth state.
struct ContentView: View {
    @State private var authViewModel = AuthViewModel()

    var body: some View {
        Group {
            if authViewModel.isCheckingSession {
                // MARK: - Loading (checking Keychain for session)
                sessionCheckView
            } else if authViewModel.isAuthenticated {
                // MARK: - Authenticated → Home
                HomeView()
            } else {
                // MARK: - Not authenticated → Sign-In
                SignInView()
            }
        }
        .environment(authViewModel)
        .task {
            await authViewModel.listenForAuthChanges()
        }
    }

    // MARK: - Session Check Loading View

    /// Displayed briefly on app launch while the Supabase SDK checks the
    /// Keychain for a stored session. Typically resolves in under 100ms.
    private var sessionCheckView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.regular)
            Text("Loading...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    ContentView()
}
