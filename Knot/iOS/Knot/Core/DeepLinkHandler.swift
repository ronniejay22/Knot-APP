//
//  DeepLinkHandler.swift
//  Knot
//
//  Created on February 12, 2026.
//  Step 9.1: Universal Links infrastructure — deep link state management.
//

import Foundation

/// Represents a destination the app should navigate to from a deep link.
///
/// Currently only supports recommendation deep links. Additional cases
/// (e.g., milestone, hint) can be added in future steps.
enum DeepLinkDestination: Equatable, Sendable {
    /// Navigate to a specific recommendation by its database ID.
    case recommendation(id: String)
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

    /// The pending deep link destination. Set by `handleURL(_:)`,
    /// consumed and cleared by the view that navigates to it.
    var pendingDestination: DeepLinkDestination?

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
