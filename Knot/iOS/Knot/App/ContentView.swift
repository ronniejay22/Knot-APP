//
//  ContentView.swift
//  Knot
//
//  Created on February 3, 2026.
//  Updated February 6, 2026 — Step 2.1: Show SignInView as the initial screen.
//  Updated February 6, 2026 — Step 2.3: Auth state router with session persistence.
//  Updated February 7, 2026 — Step 3.1: Added Onboarding flow between auth and Home.
//  Updated February 12, 2026 — Step 9.1: Added DeepLinkHandler environment property.
//

import SwiftUI

/// Root view of the app. Routes between Sign-In, Onboarding, and Home based on auth state.
///
/// On launch, the Supabase SDK checks the iOS Keychain for an existing session.
/// While checking, a loading indicator is shown. Once resolved:
/// - No session → Sign-In screen
/// - Session exists, no vault → Onboarding flow
/// - Session exists, vault exists → Home screen
///
/// The `AuthViewModel` is created here and injected into the SwiftUI environment
/// so all child views (SignInView, OnboardingContainerView, HomeView) share the same auth state.
struct ContentView: View {
    @State private var authViewModel = AuthViewModel()
    @Environment(DeepLinkHandler.self) private var deepLinkHandler

    /// The recommendation ID to display from a deep link (Step 9.2).
    @State private var deepLinkRecommendationId: String?

    var body: some View {
        Group {
            if authViewModel.isCheckingSession {
                // MARK: - Loading (checking Keychain for session)
                sessionCheckView
            } else if authViewModel.isAuthenticated {
                if authViewModel.hasCompletedOnboarding {
                    // MARK: - Authenticated + Vault exists → Home
                    HomeView()
                } else {
                    // MARK: - Authenticated + No vault → Onboarding
                    OnboardingContainerView {
                        // Called when user taps "Get Started" on the completion step
                        authViewModel.hasCompletedOnboarding = true
                    }
                }
            } else {
                // MARK: - Not authenticated → Sign-In
                SignInView()
            }
        }
        .environment(authViewModel)
        .fullScreenCover(isPresented: Binding(
            get: { deepLinkRecommendationId != nil },
            set: { if !$0 { deepLinkRecommendationId = nil } }
        )) {
            if let recId = deepLinkRecommendationId {
                DeepLinkRecommendationView(
                    recommendationId: recId,
                    onDismiss: {
                        deepLinkRecommendationId = nil
                    }
                )
            }
        }
        .onChange(of: deepLinkHandler.pendingDestination) { _, newValue in
            if case .recommendation(let id) = newValue {
                deepLinkRecommendationId = id
                deepLinkHandler.pendingDestination = nil
            }
        }
        .task {
            await authViewModel.listenForAuthChanges()

            // Check for pending deep link on cold start
            if case .recommendation(let id) = deepLinkHandler.pendingDestination {
                deepLinkRecommendationId = id
                deepLinkHandler.pendingDestination = nil
            }
        }
    }

    // MARK: - Session Check Loading View

    /// Displayed briefly on app launch while the Supabase SDK checks the
    /// Keychain for a stored session. Typically resolves in under 100ms.
    private var sessionCheckView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.regular)
                .tint(Theme.accent)
            Text("Loading...")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.backgroundGradient.ignoresSafeArea())
    }
}

#Preview {
    ContentView()
        .environment(DeepLinkHandler())
}
