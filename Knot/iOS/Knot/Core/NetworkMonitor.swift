//
//  NetworkMonitor.swift
//  Knot
//
//  Created on February 8, 2026.
//  Step 4.1: Network connectivity observer for offline banner.
//

import Foundation
import Network

/// Monitors network connectivity using `NWPathMonitor`.
///
/// When `isConnected` is `false`, the Home screen shows a persistent
/// "No internet connection" banner and disables interactive elements
/// (hint capture, recommendation views).
///
/// Usage: Create once and inject via SwiftUI environment.
/// The monitor starts observing immediately on init and stops on deinit.
@Observable
@MainActor
final class NetworkMonitor {

    /// `true` when the device has an active network connection.
    /// Updated on the main actor for safe SwiftUI binding.
    var isConnected: Bool = true

    /// The underlying path monitor.
    private let monitor: NWPathMonitor

    /// Dedicated queue for network path updates.
    private let queue = DispatchQueue(label: "com.ronniejay.knot.networkmonitor")

    init() {
        monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.isConnected = path.status == .satisfied
            }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }
}
