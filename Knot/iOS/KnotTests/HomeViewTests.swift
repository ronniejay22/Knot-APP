//
//  HomeViewTests.swift
//  KnotTests
//
//  Step 18.2 (shadcn Phase 3): Render-without-crash tests for HomeView
//  after migration to Knot* primitives (KnotCard, KnotIconButton,
//  KnotSectionHeader, KnotBadge).
//  Step 18.6: Removed hint-success state test after standalone hint capture
//  was moved out of HomeView and into the recommendation refresh flow.
//

import XCTest
import SwiftUI
@testable import Knot

@MainActor
final class HomeViewTests: XCTestCase {

    /// Verify HomeView renders without crashing in its default (online) state.
    func testHomeViewRendersOnline() throws {
        let homeView = HomeView()
            .environment(AuthViewModel())
            .environment(NetworkMonitor())

        let host = UIHostingController(rootView: homeView)
        XCTAssertNotNil(host.view, "HomeView should render without crashing")
    }

    /// Verify HomeView renders the offline banner without crashing when
    /// network monitor reports disconnected.
    func testHomeViewRendersOffline() throws {
        let monitor = NetworkMonitor()
        monitor.isConnected = false

        let homeView = HomeView()
            .environment(AuthViewModel())
            .environment(monitor)

        let host = UIHostingController(rootView: homeView)
        XCTAssertNotNil(host.view, "HomeView should render the offline banner without crashing")
    }
}
