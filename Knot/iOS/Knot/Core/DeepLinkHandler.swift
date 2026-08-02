//
//  DeepLinkHandler.swift
//  Knot
//
//  Created on February 12, 2026.
//  Step 9.1: Universal Links infrastructure — deep link state management.
//  Milestone push tap-through: added the milestoneRecommendations destination
//  and the shared-instance bridge so AppDelegate can route notification taps.
//

import Foundation

/// Milestone display data carried in the push payload so the tap-through can
/// render its header immediately, with no network round-trip. The backend
/// (`apns.build_notification_payload`) already knows all three fields — it
/// builds the notification title from them.
struct MilestonePushDisplay: Equatable, Sendable {
    let milestoneName: String
    let partnerName: String?
    let daysBefore: Int?
}

/// Represents a destination the app should navigate to from a deep link.
enum DeepLinkDestination: Equatable, Sendable {
    /// Navigate to a specific recommendation by its database ID.
    case recommendation(id: String)
    /// Navigate to the pre-generated recommendations for a milestone
    /// (a tapped milestone push notification). `notificationId` marks the
    /// originating notification_queue entry as viewed, when present;
    /// `display` renders the header without a lookup.
    case milestoneRecommendations(
        milestoneId: String,
        notificationId: String?,
        display: MilestonePushDisplay?
    )
}

/// Manages deep link state for the app.
///
/// Injected into the SwiftUI environment via `.environment()` in `KnotApp`.
/// Views observe `pendingDestination` and navigate when it is set.
/// After navigation completes, the consuming view sets it back to `nil`.
///
/// URL parsing logic:
/// - `https://api.knot-app.com/recommendation/{id}` → `.recommendation(id: "{id}")`
@Observable
@MainActor
final class DeepLinkHandler {

    /// Shared instance bridging the UIKit boundary. `AppDelegate`'s
    /// notification-tap callback fires before (or independently of) the
    /// SwiftUI hierarchy, so — like `DeviceTokenService.shared` — a singleton
    /// is the access path from the delegate. `KnotApp` injects this same
    /// instance into the SwiftUI environment, so delegate writes and view
    /// observation always agree.
    static let shared = DeepLinkHandler()

    /// The pending deep link destination. Set by `handleURL(_:)`,
    /// consumed and cleared by the view that navigates to it.
    var pendingDestination: DeepLinkDestination?

    /// Builds the destination for a tapped milestone push notification.
    ///
    /// Pure static helper (rather than inline in AppDelegate) so XCTest can
    /// exercise the mapping — `UNNotificationResponse` cannot be constructed
    /// in tests. Returns `nil` when the payload carries no usable milestone id.
    ///
    /// `milestoneName` / `partnerName` / `daysBefore` come from the push
    /// payload's custom keys; when present they let the tap-through render its
    /// header instantly. They are optional so a push from an older backend
    /// (before those keys were added) still routes correctly.
    static func destination(
        milestoneId: String?,
        notificationId: String?,
        milestoneName: String? = nil,
        partnerName: String? = nil,
        daysBefore: Int? = nil
    ) -> DeepLinkDestination? {
        guard let milestoneId, !milestoneId.isEmpty else { return nil }

        var display: MilestonePushDisplay?
        if let milestoneName, !milestoneName.isEmpty {
            display = MilestonePushDisplay(
                milestoneName: milestoneName,
                partnerName: (partnerName?.isEmpty == false) ? partnerName : nil,
                daysBefore: daysBefore
            )
        }

        return .milestoneRecommendations(
            milestoneId: milestoneId,
            notificationId: (notificationId?.isEmpty == false) ? notificationId : nil,
            display: display
        )
    }

    /// Parses an incoming Universal Link URL and sets `pendingDestination`.
    ///
    /// Expected URL format: `https://api.knot-app.com/recommendation/{uuid}`
    ///
    /// If the URL does not match a known pattern, it is silently ignored
    /// (logged to console for debugging). Step 9.2 will add the actual
    /// data fetching and navigation logic that reacts to `pendingDestination`.
    func handleURL(_ url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true) else {
            print("[Knot] Deep link: failed to parse URL: \(url)")
            return
        }

        let pathComponents = components.path
            .split(separator: "/")
            .map(String.init)

        // Match: /recommendation/{id}
        if pathComponents.count == 2,
           pathComponents[0] == "recommendation",
           !pathComponents[1].isEmpty {
            let recommendationId = pathComponents[1]
            print("[Knot] Deep link: recommendation \(recommendationId)")
            pendingDestination = .recommendation(id: recommendationId)
            return
        }

        print("[Knot] Deep link: unrecognized path: \(components.path)")
    }
}
