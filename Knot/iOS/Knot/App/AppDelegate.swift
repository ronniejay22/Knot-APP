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

    /// Handles notification tap responses (Step 7.6; tap-through wired in the
    /// milestone push tap-through step).
    ///
    /// Called when the user taps on a notification, including notifications
    /// that were queued by the system during DND/Focus mode and delivered
    /// later. Extracts `notification_id` and `milestone_id` from the payload
    /// and routes to the pre-generated milestone recommendations via
    /// `DeepLinkHandler.shared` — `ContentView` observes `pendingDestination`
    /// (warm start via `.onChange`, cold start via its `.task`) and presents
    /// the milestone recommendations cover.
    ///
    /// Swift 6 note: `userInfo` (`[AnyHashable: Any]`) is not Sendable. This
    /// delegate is `@MainActor` (the conformance is `@preconcurrency`, so the
    /// runtime hops here), so the String values are extracted before anything
    /// crosses an isolation boundary; `DeepLinkHandler` is also `@MainActor`,
    /// making the write a direct same-actor call.
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
        // Display data rides in the payload so the tap-through renders its
        // header with no lookup. `days_before` arrives as an NSNumber.
        let milestoneName = userInfo["milestone_name"] as? String
        let partnerName = userInfo["partner_name"] as? String
        let daysBefore = (userInfo["days_before"] as? NSNumber)?.intValue

        print("[Knot] Notification tapped: notification=\(notificationId ?? "nil"), milestone=\(milestoneId ?? "nil")")

        guard let destination = DeepLinkHandler.destination(
            milestoneId: milestoneId,
            notificationId: notificationId,
            milestoneName: milestoneName,
            partnerName: partnerName,
            daysBefore: daysBefore
        ) else {
            print("[Knot] Notification tapped without milestone_id — ignoring")
            return
        }
        DeepLinkHandler.shared.pendingDestination = destination
    }
}
