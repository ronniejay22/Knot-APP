//
//  SettingsViewModel.swift
//  Knot
//
//  Created on February 16, 2026.
//  Step 11.1: Settings screen state management — email loading, hint clearing,
//  notification toggle, app version display.
//

import Foundation
import UIKit
import UserNotifications

/// Manages state for the Settings screen.
///
/// Handles loading the user's email from the Supabase session, checking
/// notification authorization status, toggling notifications, and clearing
/// all captured hints via the existing `HintService`.
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

    /// Whether to show the "delete account coming soon" alert (Step 11.2).
    var showDeleteAccountAlert = false

    /// Whether to show the "export data coming soon" alert (Step 11.3).
    var showExportDataAlert = false

    /// Whether to show the "quiet hours coming soon" alert (Step 11.4).
    var showQuietHoursAlert = false

    /// Whether notifications are currently authorized.
    var notificationsEnabled = false

    /// Whether the notification toggle is being updated.
    var isUpdatingNotifications = false

    // MARK: - Computed Properties

    /// The app version string from the main bundle (e.g., "1.0 (1)").
    var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
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

    /// Loads the current notification authorization status.
    func loadNotificationStatus() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        notificationsEnabled = settings.authorizationStatus == .authorized
    }

    /// Toggles notification permissions.
    ///
    /// iOS does not allow apps to programmatically revoke notification permission.
    /// When the user tries to disable notifications, we direct them to the system
    /// Settings app. When enabling, we request permission via `UNUserNotificationCenter`.
    func toggleNotifications() async {
        isUpdatingNotifications = true
        defer { isUpdatingNotifications = false }

        if notificationsEnabled {
            // Cannot programmatically disable — direct to system Settings
            if let url = URL(string: UIApplication.openSettingsURLString) {
                await UIApplication.shared.open(url)
            }
        } else {
            // Request permission
            let center = UNUserNotificationCenter.current()
            do {
                let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
                notificationsEnabled = granted
                if granted {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            } catch {
                print("[Knot] SettingsViewModel: Notification permission error — \(error.localizedDescription)")
            }
        }
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
}
