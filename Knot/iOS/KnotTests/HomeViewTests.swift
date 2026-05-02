//
//  HomeViewTests.swift
//  KnotTests
//
//  Step 18.2 (shadcn Phase 3): Render-without-crash tests for HomeView
//  after migration to Knot* primitives (KnotCard, KnotInput, KnotIconButton,
//  KnotSectionHeader, KnotBadge).
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

@MainActor
final class HomeViewModelHintSuccessStateTests: XCTestCase {

    /// Verify the success-overlay flag flips through its lifecycle.
    /// HomeView observes this flag to animate the green checkmark over KnotInput.
    func testShowHintSuccessFlag() {
        let vm = HomeViewModel()

        XCTAssertFalse(vm.showHintSuccess, "Initial state should be false")

        vm.showHintSuccess = true
        XCTAssertTrue(vm.showHintSuccess, "Flag should be settable")

        vm.showHintSuccess = false
        XCTAssertFalse(vm.showHintSuccess, "Flag should reset to false")
    }
}
