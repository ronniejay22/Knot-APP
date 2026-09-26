//
//  SettingsViewModel.swift
//  Knot
//
//  Created on February 16, 2026.
//  Step 11.1: Settings screen state management — email loading,
//  notification toggle.
//  Step 11.2: Account deletion state management — re-authentication flow,
//  backend deletion call, local SwiftData cleanup.
//  Profile redesign: partner summary loading for the Profile hero.
//

import Foundation
import SwiftData
import UIKit
import UserNotifications

/// Seam for fetching the partner vault behind the Profile hero, so the
/// hero's loading and failure paths are unit-testable without a live backend.
/// Conformed to by the existing `VaultService`.
@MainActor
protocol PartnerVaultFetching {
    func getVault() async throws -> VaultGetResponse
}

extension VaultService: PartnerVaultFetching {}

/// The slice of the partner vault the Profile hero shows.
struct PartnerProfileSummary: Equatable, Sendable {
    let partnerName: String
    let relationshipTenureMonths: Int?
    let locationCity: String?
    let locationState: String?
}

extension PartnerProfileSummary {
    init(vault: VaultGetResponse) {
        self.init(
            partnerName: vault.partnerName,
            relationshipTenureMonths: vault.relationshipTenureMonths,
            locationCity: vault.locationCity,
            locationState: vault.locationState
        )
    }
}

/// Manages state for the Settings screen.
///
/// Handles loading the user's email from the Supabase session, loading the
/// partner summary for the Profile hero, checking notification authorization
/// status, toggling notifications, and the account deletion flow.
@Observable
@MainActor
final class SettingsViewModel {

    // MARK: - State

    /// The user's email address from the Supabase session.
    var userEmail: String = ""

    /// The partner shown in the Profile hero, or nil before the vault loads
    /// (or when it has never loaded). A failed refresh keeps the last value.
    var partnerSummary: PartnerProfileSummary?

    /// Whether a partner load has finished at least once, successfully or
    /// not. Until then the hero shows its placeholder.
    var hasResolvedPartner = false

    /// Whether `loadOnAppear()` has already run its one-time loads. Set it
    /// on a seeded model (screenshot harness, previews) to skip the network.
    var hasLoadedInitially = false

    private let vaultFetcher: any PartnerVaultFetching

    /// Bumped by every partner load, so only the newest one's result lands.
    private var partnerLoadGeneration = 0

    /// Partner loads currently awaiting the backend.
    private var partnerLoadsInFlight = 0

    init(vaultFetcher: any PartnerVaultFetching = VaultService()) {
        self.vaultFetcher = vaultFetcher
    }

    /// Whether the typed-confirmation sheet is showing.
    /// The sheet itself carries the warning + confirmation, so the
    /// previous warning alert + final-confirmation alerts are gone.
    var showDeleteConfirmationSheet = false

    /// Whether the account deletion network request is in progress.
    var isDeletingAccount = false

    /// Error message from the account deletion operation.
    var deleteAccountError: String?

    /// Whether notifications are currently authorized (iOS system permission).
    var notificationsEnabled = false

    /// Whether the notification toggle is being updated.
    var isUpdatingNotifications = false

    // MARK: - Actions

    /// Loads the user email from the current Supabase session.
    func loadUserEmail() async {
        do {
            let session = try await SupabaseManager.client.auth.session
            userEmail = session.user.email ?? "Not available"
        } catch {
            userEmail = "Not available"
        }
    }

    /// Loads the partner summary for the Profile hero. A failure is logged
    /// and never replaces a summary that already loaded.
    func loadPartnerProfile() async {
        partnerLoadGeneration += 1
        let generation = partnerLoadGeneration
        partnerLoadsInFlight += 1
        defer { partnerLoadsInFlight -= 1 }

        let summary: PartnerProfileSummary?
        do {
            summary = try await PartnerProfileSummary(vault: vaultFetcher.getVault())
        } catch {
            print("[Knot] SettingsViewModel: Partner profile load failed — \(error.localizedDescription)")
            summary = nil
        }

        // A newer load started while this one was in flight (the launch fetch
        // still running when Edit profile closes); its result is fresher, so
        // this one is dropped.
        guard generation == partnerLoadGeneration else { return }
        if let summary { partnerSummary = summary }
        hasResolvedPartner = true
    }

    /// The screen's appear-time loads. Email and partner load once, in
    /// parallel; notification status refreshes on every appear.
    func loadOnAppear() async {
        if !hasLoadedInitially {
            hasLoadedInitially = true
            async let email: Void = loadUserEmail()
            async let partner: Void = loadPartnerProfile()
            _ = await (email, partner)
            // The view went away mid-load, so the loads were cut short: run
            // them again on the next appear rather than keep their failures.
            if Task.isCancelled { hasLoadedInitially = false }
        }
        await loadNotificationStatus()
    }

