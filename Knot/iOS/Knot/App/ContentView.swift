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

/// Identifiable payload for the milestone push tap-through cover.
struct MilestoneDeepLink: Identifiable, Equatable {
    let milestoneId: String
    let notificationId: String?
    var id: String { milestoneId }
}

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

    /// The milestone whose pre-generated recommendations to display
    /// (a tapped milestone push notification).
    @State private var milestoneDeepLink: MilestoneDeepLink?

    var body: some View {
        Group {
            if let screen = UITestScreenshotHarness.activeScreen {
                // MARK: - UI-test screenshot seam (no effect on normal launches)
                UITestScreenshotHarness.rootView(for: screen)
            } else if authViewModel.isCheckingSession {
                // MARK: - Loading (checking Keychain for session)
                sessionCheckView
            } else if authViewModel.isAuthenticated {
                if let scheduledAt = authViewModel.pendingDeletionScheduledAt {
                    // MARK: - Authenticated + Pending deletion → Restore gate (Step 15.5)
                    PendingDeletionView(
                        scheduledAt: scheduledAt,
                        onRestored: {
                            Task { await authViewModel.didRestoreAccount() }
                        },
                        onSignOut: {
                            await authViewModel.signOut()
                        }
                    )
                } else if authViewModel.hasCompletedOnboarding {
                    // MARK: - Authenticated + Vault exists → Tab Bar
                    MainTabView()
                } else {
                    // MARK: - Authenticated + No vault → Onboarding
                    OnboardingContainerView {
                        // Called when the user taps "Continue" on the final
                        // recommendation-reveal step (the vault was already submitted
                        // on the Love Languages step).
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
        .fullScreenCover(item: $milestoneDeepLink) { link in
            MilestoneRecommendationsCoverView(
                milestoneId: link.milestoneId,
                notificationId: link.notificationId,
                onDismiss: { milestoneDeepLink = nil }
            )
            // The cover's content does not inherit the `.environment(authViewModel)`
            // applied to the Group above (the cover is attached outside it), and
            // the hosted RecommendationsView requires AuthViewModel — inject
            // explicitly.
            .environment(authViewModel)
        }
        .onChange(of: deepLinkHandler.pendingDestination) { _, newValue in
            // Warm start / foreground tap.
            guard newValue != nil else { return }
            consumePendingDeepLink()
        }
        .task {
            // COLD START: consume any pending deep link BEFORE starting the
            // auth listener — `listenForAuthChanges()` is a for-await over
            // `authStateChanges` that never returns, so any code placed after
            // the await is dead. (If the notification tap lands after this
            // check instead, the `.onChange` above catches it — both
            // orderings are safe.)
            consumePendingDeepLink()
            await authViewModel.listenForAuthChanges()
        }
    }

    /// Routes the pending deep link (if any) to the matching presentation
    /// state and clears it so it can't re-present.
    private func consumePendingDeepLink() {
        switch deepLinkHandler.pendingDestination {
        case .recommendation(let id):
            deepLinkRecommendationId = id
        case .milestoneRecommendations(let milestoneId, let notificationId):
            milestoneDeepLink = MilestoneDeepLink(
                milestoneId: milestoneId,
                notificationId: notificationId
            )
        case nil:
            return
        }
        deepLinkHandler.pendingDestination = nil
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
                .knotFont(Theme.Typography.body)
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
