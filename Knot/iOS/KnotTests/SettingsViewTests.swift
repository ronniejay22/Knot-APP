//
//  SettingsViewTests.swift
//  KnotTests
//
//  Created on February 16, 2026.
//  Step 11.1: Unit tests for SettingsView and SettingsViewModel.
//  Step 11.2: Account deletion state management and ReauthenticationSheet tests.
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
        XCTAssertFalse(vm.showDeleteConfirmationSheet)
        XCTAssertFalse(vm.isDeletingAccount)
        XCTAssertNil(vm.deleteAccountError)
        XCTAssertFalse(vm.notificationsEnabled)
        XCTAssertFalse(vm.isUpdatingNotifications)
    }

    /// Verify showDeleteConfirmationSheet can be toggled.
    func testDeleteConfirmationSheetToggle() {
        let vm = SettingsViewModel()

        vm.showDeleteConfirmationSheet = true
        XCTAssertTrue(vm.showDeleteConfirmationSheet)

        vm.showDeleteConfirmationSheet = false
        XCTAssertFalse(vm.showDeleteConfirmationSheet)
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

    // MARK: - Account Deletion State Tests (Step 15.5)

    /// Verify new deletion state properties have correct defaults.
    func testDeletionInitialState() {
        let vm = SettingsViewModel()

        XCTAssertFalse(vm.showDeleteConfirmationSheet)
        XCTAssertFalse(vm.isDeletingAccount)
        XCTAssertNil(vm.deleteAccountError)
    }

    /// Verify requestAccountDeletion presents the typed-confirmation sheet directly.
    func testRequestAccountDeletionShowsConfirmationSheet() {
        let vm = SettingsViewModel()

        vm.requestAccountDeletion()
        XCTAssertTrue(vm.showDeleteConfirmationSheet)
    }

    /// Verify deleteAccountError can be set and cleared.
    func testDeleteAccountErrorCanBeSetAndCleared() {
        let vm = SettingsViewModel()

        vm.deleteAccountError = "Network error"
        XCTAssertEqual(vm.deleteAccountError, "Network error")

        vm.deleteAccountError = nil
        XCTAssertNil(vm.deleteAccountError)
    }

    /// Verify isDeletingAccount can be toggled.
    func testIsDeletingAccountToggle() {
        let vm = SettingsViewModel()

        vm.isDeletingAccount = true
        XCTAssertTrue(vm.isDeletingAccount)

        vm.isDeletingAccount = false
        XCTAssertFalse(vm.isDeletingAccount)
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

    /// Verify the typed-confirmation sheet renders without crashing.
    func testReauthenticationSheetRenders() {
        let view = ReauthenticationSheet(
            onConfirm: { true },
            onCancel: {}
        )
        let hostingController = UIHostingController(rootView: view)
        XCTAssertNotNil(hostingController.view, "ReauthenticationSheet should render a valid view")
    }
}
