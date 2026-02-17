//
//  SettingsViewTests.swift
//  KnotTests
//
//  Created on February 16, 2026.
//  Step 11.1: Unit tests for SettingsView and SettingsViewModel.
//  Step 11.2: Account deletion state management and ReauthenticationSheet tests.
//  Step 11.3: Data export state management tests.
//  Step 11.4: Notification preferences state management tests.
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

    /// Verify showQuietHoursPicker can be toggled (Step 11.4).
    func testShowQuietHoursPickerToggle() {
        let vm = SettingsViewModel()

        vm.showQuietHoursPicker = true
        XCTAssertTrue(vm.showQuietHoursPicker)

        vm.showQuietHoursPicker = false
        XCTAssertFalse(vm.showQuietHoursPicker)
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

    // MARK: - Account Deletion State Tests (Step 11.2)

    /// Verify new deletion state properties have correct defaults.
    func testDeletionInitialState() {
        let vm = SettingsViewModel()

        XCTAssertFalse(vm.showReauthentication)
        XCTAssertFalse(vm.showFinalDeleteConfirmation)
        XCTAssertFalse(vm.isDeletingAccount)
        XCTAssertNil(vm.deleteAccountError)
        XCTAssertFalse(vm.isReauthenticated)
    }

    /// Verify requestAccountDeletion shows the warning alert.
    func testRequestAccountDeletionShowsAlert() {
        let vm = SettingsViewModel()

        vm.requestAccountDeletion()
        XCTAssertTrue(vm.showDeleteAccountAlert)
    }

    /// Verify confirmDeleteAndReauthenticate shows re-auth sheet.
    func testConfirmDeleteShowsReauthentication() {
        let vm = SettingsViewModel()

        vm.confirmDeleteAndReauthenticate()
        XCTAssertTrue(vm.showReauthentication)
    }

    /// Verify onReauthenticationSuccess sets correct state.
    func testReauthenticationSuccessState() {
        let vm = SettingsViewModel()

        vm.onReauthenticationSuccess()
        XCTAssertTrue(vm.isReauthenticated)
        XCTAssertFalse(vm.showReauthentication)
        XCTAssertTrue(vm.showFinalDeleteConfirmation)
    }

    /// Verify onReauthenticationFailure resets state.
    func testReauthenticationFailureState() {
        let vm = SettingsViewModel()

        vm.showReauthentication = true
        vm.onReauthenticationFailure()
        XCTAssertFalse(vm.isReauthenticated)
        XCTAssertFalse(vm.showReauthentication)
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

    // MARK: - Data Export State Tests (Step 11.3)

    /// Verify new export state properties have correct defaults.
    func testExportInitialState() {
        let vm = SettingsViewModel()

        XCTAssertFalse(vm.isExportingData)
        XCTAssertNil(vm.exportDataError)
        XCTAssertFalse(vm.showExportShareSheet)
        XCTAssertNil(vm.exportedFileURL)
    }

    /// Verify isExportingData can be toggled.
    func testIsExportingDataToggle() {
        let vm = SettingsViewModel()

        vm.isExportingData = true
        XCTAssertTrue(vm.isExportingData)

        vm.isExportingData = false
        XCTAssertFalse(vm.isExportingData)
    }

    /// Verify exportDataError can be set and cleared.
    func testExportDataErrorCanBeSetAndCleared() {
        let vm = SettingsViewModel()

        vm.exportDataError = "Network error"
        XCTAssertEqual(vm.exportDataError, "Network error")

        vm.exportDataError = nil
        XCTAssertNil(vm.exportDataError)
    }

    /// Verify showExportShareSheet can be toggled.
    func testShowExportShareSheetToggle() {
        let vm = SettingsViewModel()

        vm.showExportShareSheet = true
        XCTAssertTrue(vm.showExportShareSheet)

        vm.showExportShareSheet = false
        XCTAssertFalse(vm.showExportShareSheet)
    }

    /// Verify exportedFileURL can be set and cleared.
    func testExportedFileURLCanBeSetAndCleared() {
        let vm = SettingsViewModel()

        let testURL = URL(fileURLWithPath: "/tmp/test-export.pdf")
        vm.exportedFileURL = testURL
        XCTAssertEqual(vm.exportedFileURL, testURL)

        vm.exportedFileURL = nil
        XCTAssertNil(vm.exportedFileURL)
    }

    // MARK: - Notification Preferences State Tests (Step 11.4)

    /// Verify notification preferences initial state matches backend defaults.
    func testNotificationPreferencesInitialState() {
        let vm = SettingsViewModel()

        XCTAssertEqual(vm.quietHoursStart, 22, "Default quiet hours start should be 22 (10pm)")
        XCTAssertEqual(vm.quietHoursEnd, 8, "Default quiet hours end should be 8 (8am)")
        XCTAssertFalse(vm.showQuietHoursPicker)
        XCTAssertFalse(vm.isLoadingPreferences)
        XCTAssertFalse(vm.isSavingPreferences)
        XCTAssertNil(vm.preferencesError)
    }

    /// Verify quietHoursStart can be set.
    func testQuietHoursStartCanBeSet() {
        let vm = SettingsViewModel()

        vm.quietHoursStart = 21
        XCTAssertEqual(vm.quietHoursStart, 21)

        vm.quietHoursStart = 0
        XCTAssertEqual(vm.quietHoursStart, 0)

        vm.quietHoursStart = 23
        XCTAssertEqual(vm.quietHoursStart, 23)
    }

    /// Verify quietHoursEnd can be set.
    func testQuietHoursEndCanBeSet() {
        let vm = SettingsViewModel()

        vm.quietHoursEnd = 9
        XCTAssertEqual(vm.quietHoursEnd, 9)

        vm.quietHoursEnd = 0
        XCTAssertEqual(vm.quietHoursEnd, 0)

        vm.quietHoursEnd = 23
        XCTAssertEqual(vm.quietHoursEnd, 23)
    }

    /// Verify isLoadingPreferences can be toggled.
    func testIsLoadingPreferencesToggle() {
        let vm = SettingsViewModel()

        vm.isLoadingPreferences = true
        XCTAssertTrue(vm.isLoadingPreferences)

        vm.isLoadingPreferences = false
        XCTAssertFalse(vm.isLoadingPreferences)
    }

    /// Verify isSavingPreferences can be toggled.
    func testIsSavingPreferencesToggle() {
        let vm = SettingsViewModel()

        vm.isSavingPreferences = true
        XCTAssertTrue(vm.isSavingPreferences)

        vm.isSavingPreferences = false
        XCTAssertFalse(vm.isSavingPreferences)
    }

    /// Verify preferencesError can be set and cleared.
    func testPreferencesErrorCanBeSetAndCleared() {
        let vm = SettingsViewModel()

        vm.preferencesError = "Network error"
        XCTAssertEqual(vm.preferencesError, "Network error")

        vm.preferencesError = nil
        XCTAssertNil(vm.preferencesError)
    }

    /// Verify formatHour produces correct 12-hour time strings.
    func testFormatHour() {
        let vm = SettingsViewModel()

        XCTAssertEqual(vm.formatHour(0), "12:00 AM")
        XCTAssertEqual(vm.formatHour(1), "1:00 AM")
        XCTAssertEqual(vm.formatHour(8), "8:00 AM")
        XCTAssertEqual(vm.formatHour(11), "11:00 AM")
        XCTAssertEqual(vm.formatHour(12), "12:00 PM")
        XCTAssertEqual(vm.formatHour(13), "1:00 PM")
        XCTAssertEqual(vm.formatHour(22), "10:00 PM")
        XCTAssertEqual(vm.formatHour(23), "11:00 PM")
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

    /// Verify the ReauthenticationSheet renders without crashing (Step 11.2).
    func testReauthenticationSheetRenders() {
        let view = ReauthenticationSheet(
            onSuccess: {},
            onCancel: {}
        )
        let hostingController = UIHostingController(rootView: view)
        XCTAssertNotNil(hostingController.view, "ReauthenticationSheet should render a valid view")
    }
}
