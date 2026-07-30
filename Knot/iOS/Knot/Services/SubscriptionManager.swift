//
//  SubscriptionManager.swift
//  Knot
//
//  Step 19.8: Wires the end-of-onboarding paywall to real StoreKit 2 purchases.
//  Loads the Knot Premium subscription products, runs the purchase flow (which
//  applies each product's 7-day free-trial introductory offer when the user is
//  eligible), verifies and finishes transactions, and tracks the resulting
//  premium entitlement. See `OnboardingPaywallView` for the UI that drives it and
//  `Knot.storekit` for the local product catalog used in the simulator.
//
//  Scope: this is the CLIENT-side purchase experience. Server-side receipt
//  validation / App Store Server Notifications (syncing entitlement to the
//  backend) is a documented follow-up — see memory-bank/progress.md Step 19.8.
//

import StoreKit

/// Owns the StoreKit product catalog, the purchase flow, and the premium
/// entitlement for the onboarding paywall.
///
/// Follows the app's `@Observable @MainActor` service convention (see
/// `AuthViewModel`). A single instance is created and owned by
/// `OnboardingContainerView` and passed into `OnboardingPaywallView`.
@Observable
@MainActor
final class SubscriptionManager {

    // MARK: - Product Identifiers

    /// App Store product identifiers. These MUST match both `Knot.storekit`
    /// (local testing) and the auto-renewable subscriptions created in App Store
    /// Connect before release.
    enum ProductID {
        static let annual = "com.knot.premium.annual"
        static let monthly = "com.knot.premium.monthly"

        /// All identifiers in paywall display order (annual first, monthly second).
        static let all = [annual, monthly]
    }

    // MARK: - Published State

    /// The loaded StoreKit products, in paywall display order. Empty until
    /// `loadProducts()` succeeds.
    private(set) var products: [Product] = []

    /// True once `loadProducts()` has returned products (drives whether the UI
    /// shows real prices/trial copy vs. the static placeholder labels).
    private(set) var productsLoaded = false

    /// True while a purchase or restore network round-trip is in flight. Drives
    /// the CTA's loading spinner and disabled state.
    var isPurchasing = false

    /// A user-facing error message for the most recent failed purchase/restore,
    /// or nil. User-cancelled purchases do NOT set this (cancelling is not an error).
    var purchaseError: String?

    /// True when the user holds an active Knot Premium entitlement. Always derived
    /// from `Transaction.currentEntitlements` (device/Apple-ID scoped) — never
    /// persisted, so it can't leak premium across app accounts on the same device.
    private(set) var isSubscribed = false

    // MARK: - Private

    // Not observation-tracked, and `nonisolated(unsafe)` so `deinit` — a nonisolated
    // context under Swift 6 strict concurrency — may cancel it. Only ever assigned
    // once, in `init`.
    @ObservationIgnored private nonisolated(unsafe) var updatesTask: Task<Void, Never>?

    enum SubscriptionError: Error {
        case failedVerification
    }

    // MARK: - Lifecycle

    init() {
        // Observe transactions that arrive outside the direct purchase call —
        // renewals, Ask-to-Buy approvals, and purchases restored on another
        // device — so the entitlement stays current for the app's lifetime.
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                guard let self else { return }
                await self.handle(transactionResult: update)
            }
        }
    }

    deinit {
        updatesTask?.cancel()
    }

#if DEBUG
    /// Screenshot/preview override. When true, the manager reports an active Premium
    /// entitlement without a live StoreKit transaction so the paywall's already-
    /// subscribed "Continue" state can be rendered deterministically — the paywall's
    /// `.task`-driven `refreshEntitlements()` would otherwise reset `isSubscribed` to
    /// false in a harness with no real purchase. Never set in shipping code.
    private var debugForceSubscribed = false

    /// Screenshot/preview-only convenience: a manager pre-marked as subscribed, used by
    /// `UITestScreenshotHarness` to capture the entitlement-aware "Continue" paywall.
    convenience init(debugSubscribed: Bool) {
        self.init()
        debugForceSubscribed = debugSubscribed
        isSubscribed = debugSubscribed
    }
