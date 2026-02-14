//
//  MerchantHandoffService.swift
//  Knot
//
//  Created on February 12, 2026.
//  Step 9.3: External merchant handoff — opens merchant URLs preferring native apps,
//  falls back to Safari, and logs a "handoff" analytics event.
//

import Foundation
import UIKit

/// Handles opening external merchant URLs with native-app-first preference
/// and recording handoff analytics.
///
/// Flow:
/// 1. Tries universal links first (`.universalLinksOnly: true`) — opens in merchant's native app
/// 2. If no native app handles the link, falls back to regular open (Safari)
/// 3. Records a `"handoff"` feedback action via `RecommendationService` (fire-and-forget)
@MainActor
enum MerchantHandoffService {

    /// Opens a merchant URL, preferring the native app via universal links.
    ///
    /// - Parameters:
    ///   - urlString: The merchant URL string to open
    ///   - recommendationId: The recommendation ID for analytics tracking
    ///   - service: The recommendation service for recording feedback (injectable for testing)
    /// - Returns: `true` if the URL was valid and an open was attempted, `false` if the URL was invalid
    @discardableResult
    static func openMerchantURL(
        urlString: String,
        recommendationId: String,
        service: RecommendationService = RecommendationService()
    ) async -> Bool {
        guard let url = URL(string: urlString), url.scheme != nil else { return false }

        // Try universal links first (native app)
        let openedInApp = await UIApplication.shared.open(
            url,
            options: [.universalLinksOnly: true]
        )

        if !openedInApp {
            // Fall back to regular open (Safari)
            await UIApplication.shared.open(url)
        }

        // Record handoff event (fire-and-forget)
        Task {
            try? await service.recordFeedback(
                recommendationId: recommendationId,
                action: "handoff"
            )
        }

        return true
    }
}
