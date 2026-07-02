//
//  OnboardingCompletionViewContinueGatingTests.swift
//  KnotTests
//
//  Step 18.47: Verifies the gating that hides the onboarding "Continue" button
//  while the recommendation reveal is in progress. The button is shown when
//  `revealInProgress` is false (Continue visible) and hidden when true.
//
//  Step 19.7: Extends the coverage to `shouldShowContinue`, which additionally
//  requires the user to open at least one recommendation before "Continue" appears
//  in the loaded state — while still surfacing it immediately in the empty / error /
//  vault-failed states so the user is never trapped.
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

    // MARK: - shouldShowContinue (open-a-pick gating)

    private func shouldShow(
        vaultFailed: Bool = false,
        vaultReady: Bool = true,
        isLoading: Bool = false,
        isPlayingClimax: Bool = false,
        hasError: Bool = false,
        hasRecommendations: Bool = true,
        hasOpenedRecommendation: Bool = false
    ) -> Bool {
        OnboardingCompletionView.shouldShowContinue(
            vaultFailed: vaultFailed,
            vaultReady: vaultReady,
            isLoading: isLoading,
            isPlayingClimax: isPlayingClimax,
            hasError: hasError,
            hasRecommendations: hasRecommendations,
            hasOpenedRecommendation: hasOpenedRecommendation
        )
    }

    /// Loaded with picks but the user hasn't opened one yet → Continue hidden.
    func testHiddenWhenLoadedButNoPickOpened() {
        XCTAssertFalse(shouldShow(hasRecommendations: true, hasOpenedRecommendation: false))
    }

    /// Loaded with picks and the user opened one → Continue appears.
    func testShownWhenLoadedAndPickOpened() {
        XCTAssertTrue(shouldShow(hasRecommendations: true, hasOpenedRecommendation: true))
    }

    /// While the reveal is still in progress, Continue stays hidden even if a pick
    /// was somehow already opened.
    func testHiddenWhileRevealingRegardlessOfOpen() {
        XCTAssertFalse(shouldShow(vaultReady: false, isLoading: false, hasOpenedRecommendation: true))
        XCTAssertFalse(shouldShow(isLoading: true, hasOpenedRecommendation: true))
        XCTAssertFalse(shouldShow(isPlayingClimax: true, hasOpenedRecommendation: true))
    }

    /// Empty terminal state has nothing to open → Continue appears immediately.
    func testShownWhenEmptyEvenWithoutOpen() {
        XCTAssertTrue(shouldShow(hasRecommendations: false, hasOpenedRecommendation: false))
    }

    /// Generation-error terminal state must not trap the user → Continue appears.
    func testShownWhenErrorEvenWithoutOpen() {
        XCTAssertTrue(shouldShow(hasError: true, hasRecommendations: false, hasOpenedRecommendation: false))
    }

    /// Vault-failure state must not trap the user → Continue appears immediately.
    func testShownWhenVaultFailedEvenWithoutOpen() {
        XCTAssertTrue(shouldShow(vaultFailed: true, vaultReady: false, hasOpenedRecommendation: false))
    }
}
