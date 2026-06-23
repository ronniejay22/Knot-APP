//
//  OnboardingCompletionViewContinueGatingTests.swift
//  KnotTests
//
//  Step 18.47: Verifies the gating that hides the onboarding "Continue" button
//  while the recommendation reveal is in progress. The button is shown when
//  `revealInProgress` is false (Continue visible) and hidden when true.
//

import XCTest
@testable import Knot

@MainActor
final class OnboardingCompletionViewContinueGatingTests: XCTestCase {

    private func revealing(
        vaultFailed: Bool = false,
        vaultReady: Bool = false,
        isLoading: Bool = false,
        isPlayingClimax: Bool = false
    ) -> Bool {
        OnboardingCompletionView.revealInProgress(
            vaultFailed: vaultFailed,
            vaultReady: vaultReady,
            isLoading: isLoading,
            isPlayingClimax: isPlayingClimax
        )
    }

    /// At reveal start the vault is not yet created — Continue stays hidden.
    func testInProgressWhileVaultCreating() {
        XCTAssertTrue(revealing(vaultReady: false, isLoading: false))
    }

    /// After the vault is ready, recommendation generation keeps it hidden.
    func testInProgressWhileGenerating() {
        XCTAssertTrue(revealing(vaultReady: true, isLoading: true))
    }

    /// The climax celebration keeps Continue hidden even once loading finishes.
    func testInProgressDuringClimax() {
        XCTAssertTrue(revealing(vaultReady: true, isLoading: false, isPlayingClimax: true))
    }

    /// Loaded terminal state: generation done, no climax → Continue appears.
    func testNotInProgressWhenLoaded() {
        XCTAssertFalse(revealing(vaultReady: true, isLoading: false, isPlayingClimax: false))
    }

    /// Empty terminal state behaves the same as loaded → Continue appears.
    func testNotInProgressWhenEmpty() {
        XCTAssertFalse(revealing(vaultReady: true, isLoading: false, isPlayingClimax: false))
    }

    /// Vault-failure error state must not trap the user — Continue appears
    /// regardless of vaultReady/isLoading, since the error branch is terminal.
    func testNotInProgressWhenVaultFailed() {
        XCTAssertFalse(revealing(vaultFailed: true, vaultReady: false, isLoading: false))
        XCTAssertFalse(revealing(vaultFailed: true, vaultReady: false, isLoading: true))
    }
}
