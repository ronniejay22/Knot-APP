//
//  SettingsView.swift
//  Knot
//
//  Created on February 16, 2026.
//  Step 11.1: Settings screen with Account, Partner Profile, Notifications,
//  and About sections. Replaces the temporary toolbar buttons in HomeView.
//  Step 11.2: Account deletion with three-stage confirmation flow
//  (warning, Apple Sign-In re-auth, final confirmation).
//  Profile redesign: couple hero, grouped cards, quiet account actions,
//  and a Terms · Privacy footer.
//

import SwiftUI
import SwiftData

/// The Profile tab (and the Settings sheet when presented modally).
///
/// Top to bottom:
/// - **Hero** — the couple card (`ProfileHeroCard`) with an Edit profile shortcut
/// - **Partner** — partner profile (reuses `EditVaultView`), milestones
/// - **Preferences** — notifications toggle
/// - **Account** — email display
/// - **Sign out** and **Delete account** (Step 11.2) as quiet buttons
/// - **Footer** — Terms · Privacy links
/// - **Developer** — DEBUG-only tools, last
struct SettingsView: View {
    /// When `true`, the view is embedded in the tab bar and hides the dismiss button.
    let isTabEmbedded: Bool

    static let termsURL = URL(string: "https://drive.google.com/file/d/1AeU_SpK1pJ1l8Cl1eLqYXSGEwIiEY7Bc/view")!
    static let privacyURL = URL(string: "https://drive.google.com/file/d/1aBUcFdQoMj14dLWpF72gZkHlJtpbgZKW/view")!

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AuthViewModel.self) private var authViewModel

    @State private var viewModel: SettingsViewModel

    init(isTabEmbedded: Bool = false, viewModel: SettingsViewModel = SettingsViewModel()) {
        self.isTabEmbedded = isTabEmbedded
        _viewModel = State(initialValue: viewModel)
    }

    /// Controls the Edit Profile fullScreenCover (moved from HomeView).
    @State private var showEditProfile = false

    /// Controls the Milestones management fullScreenCover.
    @State private var showMilestones = false

    #if DEBUG
    /// Step 19.23 — Developer menu: presents `OnboardingPaywallView` on demand.
    /// The paywall otherwise exists only at the very end of onboarding, so re-reaching it
    /// meant running the backend dev server and using "Reset Onboarding (DEV)" — far too
    /// much friction to verify a subscription change.
    @State private var showDevPaywall = false

    /// Owns the paywall's StoreKit state for the developer-menu presentation, mirroring
    /// how `OnboardingContainerView` owns it for the real flow (so loaded products and
    /// in-flight purchase state survive view rebuilds).
    @State private var devSubscriptionManager = SubscriptionManager()

    /// Result banner for "Reset Premium (DEV)", or nil.
    @State private var devPremiumResetMessage: String?
    #endif

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.backgroundGradient.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: Theme.Spacing.xxl) {
                        ProfileHeroCard(
                            content: viewModel.heroContent,
                            isPlaceholder: viewModel.showsHeroPlaceholder,
                            onEditProfile: { showEditProfile = true }
                        )
                        partnerSection
                        preferencesSection
                        accountSection
                        accountActions
                        legalFooter
                        #if DEBUG
                        developerSection
                        #endif
                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, Theme.Spacing.xl)
                    .padding(.top, Theme.Spacing.sm)
                }

                // MARK: - Loading Overlays
                if viewModel.isDeletingAccount {
                    deletionLoadingOverlay
                }
                #if DEBUG
                if viewModel.isDevResetting {
                    KnotProgressIndicator.Overlay(message: "Resetting onboarding...")
                }
                #endif
            }
            .navigationTitle(isTabEmbedded ? "Profile" : "Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !isTabEmbedded {
                    settingsToolbar
                }
            }
            // Account deletion alerts (Step 11.2)
            .modifier(AccountDeletionAlerts(
                viewModel: $viewModel,
                modelContext: modelContext,
                authViewModel: authViewModel,
                dismiss: dismiss
            ))
            #if DEBUG
            // DEBUG-only dev-reset confirmation + error alert
            .modifier(DeveloperAlerts(
                viewModel: $viewModel,
                modelContext: modelContext,
                authViewModel: authViewModel
            ))
            #endif
            // MARK: - Sheets
            // Reloads the partner on dismiss so an edited name, tenure, or
            // city shows up in the hero.
            .fullScreenCover(isPresented: $showEditProfile, onDismiss: {
                Task { await viewModel.loadPartnerProfile() }
            }) {
                EditVaultView()
            }
            .fullScreenCover(isPresented: $showMilestones) {
                MilestonesManagementView()
            }
            #if DEBUG
            // Step 19.23 — Developer menu: the onboarding paywall, on demand.
            .fullScreenCover(isPresented: $showDevPaywall) {
                OnboardingPaywallView(
                    subscriptionManager: devSubscriptionManager,
                    onContinue: { showDevPaywall = false },
                    onClose: { showDevPaywall = false }
                )
            }
            // Informational only — the title must not imply something was reset.
            .alert(
                "Clearing StoreKit Purchases",
                isPresented: Binding(
                    get: { devPremiumResetMessage != nil },
                    set: { if !$0 { devPremiumResetMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) { devPremiumResetMessage = nil }
            } message: {
                Text(devPremiumResetMessage ?? "")
            }
            #endif
            .sheet(isPresented: $viewModel.showDeleteConfirmationSheet) {
                ReauthenticationSheet(
                    onConfirm: {
                        let success = await viewModel.executeAccountDeletion(modelContext: modelContext)
                        if success {
                            await authViewModel.signOutAfterDeletion()
                            dismiss()
                        }
                        return success
                    },
                    onCancel: { }
                )
            }
            .task {
                await viewModel.loadOnAppear()
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    Task { await viewModel.refreshOnForeground() }
                }
            }
        }
    }

    /// Loading overlay shown during account deletion.
    private var deletionLoadingOverlay: some View {
        KnotProgressIndicator.Overlay(message: "Deleting account...")
    }

    /// Toolbar content extracted to reduce body complexity.
    @ToolbarContentBuilder
    private var settingsToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            KnotIconButton(icon: .closeOutlined, variant: .ghost, size: .sm) {
                dismiss()
            }
            .accessibilityLabel("Close")
        }
    }

    // MARK: - Partner Section

    private var partnerSection: some View {
        KnotListGroup("Partner") {
            KnotListRow.chevron(
                icon: .favoriteBorder,
                title: "Partner profile",
                action: { showEditProfile = true }
            )

            KnotListDivider()

            KnotListRow.chevron(
                icon: .eventOutlined,
                title: "Milestones",
                action: { showMilestones = true }
            )
        }
    }

    // MARK: - Preferences Section

    private var preferencesSection: some View {
        KnotListGroup("Preferences") {
            KnotListRow.toggle(
                icon: .notificationsActiveOutlined,
                title: "Notifications",
                isOn: Binding(
                    get: { viewModel.notificationsEnabled },
                    set: { _ in
                        Task { await viewModel.toggleNotifications() }
                    }
                )
            )
        }
    }

    // MARK: - Account Section

    private var accountSection: some View {
        KnotListGroup("Account") {
            KnotListRow.info(
                icon: .mailOutlined,
                title: "Email",
                value: viewModel.userEmail
            )
        }
    }

    /// Sign out and Delete account as quiet buttons below the cards, rather
    /// than rows — Delete account's typed-confirmation sheet carries the
    /// warning, so the entry point doesn't need to shout.
    private var accountActions: some View {
        VStack(spacing: Theme.Spacing.sm) {
            KnotButton(
                "Sign out",
                variant: .outlineNeutral,
                size: .lg,
                shape: .pill,
                action: { Task { await authViewModel.signOut() } }
            )

            KnotButton(
                "Delete account",
                variant: .ghostDestructive,
                action: { viewModel.requestAccountDeletion() }
            )
            .accessibilityHint("Permanently remove your data")
        }
    }

    // MARK: - Legal Footer

    private var legalFooter: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Link("Terms", destination: Self.termsURL)
                .knotFont(Theme.Typography.label)
                .foregroundStyle(Theme.textSecondary)
                .accessibilityLabel("Terms of Service")

            Text("·")
                .knotFont(Theme.Typography.label)
                .foregroundStyle(Theme.textTertiary)
                .accessibilityHidden(true)

            Link("Privacy", destination: Self.privacyURL)
                .knotFont(Theme.Typography.label)
                .foregroundStyle(Theme.textSecondary)
                .accessibilityLabel("Privacy Policy")
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Developer Section (Step 15.6 — DEBUG only)

    #if DEBUG
    private var developerSection: some View {
        KnotListGroup("Developer") {
            KnotListRow.action(
                icon: .refreshOutlined,
                title: "Reset Onboarding (DEV)",
                subtitle: "Wipe vault + pending deletion, return to onboarding",
                action: { viewModel.showDevResetConfirmation = true }
            )

            KnotListDivider()

            // Step 19.23 — reach the paywall without replaying onboarding.
            KnotListRow.action(
                icon: .creditCardOutlined,
                title: "Show Paywall (DEV)",
                subtitle: "Open the subscription paywall and test the free trial",
                action: { showDevPaywall = true }
            )

            KnotListDivider()

            // Step 19.23 — the Simulator keeps StoreKit test purchases across launches, so
            // a completed trial makes the paywall CTA read "Continue" forever, which reads
            // as "the trial button doesn't show payment options". The app cannot revoke its
            // own transactions (StoreKit exposes no such API, and `SKTestSession` aborts
            // outside an XCTest process), so this points at the tooling that can.
            KnotListRow.action(
                icon: .restartAltOutlined,
                title: "Reset Premium (DEV)",
                subtitle: "Shows how to clear local StoreKit purchases",
                action: {
                    devPremiumResetMessage = """
                    An app can't revoke its own StoreKit purchases. Clear them with either:

                    • iOS/scripts/reset-storekit.sh (from the repo)
                    • Xcode ▸ Debug ▸ StoreKit ▸ Manage Transactions, if you launched from Xcode

                    Then reopen the paywall — the CTA should read "Start Free Trial" again.
                    """
                }
            )
        }
    }
    #endif
}

