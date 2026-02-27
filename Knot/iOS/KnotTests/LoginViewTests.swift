//
//  LoginViewTests.swift
//  KnotTests
//
//  Created on February 26, 2026.
//  Tests for the multi-provider login flow.
//

import XCTest
@testable import Knot

final class LoginViewTests: XCTestCase {

    func testRedirectURLScheme() {
        let url = Constants.Supabase.redirectURL
        XCTAssertEqual(url.scheme, "com.ronniejay.knot", "Redirect URL scheme should match bundle identifier")
    }

    func testRedirectURLHost() {
        let url = Constants.Supabase.redirectURL
        XCTAssertEqual(url.host, "login-callback", "Redirect URL host should be login-callback")
    }

    func testRedirectURLFullString() {
        XCTAssertEqual(
            Constants.Supabase.redirectURL.absoluteString,
            "com.ronniejay.knot://login-callback",
            "Full redirect URL should match expected format"
        )
    }

    @MainActor
    func testAuthViewModelInitialState() {
        let vm = AuthViewModel()
        XCTAssertTrue(vm.isCheckingSession, "Should start checking session")
        XCTAssertFalse(vm.isLoading, "Should not be loading initially")
        XCTAssertFalse(vm.isAuthenticated, "Should not be authenticated initially")
        XCTAssertFalse(vm.hasCompletedOnboarding, "Should not have completed onboarding initially")
        XCTAssertFalse(vm.showError, "Should not show error initially")
        XCTAssertNil(vm.signInError, "Should have no error message initially")
    }
}
