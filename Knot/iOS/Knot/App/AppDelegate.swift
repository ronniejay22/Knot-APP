//
//  AppDelegate.swift
//  Knot
//
//  Created on February 12, 2026.
//  Step 7.4: Push Notification Registration — AppDelegate for remote notification callbacks.
//  Step 7.6: DND Respect — Notification tap handler for queued/DND-deferred notifications.
//

import UIKit
import UserNotifications

/// UIApplicationDelegate for handling remote notification registration callbacks.
///
/// SwiftUI does not provide native hooks for `didRegisterForRemoteNotificationsWithDeviceToken`
/// or `didFailToRegisterForRemoteNotificationsWithDeviceToken`. This delegate is bridged
/// into the SwiftUI lifecycle via `@UIApplicationDelegateAdaptor` in `KnotApp`.
///
/// Also conforms to `UNUserNotificationCenterDelegate` to handle foreground notification
/// display behavior.
@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate, @preconcurrency UNUserNotificationCenterDelegate {

    // MARK: - App Lifecycle

    /// Configures the notification center delegate on app launch.
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    // MARK: - Remote Notification Registration

    /// Called by the system after successfully registering with APNs.
    ///
    /// Converts the raw device token data to a hex string and sends it
    /// to the backend via `DeviceTokenService`. This method is called
    /// on every app launch when the app is registered for remote
    /// notifications (tokens can change between launches).
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let tokenString = deviceToken.map { String(format: "%02x", $0) }.joined()
        print("[Knot] APNs device token: \(tokenString.prefix(16))...")

        Task {
            await DeviceTokenService.shared.registerToken(tokenString)
        }
    }

    /// Called by the system when APNs registration fails.
    ///
    /// This commonly happens on the iOS Simulator (which does not support
    /// push notifications). Logs the error but does not surface it to the
    /// user — push notifications are a non-blocking feature.
    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("[Knot] APNs registration failed: \(error.localizedDescription)")
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Allows notifications to display when the app is in the foreground.
    ///
    /// By default, iOS suppresses notification banners when the app is active.
    /// This method opts in to showing the banner and playing the sound even
    /// while the user is using Knot.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        return [.banner, .sound]
    }

    /// Handles notification tap responses (Step 7.6).
    ///
    /// Called when the user taps on a notification, including notifications
    /// that were queued by the system during DND/Focus mode and delivered
    /// later. Extracts `notification_id` and `milestone_id` from the
    /// payload for deep-linking to the recommendations screen.
    ///
    /// iOS automatically queues notifications during system DND and delivers
    /// them when DND ends — no custom suppression logic is needed.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo
        let notificationId = userInfo["notification_id"] as? String
        let milestoneId = userInfo["milestone_id"] as? String

        print("[Knot] Notification tapped: notification=\(notificationId ?? "nil"), milestone=\(milestoneId ?? "nil")")

        // Deep-link handling to recommendations screen will be
        // implemented in Step 9.2 (Deep Link Handler for Recommendations).
    }
}
