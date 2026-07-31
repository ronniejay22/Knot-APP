//
//  OnboardingPaywallViewTests.swift
//  KnotTests
//
//  Step 19.7: Covers the pure plan data backing the end-of-onboarding paywall
//  (`OnboardingPaywallView`). The view itself is presentational; these tests pin the
//  plan list's invariants and the default-selection rule so they don't drift when the
//  placeholder pricing is later swapped for StoreKit products.
//

import XCTest
@testable import Knot

@MainActor
final class OnboardingPaywallViewTests: XCTestCase {

    /// The paywall offers more than one plan (so the selectable-card UI is meaningful).
    func testOffersMultiplePlans() {
        XCTAssertGreaterThan(PaywallPlan.all.count, 1)
    }

    /// Exactly one plan is flagged "Most Popular" — the badge/highlight must be unambiguous.
    func testExactlyOnePopularPlan() {
        XCTAssertEqual(PaywallPlan.all.filter(\.isPopular).count, 1)
    }

    /// Plan identifiers are unique (they key the `ForEach` and any future purchase lookup).
    func testPlanIdentifiersAreUnique() {
        let ids = PaywallPlan.all.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count)
    }

    /// The default selection is the "Most Popular" plan.
    func testDefaultSelectionIsPopularPlan() {
        XCTAssertTrue(PaywallPlan.defaultSelection.isPopular)
    }

    /// The default selection is one of the offered plans (not a stray value).
    func testDefaultSelectionIsAnOfferedPlan() {
        XCTAssertTrue(PaywallPlan.all.contains(PaywallPlan.defaultSelection))
    }

    /// Every plan surfaces the copy the card renders — title, headline price, and
    /// per-week price are all non-empty.
    func testEveryPlanHasDisplayableCopy() {
        for plan in PaywallPlan.all {
            XCTAssertFalse(plan.title.isEmpty, "plan \(plan.id) missing title")
            XCTAssertFalse(plan.priceLabel.isEmpty, "plan \(plan.id) missing price")
            XCTAssertFalse(plan.perWeekLabel.isEmpty, "plan \(plan.id) missing per-week price")
        }
    }

    /// Every plan maps to a known StoreKit product identifier, so the purchase flow
    /// can always resolve a `Product` for the user's selection.
    func testEveryPlanMapsToAKnownProductID() {
        let known = Set(SubscriptionManager.ProductID.all)
        for plan in PaywallPlan.all {
            XCTAssertTrue(
                known.contains(plan.productID),
                "plan \(plan.id) maps to unknown product id \(plan.productID)"
            )
        }
    }

    /// Plan → product identifiers are unique, so two plans can't collide on one product.
    func testPlanProductIdentifiersAreUnique() {
        let productIDs = PaywallPlan.all.map(\.productID)
        XCTAssertEqual(productIDs.count, Set(productIDs).count)
    }

    // MARK: - Primary CTA (entitlement- and load-state-aware)

    /// An already-entitled user (returning/restored subscriber, or leftover StoreKit
    /// test state) sees "Continue" and the app-finish action — there is nothing left to
    /// purchase. This wins even when a trial offer is present or the load failed.
    func testPrimaryButtonIsContinueWhenAlreadySubscribed() {
        for state in [SubscriptionManager.ProductsState.loading, .loaded, .failed] {
            let button = OnboardingPaywallView.primaryButton(
                isSubscribed: true, state: state, hasTrial: true
            )
            XCTAssertEqual(button.title, "Continue")
            XCTAssertEqual(button.action, .continueApp)
            XCTAssertFalse(button.showsSpinner)
        }
    }

    /// While products are loading, the CTA leads with the free trial but spins — the
    /// spinner disables the button so it can't be tapped against a not-yet-loaded catalog.
    func testPrimaryButtonSpinsWhileLoading() {
        let button = OnboardingPaywallView.primaryButton(
            isSubscribed: false, state: .loading, hasTrial: false
        )
        XCTAssertEqual(button.title, "Start Free Trial")
        XCTAssertEqual(button.action, .purchase)
        XCTAssertTrue(button.showsSpinner)
    }

    /// When the catalog failed to load, the CTA becomes "Try Again" wired to a reload —
    /// never a silent no-op.
    func testPrimaryButtonIsTryAgainWhenLoadFailed() {
        let button = OnboardingPaywallView.primaryButton(
            isSubscribed: false, state: .failed, hasTrial: false
        )
        XCTAssertEqual(button.title, "Try Again")
        XCTAssertEqual(button.action, .retry)
        XCTAssertFalse(button.showsSpinner)
    }

    /// Loaded with an eligible free trial, not subscribed → "Start Free Trial" (no spinner).
    func testPrimaryButtonIsStartFreeTrialWhenLoadedWithTrial() {
        let button = OnboardingPaywallView.primaryButton(
            isSubscribed: false, state: .loaded, hasTrial: true
        )
        XCTAssertEqual(button.title, "Start Free Trial")
        XCTAssertEqual(button.action, .purchase)
        XCTAssertFalse(button.showsSpinner)
    }

    /// Loaded, no trial offer, not subscribed → a plain "Subscribe".
    func testPrimaryButtonIsSubscribeWhenLoadedWithoutTrial() {
        let button = OnboardingPaywallView.primaryButton(
            isSubscribed: false, state: .loaded, hasTrial: false
        )
        XCTAssertEqual(button.title, "Subscribe")
        XCTAssertEqual(button.action, .purchase)
        XCTAssertFalse(button.showsSpinner)
    }
}