#endif

    // MARK: - Products

    /// Loads the Knot Premium products from the App Store (or the local
    /// `.storekit` catalog in the simulator) and refreshes the entitlement.
    /// Failures leave `productsLoaded == false` so the paywall keeps rendering
    /// its placeholder pricing.
    func loadProducts() async {
        do {
            let fetched = try await Product.products(for: ProductID.all)
            products = fetched.sorted { lhs, rhs in
                (ProductID.all.firstIndex(of: lhs.id) ?? .max)
                    < (ProductID.all.firstIndex(of: rhs.id) ?? .max)
            }
            productsLoaded = !products.isEmpty
        } catch {
            productsLoaded = false
        }
        // Always recompute the entitlement, even when product loading fails —
        // `currentEntitlements` is read locally and doesn't depend on the catalog,
        // so a load failure can't strand a stale `isSubscribed`.
        await refreshEntitlements()
    }

    /// The loaded `Product` backing a paywall plan, or nil if products haven't
    /// loaded (or the id is unknown).
    func product(for plan: PaywallPlan) -> Product? {
        products.first { $0.id == plan.productID }
    }

    // MARK: - Purchase

    /// Runs the StoreKit purchase for the selected plan. When the plan carries an
    /// eligible free-trial introductory offer, StoreKit applies it automatically
    /// (the user isn't charged until the trial ends, then it auto-renews at the
    /// plan's price).
    ///
    /// - Returns: `true` when the purchase completes and premium is unlocked.
    ///   `false` for user-cancel, pending/deferred, or failure (`purchaseError`
    ///   is set for genuine failures only).
    func purchase(_ plan: PaywallPlan) async -> Bool {
        guard let product = product(for: plan) else {
            purchaseError = "This plan isn't available right now. Please try again."
            return false
        }

        isPurchasing = true
        purchaseError = nil
        defer { isPurchasing = false }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await transaction.finish()
                await refreshEntitlements()
                return isSubscribed
            case .userCancelled:
                // Not an error — the user backed out of the sheet.
                return false
            case .pending:
                // Deferred (e.g. Ask to Buy). The entitlement, if approved,
                // arrives later via `Transaction.updates`.
                return false
            @unknown default:
                return false
            }
        } catch {
            purchaseError = "Your purchase couldn't be completed. Please try again."
            return false
        }
    }

    // MARK: - Restore

    /// Restores previously purchased subscriptions (App Store requirement).
    /// - Returns: `true` if an active entitlement was found after syncing.
    func restorePurchases() async -> Bool {
        isPurchasing = true
        purchaseError = nil
        defer { isPurchasing = false }

        do {
            try await AppStore.sync()
            await refreshEntitlements()
            if !isSubscribed {
                purchaseError = "No active subscription to restore."
            }
            return isSubscribed
        } catch {
            purchaseError = "We couldn't restore your purchases. Please try again."
            return false
        }
    }

    // MARK: - Entitlements

    /// Recomputes `isSubscribed` from the current, unexpired, non-revoked
    /// entitlements for the Knot Premium products.
    func refreshEntitlements() async {
#if DEBUG
        // Screenshot/preview override — keep the forced entitlement instead of
        // recomputing it from (absent) real transactions.
        if debugForceSubscribed {
            isSubscribed = true
            return
        }
#endif
        var active = false
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            if transaction.productType == .autoRenewable,
               ProductID.all.contains(transaction.productID),
               transaction.revocationDate == nil {
                active = true
            }
        }
        isSubscribed = active
    }

    private func handle(transactionResult: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = transactionResult else { return }
        await transaction.finish()
        await refreshEntitlements()
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw SubscriptionError.failedVerification
        case .verified(let safe):
            return safe
        }
    }

    // MARK: - Trial / Offer Display

    /// A compact label for a plan's introductory free trial (e.g. "7-day free
    /// trial"), or nil when the loaded product has no eligible free-trial offer.
    func trialLabel(for plan: PaywallPlan) -> String? {
        guard let offer = product(for: plan)?.subscription?.introductoryOffer,
              offer.paymentMode == .freeTrial else { return nil }
        return "\(offer.period.knotShortLabel) free trial"
    }

    /// The post-trial renewal label for a plan (e.g. "$9.99/month"), pulled from
    /// the loaded product, or nil when products haven't loaded.
    func renewalLabel(for plan: PaywallPlan) -> String? {
        guard let product = product(for: plan),
              let period = product.subscription?.subscriptionPeriod else { return nil }
        return "\(product.displayPrice)/\(period.knotUnitLabel)"
    }
}

// MARK: - Period Formatting

extension Product.SubscriptionPeriod {
    /// A compact human description like "7-day", "1-month", or "1-year". Weeks are
    /// expanded to days so a 1-week trial reads as the expected "7-day".
    var knotShortLabel: String {
        switch unit {
        case .day: return "\(value)-day"
        case .week: return "\(value * 7)-day"
        case .month: return "\(value)-month"
        case .year: return "\(value)-year"
        @unknown default: return "\(value)-period"
        }
    }

    /// A billing-cadence unit label like "month" or "year" (pluralized when the
    /// period spans more than one unit), for renewal copy such as "$9.99/month".
    var knotUnitLabel: String {
        let name: String
        switch unit {
        case .day: name = "day"
        case .week: name = "week"
        case .month: name = "month"
        case .year: name = "year"
        @unknown default: name = "period"
        }
        return value > 1 ? "\(value) \(name)s" : name
    }
}