// MARK: - Account Deletion Alerts (Step 11.2)

/// Groups the account deletion alerts into a single `ViewModifier`
/// so the Swift type checker doesn't time out on a long `.alert` chain.
private struct AccountDeletionAlerts: ViewModifier {
    @Binding var viewModel: SettingsViewModel
    let modelContext: ModelContext
    let authViewModel: AuthViewModel
    let dismiss: DismissAction

    func body(content: Content) -> some View {
        content
            // The typed-confirmation sheet (presented by SettingsView)
            // is now the only confirmation step. The previous warning +
            // final-confirmation alerts are gone; this modifier only owns
            // the error alert.
            .alert("Deletion Failed", isPresented: Binding(
                get: { viewModel.deleteAccountError != nil },
                set: { if !$0 { viewModel.deleteAccountError = nil } }
            )) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(viewModel.deleteAccountError ?? "An unexpected error occurred.")
            }
    }
}

// MARK: - Developer Alerts (Step 15.6 — DEBUG only)

#if DEBUG
/// Owns the dev-reset confirmation + error alerts. Lives in its own modifier
/// so the existing `AccountDeletionAlerts` chain stays short and doesn't push
/// the Swift type checker further.
private struct DeveloperAlerts: ViewModifier {
    @Binding var viewModel: SettingsViewModel
    let modelContext: ModelContext
    let authViewModel: AuthViewModel

    func body(content: Content) -> some View {
        content
            .alert("Reset Onboarding?", isPresented: $viewModel.showDevResetConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Reset", role: .destructive) {
                    Task {
                        await viewModel.devResetForOnboarding(
                            authViewModel: authViewModel,
                            modelContext: modelContext
                        )
                    }
                }
            } message: {
                Text("This deletes your partner vault on the server and clears any pending deletion so the app returns to the onboarding wizard. You stay signed in. DEBUG builds only.")
            }
            .alert("Reset Failed", isPresented: Binding(
                get: { viewModel.devResetError != nil },
                set: { if !$0 { viewModel.devResetError = nil } }
            )) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(viewModel.devResetError ?? "An unexpected error occurred.")
            }
    }
}
#endif

// MARK: - Previews

#Preview("Settings") {
    SettingsView()
        .environment(AuthViewModel())
}
