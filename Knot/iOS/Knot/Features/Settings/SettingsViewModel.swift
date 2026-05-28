//
//  SettingsViewModel.swift
//  Knot
//
//  Created on February 16, 2026.
//  Step 11.1: Settings screen state management — email loading, hint clearing,
//  notification toggle, app version display.
//  Step 11.2: Account deletion state management — re-authentication flow,
//  backend deletion call, local SwiftData cleanup.
//  Step 11.3: Data export — export all user data as PDF via share sheet.
//  Step 11.4: Notification preferences — quiet hours, global toggle, backend sync.
//

import Foundation
import SwiftData
import UIKit
import UserNotifications

/// Manages state for the Settings screen.
///
/// Handles loading the user's email from the Supabase session, checking
/// notification authorization status, toggling notifications, managing
/// quiet hours preferences, and clearing all captured hints via `HintService`.
@Observable
@MainActor
final class SettingsViewModel {

    // MARK: - State

    /// The user's email address from the Supabase session.
    var userEmail: String = ""

    /// Whether the "clear all hints" operation is in progress.
    var isClearingHints = false

    /// Error message from the clear hints operation.
    var clearHintsError: String?

    /// Whether to show the clear hints confirmation alert.
    var showClearHintsConfirmation = false

    /// Whether to show the "clear hints success" alert.
    var showClearHintsSuccess = false

    /// Whether the typed-confirmation sheet is showing.
    /// The sheet itself carries the warning + confirmation, so the
    /// previous warning alert + final-confirmation alert are gone.
    var showDeleteConfirmationSheet = false

    /// Whether the account deletion network request is in progress.
    var isDeletingAccount = false

    /// Error message from the account deletion operation.
    var deleteAccountError: String?

    /// Whether to show the export data confirmation alert (Step 11.3).
    var showExportDataAlert = false

    /// Whether a data export is currently in progress.
    var isExportingData = false

    /// Error message from the data export operation.
    var exportDataError: String?

    /// Whether the export completed successfully (triggers share sheet).
    var showExportShareSheet = false

    /// The temporary file URL of the exported PDF file for sharing.
    var exportedFileURL: URL?

    /// Whether notifications are currently authorized (iOS system permission).
    var notificationsEnabled = false

    /// Whether the notification toggle is being updated.
    var isUpdatingNotifications = false

    // MARK: - Notification Preferences State (Step 11.4)

    /// Hour when quiet hours begin (0-23). Synced with backend.
    var quietHoursStart: Int = 22

    /// Hour when quiet hours end (0-23). Synced with backend.
    var quietHoursEnd: Int = 8

    /// Whether the quiet hours picker is expanded/visible.
    var showQuietHoursPicker = false

    /// Whether notification preferences are being loaded from the backend.
    var isLoadingPreferences = false

    /// Whether notification preferences are being saved to the backend.
    var isSavingPreferences = false

    /// Error message from notification preferences operations.
    var preferencesError: String?

    // MARK: - Computed Properties

    /// The app version string from the main bundle (e.g., "1.0 (1)").
    var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    /// Formats an hour (0-23) as a 12-hour time string (e.g., "10:00 PM").
    func formatHour(_ hour: Int) -> String {
        let period = hour >= 12 ? "PM" : "AM"
        let displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour)
        return "\(displayHour):00 \(period)"
    }

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

    // MARK: - Notification Preferences (Step 11.4)

    /// Loads notification preferences from the backend.
    ///
    /// Fetches quiet hours, timezone, and the global notifications toggle
    /// from the server and updates local state. Called in `.task {}` alongside
    /// `loadNotificationStatus()`.
    func loadNotificationPreferences() async {
        isLoadingPreferences = true
        preferencesError = nil

        do {
            let service = NotificationPreferencesService()
            let prefs = try await service.fetchPreferences()
            quietHoursStart = prefs.quietHoursStart
            quietHoursEnd = prefs.quietHoursEnd
        } catch {
            print("[Knot] SettingsViewModel: Failed to load notification preferences — \(error.localizedDescription)")
        }

        isLoadingPreferences = false
    }

    /// Saves the current quiet hours to the backend.
    ///
    /// Called after the user adjusts quiet hours start or end time.
    /// Non-blocking — errors are logged but do not show alerts.
    func saveQuietHours() async {
        isSavingPreferences = true
        preferencesError = nil

        do {
            let service = NotificationPreferencesService()
            let update = NotificationPreferencesUpdateDTO(
                notificationsEnabled: nil,
                quietHoursStart: quietHoursStart,
                quietHoursEnd: quietHoursEnd,
                timezone: nil
            )
            let result = try await service.updatePreferences(update)
            quietHoursStart = result.quietHoursStart
            quietHoursEnd = result.quietHoursEnd
        } catch {
            preferencesError = error.localizedDescription
            print("[Knot] SettingsViewModel: Failed to save quiet hours — \(error.localizedDescription)")
        }

        isSavingPreferences = false
    }

    /// Clears all hints by fetching pages and deleting each one via `HintService`.
    ///
    /// There is no bulk delete endpoint, so hints are deleted sequentially.
    /// The backend limits `listHints` to 100 per request, so we paginate
    /// until no more hints remain.
    func clearAllHints() async {
        isClearingHints = true
        clearHintsError = nil

        do {
            let service = HintService()
            // Paginate through all hints (backend limit is 100 per request)
            while true {
                let response = try await service.listHints(limit: 100, offset: 0)
                if response.hints.isEmpty { break }
                for hint in response.hints {
                    try await service.deleteHint(id: hint.id)
                }
            }
            isClearingHints = false
            showClearHintsSuccess = true
        } catch {
            isClearingHints = false
            clearHintsError = error.localizedDescription
        }
    }

    // MARK: - Data Export (Step 11.3)

    /// Exports all user data as a styled PDF and prepares a temporary file for sharing.
    ///
    /// Calls `GET /api/v1/users/me/export`, decodes the JSON into a structured
    /// model, renders a branded PDF via `PDFExportRenderer`, writes it to a
    /// temporary file, and triggers the system share sheet.
    func exportUserData() async {
        isExportingData = true
        exportDataError = nil

        do {
            let service = ExportService()
            let rawData = try await service.exportData()

            let decoder = JSONDecoder()
            let exportData = try decoder.decode(DataExportResponse.self, from: rawData)

            let renderer = PDFExportRenderer()
            let pdfData = try await renderer.renderPDF(from: exportData)

            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            let dateString = dateFormatter.string(from: Date())
            let fileName = "Knot Data Export \u{2014} \(dateString).pdf"
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

            try pdfData.write(to: tempURL)

            exportedFileURL = tempURL
            isExportingData = false
            showExportShareSheet = true
        } catch {
            isExportingData = false
            exportDataError = error.localizedDescription
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
