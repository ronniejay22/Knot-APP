//
//  SubscriptionManagerTests.swift
//  KnotTests
//
//  Step 19.8: Exercises `SubscriptionManager` against a local StoreKit test
//  session built from `Knot.storekit` (bundled into this test target). Covers
//  product loading, the 7-day free-trial introductory offer on each plan, a
//  successful purchase unlocking premium, and the unsubscribed default state.
//

import StoreKit
import StoreKitTest
import XCTest
@testable import Knot

@MainActor
final class SubscriptionManagerTests: XCTestCase {

    private var session: SKTestSession!

    override func setUpWithError() throws {
        session = try SKTestSession(configurationFileNamed: "Knot")
        session.disableDialogs = true
        // Start each test from a clean slate; `isSubscribed` is derived from these
        // transactions, so clearing them resets the entitlement.
        session.clearTransactions()
    }

    override func tearDownWithError() throws {
        session.clearTransactions()
        session = nil
    }

    // MARK: - Products

    func testLoadsBothProducts() async {
        let manager = SubscriptionManager()
        await manager.loadProducts()

        XCTAssertTrue(manager.productsLoaded)
        XCTAssertEqual(manager.products.count, 2)
        XCTAssertEqual(
            Set(manager.products.map(\.id)),
            Set(SubscriptionManager.ProductID.all)
        )
    }

    func testProductsAreInPaywallOrder() async {
        let manager = SubscriptionManager()
        await manager.loadProducts()
        // Annual first, monthly second — matches `PaywallPlan.all` / the card order.
        XCTAssertEqual(manager.products.map(\.id), SubscriptionManager.ProductID.all)
    }

    // MARK: - Load state

    /// A successful load against the local catalog resolves the state to `.loaded`
    /// (which is what `productsLoaded` reports), so the paywall shows its live CTA.
    func testProductsStateIsLoadedAfterSuccessfulLoad() async {
        let manager = SubscriptionManager()
        XCTAssertEqual(manager.productsState, .loading) // pre-load default
        await manager.loadProducts()
        XCTAssertEqual(manager.productsState, .loaded)
        XCTAssertTrue(manager.productsLoaded)
    }

    /// The DEBUG failure hook pins the state to `.failed` even across a `loadProducts()`
    /// call, so the screenshot harness can render the Try-Again recovery state.
    func testDebugProductsFailedPinsFailedStateAcrossLoad() async {
        let manager = SubscriptionManager(debugProductsFailed: true)
        XCTAssertEqual(manager.productsState, .failed)
        await manager.loadProducts()
        XCTAssertEqual(manager.productsState, .failed)
        XCTAssertFalse(manager.productsLoaded)
    }

    // MARK: - Free trial

    func testEachPlanHasSevenDayFreeTrial() async {
        let manager = SubscriptionManager()
        await manager.loadProducts()

        for plan in PaywallPlan.all {
            guard let product = manager.product(for: plan) else {
                return XCTFail("no product loaded for plan \(plan.id)")
            }
            guard let offer = product.subscription?.introductoryOffer else {
                return XCTFail("no introductory offer for plan \(plan.id)")
            }
            XCTAssertEqual(offer.paymentMode, .freeTrial, "plan \(plan.id) is not a free trial")
            // 7 days is configured as a 1-week period in StoreKit.
            XCTAssertEqual(offer.period.unit, .week)
            XCTAssertEqual(offer.period.value, 1)
            XCTAssertEqual(manager.trialLabel(for: plan), "7-day free trial")
        }
    }

    func testRenewalLabelReflectsPlanCadence() async throws {
        let manager = SubscriptionManager()
        await manager.loadProducts()

        let monthly = try XCTUnwrap(PaywallPlan.all.first { $0.id == "monthly" })
        let annual = try XCTUnwrap(PaywallPlan.all.first { $0.id == "annual" })
        XCTAssertEqual(manager.renewalLabel(for: monthly), "$9.99/month")
        XCTAssertEqual(manager.renewalLabel(for: annual), "$59.99/year")
    }

    // MARK: - Purchase / entitlement

    func testStartsUnsubscribed() async {
        let manager = SubscriptionManager()
        await manager.loadProducts()
        XCTAssertFalse(manager.isSubscribed)
    }

    func testPurchaseUnlocksPremium() async throws {
        let manager = SubscriptionManager()
        await manager.loadProducts()

        let monthly = try XCTUnwrap(PaywallPlan.all.first { $0.id == "monthly" })
        let unlocked = await manager.purchase(monthly)

        XCTAssertTrue(unlocked)
        XCTAssertTrue(manager.isSubscribed)
        XCTAssertNil(manager.purchaseError)
        XCTAssertFalse(manager.isPurchasing)
    }

    func testEntitlementSurvivesReload() async throws {
        let purchaser = SubscriptionManager()
        await purchaser.loadProducts()
        let annual = try XCTUnwrap(PaywallPlan.all.first { $0.id == "annual" })
        _ = await purchaser.purchase(annual)

        // A fresh manager (same process/session) should see the active entitlement.
        let observer = SubscriptionManager()
        await observer.loadProducts()
        XCTAssertTrue(observer.isSubscribed)
    }
}
