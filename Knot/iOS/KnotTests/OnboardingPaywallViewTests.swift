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

    // MARK: - CTA title (Step 19.14: entitlement-aware)

    /// An already-entitled user (returning/restored subscriber, or leftover StoreKit
    /// test state) sees "Continue" — there is nothing left to purchase. This wins even
    /// when a trial offer is present or products haven't loaded.
    func testCTATitleIsContinueWhenAlreadySubscribed() {
        XCTAssertEqual(
            OnboardingPaywallView.ctaTitle(isSubscribed: true, hasTrial: true, productsLoaded: true),
            "Continue"
        )
        XCTAssertEqual(
            OnboardingPaywallView.ctaTitle(isSubscribed: true, hasTrial: false, productsLoaded: false),
            "Continue"
        )
    }

    /// A not-yet-subscribed user with an eligible free trial sees "Start Free Trial".
    func testCTATitleIsStartFreeTrialWhenTrialAvailable() {
        XCTAssertEqual(
            OnboardingPaywallView.ctaTitle(isSubscribed: false, hasTrial: true, productsLoaded: true),
            "Start Free Trial"
        )
    }

    /// Before products load, both plans are trial-eligible by design, so the CTA still
    /// leads with the free trial.
    func testCTATitleIsStartFreeTrialBeforeProductsLoad() {
        XCTAssertEqual(
            OnboardingPaywallView.ctaTitle(isSubscribed: false, hasTrial: false, productsLoaded: false),
            "Start Free Trial"
        )
    }

    /// Products loaded, no trial offer, not subscribed → a plain "Subscribe".
    func testCTATitleIsSubscribeWhenNoTrialAndLoaded() {
        XCTAssertEqual(
            OnboardingPaywallView.ctaTitle(isSubscribed: false, hasTrial: false, productsLoaded: true),
            "Subscribe"
        )
    }
}
