//
//  SettingsViewTests.swift
//  KnotTests
//
//  Created on February 16, 2026.
//  Step 11.1: Unit tests for SettingsView and SettingsViewModel.
//

import XCTest
import SwiftUI
@testable import Knot

// MARK: - SettingsViewModel Tests

@MainActor
final class SettingsViewModelTests: XCTestCase {

    /// Verify ViewModel initializes with correct default state.
    func testInitialState() {
        let vm = SettingsViewModel()

        XCTAssertEqual(vm.userEmail, "")
        XCTAssertFalse(vm.isClearingHints)
        XCTAssertNil(vm.clearHintsError)
        XCTAssertFalse(vm.showClearHintsConfirmation)
        XCTAssertFalse(vm.showClearHintsSuccess)
        XCTAssertFalse(vm.showDeleteAccountAlert)
        XCTAssertFalse(vm.showExportDataAlert)
        XCTAssertFalse(vm.showQuietHoursAlert)
        XCTAssertFalse(vm.notificationsEnabled)
        XCTAssertFalse(vm.isUpdatingNotifications)
    }

    /// Verify appVersion returns a properly formatted version string.
    func testAppVersionFormat() {
        let vm = SettingsViewModel()
        let version = vm.appVersion

        // Should contain parentheses for build number
        XCTAssertTrue(version.contains("("), "Version should contain opening parenthesis")
        XCTAssertTrue(version.contains(")"), "Version should contain closing parenthesis")

        // Should match pattern "X.Y (N)" or "X.Y.Z (N)"
        let regex = try! NSRegularExpression(pattern: #"^\d+\.\d+(\.\d+)? \(\d+\)$"#)
        let range = NSRange(version.startIndex..., in: version)
        XCTAssertNotNil(regex.firstMatch(in: version, range: range),
                        "App version '\(version)' should match format 'X.Y.Z (N)'")
    }

    /// Verify showDeleteAccountAlert can be toggled.
    func testDeleteAccountAlertToggle() {
        let vm = SettingsViewModel()

        vm.showDeleteAccountAlert = true
        XCTAssertTrue(vm.showDeleteAccountAlert)

        vm.showDeleteAccountAlert = false
        XCTAssertFalse(vm.showDeleteAccountAlert)
    }

    /// Verify showClearHintsConfirmation can be toggled.
    func testClearHintsConfirmationToggle() {
        let vm = SettingsViewModel()

        vm.showClearHintsConfirmation = true
        XCTAssertTrue(vm.showClearHintsConfirmation)

        vm.showClearHintsConfirmation = false
        XCTAssertFalse(vm.showClearHintsConfirmation)
    }

    /// Verify showExportDataAlert can be toggled.
    func testExportDataAlertToggle() {
        let vm = SettingsViewModel()

        vm.showExportDataAlert = true
        XCTAssertTrue(vm.showExportDataAlert)

        vm.showExportDataAlert = false
        XCTAssertFalse(vm.showExportDataAlert)
    }

    /// Verify showQuietHoursAlert can be toggled.
    func testQuietHoursAlertToggle() {
        let vm = SettingsViewModel()

        vm.showQuietHoursAlert = true
        XCTAssertTrue(vm.showQuietHoursAlert)

        vm.showQuietHoursAlert = false
        XCTAssertFalse(vm.showQuietHoursAlert)
    }

    /// Verify notificationsEnabled can be toggled.
    func testNotificationsEnabledToggle() {
        let vm = SettingsViewModel()

        vm.notificationsEnabled = true
        XCTAssertTrue(vm.notificationsEnabled)

        vm.notificationsEnabled = false
        XCTAssertFalse(vm.notificationsEnabled)
    }

    /// Verify userEmail can be set.
    func testUserEmailCanBeSet() {
        let vm = SettingsViewModel()

        vm.userEmail = "test@example.com"
        XCTAssertEqual(vm.userEmail, "test@example.com")
    }

    /// Verify clearing hints initial state is correct.
    func testClearingHintsInitialState() {
        let vm = SettingsViewModel()

        XCTAssertFalse(vm.isClearingHints)
        XCTAssertNil(vm.clearHintsError)
        XCTAssertFalse(vm.showClearHintsSuccess)
    }

    /// Verify showClearHintsSuccess can be toggled.
    func testClearHintsSuccessToggle() {
        let vm = SettingsViewModel()

        vm.showClearHintsSuccess = true
        XCTAssertTrue(vm.showClearHintsSuccess)

        vm.showClearHintsSuccess = false
        XCTAssertFalse(vm.showClearHintsSuccess)
    }

    /// Verify clearHintsError can be set and cleared.
    func testClearHintsErrorCanBeSetAndCleared() {
        let vm = SettingsViewModel()

        vm.clearHintsError = "Network error"
        XCTAssertEqual(vm.clearHintsError, "Network error")

        vm.clearHintsError = nil
        XCTAssertNil(vm.clearHintsError)
    }
}

// MARK: - SettingsView Rendering Tests

@MainActor
final class SettingsViewRenderingTests: XCTestCase {

    /// Verify the SettingsView renders without crashing.
    func testViewRenders() {
        let view = SettingsView()
            .environment(AuthViewModel())
        let hostingController = UIHostingController(rootView: view)
        XCTAssertNotNil(hostingController.view, "SettingsView should render a valid view")
    }

    /// Verify the SettingsView renders in dark mode.
    func testViewRendersInDarkMode() {
        let view = SettingsView()
            .environment(AuthViewModel())
            .preferredColorScheme(.dark)
        let hostingController = UIHostingController(rootView: view)
        XCTAssertNotNil(hostingController.view, "SettingsView should render in dark mode")
    }
}