    /// The return-to-foreground refresh: notification status always, and the
    /// partner again if it has never loaded (say, the app launched offline),
    /// so the hero recovers without a relaunch.
    func refreshOnForeground() async {
        await loadNotificationStatus()
        if hasLoadedInitially, partnerSummary == nil, partnerLoadsInFlight == 0 {
            await loadPartnerProfile()
        }
    }

    /// Whether the hero should show its loading placeholder.
    var showsHeroPlaceholder: Bool {
        partnerSummary == nil && !hasResolvedPartner
    }

    /// What the Profile hero displays.
    var heroContent: ProfileHeroContent {
        showsHeroPlaceholder ? .placeholder : ProfileHeroContent(summary: partnerSummary)
    }

    /// Loads the current notification authorization status from iOS.
    func loadNotificationStatus() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        notificationsEnabled = settings.authorizationStatus == .authorized
    }

    /// Toggles notification permissions.
    ///
    /// iOS only shows the notification permission prompt once. After that:
    /// - If `.notDetermined` → request authorization (shows system prompt)
    /// - If `.denied` → open Settings so the user can re-enable manually
    /// - If `.authorized` → open Settings so the user can disable manually
    func toggleNotifications() async {
        isUpdatingNotifications = true
        defer { isUpdatingNotifications = false }

        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()

        switch settings.authorizationStatus {
        case .notDetermined:
            // First time — show the system permission prompt
            do {
                let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
                notificationsEnabled = granted
                if granted {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            } catch {
                print("[Knot] SettingsViewModel: Notification permission error — \(error.localizedDescription)")
            }

        case .denied, .authorized, .provisional, .ephemeral:
            // Already decided — must change in Settings.app
            if let url = URL(string: UIApplication.openSettingsURLString) {
                await UIApplication.shared.open(url)
            }

        @unknown default:
            if let url = URL(string: UIApplication.openSettingsURLString) {
                await UIApplication.shared.open(url)
            }
        }
    }

    // MARK: - Account Deletion (Step 15.5 — 60-day soft delete)

    /// Called when user taps "Delete Account" button. Presents the typed
    /// confirmation sheet directly; the sheet is itself the warning.
    func requestAccountDeletion() {
        showDeleteConfirmationSheet = true
    }

    /// Schedules the account for deletion (60-day grace).
    ///
    /// Calls the backend to schedule the deletion, then clears all local
    /// SwiftData. The caller is responsible for signing out after this
    /// returns `true`.
    ///
    /// - Parameter modelContext: The SwiftData model context for clearing local data.
    /// - Returns: `true` if scheduling succeeded and sign-out should proceed.
    func executeAccountDeletion(modelContext: ModelContext) async -> Bool {
        isDeletingAccount = true
        deleteAccountError = nil

        do {
            let service = AccountService()
            try await service.deleteAccount()

            clearLocalData(modelContext: modelContext)

            isDeletingAccount = false
            return true
        } catch {
            isDeletingAccount = false
            deleteAccountError = error.localizedDescription
            return false
        }
    }

    // MARK: - Dev Reset (Step 15.6 — DEBUG only)

#if DEBUG
    /// Whether the dev-reset confirmation alert is visible.
    var showDevResetConfirmation = false

    /// Whether the dev-reset network request is in progress.
    var isDevResetting = false

    /// Error message from the dev-reset operation.
    var devResetError: String?

    /// DEV-ONLY: wipes the partner vault on the backend, clears local
    /// SwiftData, and resets the `AuthViewModel` gate so `ContentView`
    /// routes back to the onboarding wizard without signing the user out.
    ///
    /// Backend is gated by `KNOT_DEV_RESET_ENABLED=true`; if it returns
    /// 403, the error surfaces as `devResetError` and the auth state is
    /// left alone.
    func devResetForOnboarding(
        authViewModel: AuthViewModel,
        modelContext: ModelContext
    ) async {
        isDevResetting = true
        devResetError = nil
        defer { isDevResetting = false }

        do {
            try await AccountService().devResetForOnboarding()
            clearLocalData(modelContext: modelContext)
            authViewModel.pendingDeletionScheduledAt = nil
            authViewModel.hasCompletedOnboarding = false
        } catch {
            devResetError = error.localizedDescription
        }
    }
#endif

    /// Removes all SwiftData entities from the local store.
    private func clearLocalData(modelContext: ModelContext) {
        do {
            try modelContext.delete(model: PartnerVaultLocal.self)
            try modelContext.delete(model: HintLocal.self)
            try modelContext.delete(model: MilestoneLocal.self)
            try modelContext.delete(model: RecommendationLocal.self)
            try modelContext.delete(model: SavedRecommendation.self)
            try modelContext.save()
            print("[Knot] Local SwiftData cleared for account deletion")
        } catch {
            // Non-fatal: backend data is already deleted, local data will be
            // orphaned but harmless. A fresh install would clear it anyway.
            print("[Knot] Failed to clear local SwiftData: \(error.localizedDescription)")
        }
    }
}
