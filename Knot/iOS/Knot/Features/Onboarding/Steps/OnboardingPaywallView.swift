//
//  OnboardingPaywallView.swift
//  Knot
//
//  Step 19.7: Subscription upsell shown at the very end of onboarding. After the
//  recommendation reveal, once the user has opened at least one pick and tapped
//  "Continue", this paywall is presented (see `OnboardingContainerView`). It mirrors
//  a standard app-store paywall layout: a benefit checklist, two selectable price
//  plans (one flagged "Most Popular"), a primary CTA, a cancel-anytime note, and
//  Terms / Privacy fine print.
//
//  Step 19.8: Wired the CTA to a real StoreKit 2 purchase via `SubscriptionManager`.
//  Selecting a plan and tapping the CTA starts that plan's 7-day free trial; the
//  subscription auto-renews at the plan's price after the trial ends. A successful
//  purchase (or a successful restore) finishes onboarding; the close (X) still skips
//  straight into the app. `PaywallPlan` now carries the StoreKit product identifier
//  it maps to, while its card copy stays the designed placeholder (mirroring
//  `Knot.storekit`) until real App Store Connect prices are localized.
//
//  Step 19.13: Made the paywall entitlement-aware. When `SubscriptionManager.isSubscribed`
//  is already true — a returning/restored subscriber, or leftover StoreKit test state in
//  the Simulator — the CTA reads "Continue" and finishes onboarding directly instead of
//  silently no-opping through a `product.purchase()` for an already-owned subscription
//  (which reads as "the trial steps didn't show; it just went to the next screen"). The
//  under-CTA line then states "You already have Knot Premium." The fresh-user trial flow
//  is unchanged.
//

import SwiftUI
import LucideIcons

/// A subscription plan rendered by `OnboardingPaywallView`. Its card copy is the
/// designed placeholder (mirroring `Knot.storekit`); `productID` maps it to the
/// StoreKit `Product` that `SubscriptionManager` purchases.
struct PaywallPlan: Identifiable, Equatable {
    let id: String
    /// The StoreKit product identifier this plan purchases (see `SubscriptionManager.ProductID`).
    let productID: String
    /// Display title, e.g. "Knot Premium — 12 Months".
    let title: String
    /// Headline price for the billing period, e.g. "$59.99".
    let priceLabel: String
    /// Normalized per-week price shown on the trailing edge, e.g. "$1.15 / week".
    let perWeekLabel: String
    /// Optional struck-through "was" price for discounted plans.
    let originalPriceLabel: String?
    /// Whether this plan carries the "Most Popular" badge and is selected by default.
    let isPopular: Bool

    /// The plans offered on the onboarding paywall. Card copy mirrors `Knot.storekit`
    /// until real App Store Connect prices are localized into the cards.
    static let all: [PaywallPlan] = [
        PaywallPlan(
            id: "annual",
            productID: SubscriptionManager.ProductID.annual,
            title: "Knot Premium — 12 Months",
            priceLabel: "$59.99",
            perWeekLabel: "$1.15 / week",
            originalPriceLabel: "$119.88",
            isPopular: true
        ),
        PaywallPlan(
            id: "monthly",
            productID: SubscriptionManager.ProductID.monthly,
            title: "Knot Premium — Monthly",
            priceLabel: "$9.99",
            perWeekLabel: "$2.30 / week",
            originalPriceLabel: nil,
            isPopular: false
        )
    ]

    /// The plan pre-selected when the paywall appears: the "Most Popular" plan when
    /// one is flagged, otherwise the first plan.
    static var defaultSelection: PaywallPlan {
        all.first(where: { $0.isPopular }) ?? all[0]
    }
}

/// The end-of-onboarding subscription paywall. Presented as a full-screen modal by
/// `OnboardingContainerView` once the user opens a pick and taps "Continue".
struct OnboardingPaywallView: View {
    /// Runs the StoreKit purchase and tracks the resulting entitlement. Owned by
    /// `OnboardingContainerView` and passed in so its state survives view rebuilds.
    let subscriptionManager: SubscriptionManager
    /// Invoked once the user has an active entitlement — a completed purchase or a
    /// successful restore. Finishes onboarding and enters the app.
    let onContinue: @MainActor () -> Void
    /// Invoked when the user dismisses the paywall via the close (X) button.
    /// `@MainActor`: wired to the close button's `@MainActor` action.
    let onClose: @MainActor () -> Void

    @State private var selectedPlan: PaywallPlan = PaywallPlan.defaultSelection

    private let plans = PaywallPlan.all

    /// Benefit bullets, one per checkmark row. Themed to Knot's relationship-
    /// intentionality value proposition.
    private let benefits = [
        "AI-powered gift and date ideas, personalized to your partner.",
        "Never miss a birthday, anniversary, or milestone again.",
        "Fresh \"Just Because\" recommendations every week.",
        "Thoughtful nudges that keep your relationship a priority."
    ]

    private let termsURL = URL(string: "https://knot-app.com/terms")!
    private let privacyURL = URL(string: "https://knot-app.com/privacy")!

    var body: some View {
        ZStack {
            Theme.backgroundGradient.ignoresSafeArea()

            VStack(spacing: 0) {
                closeRow

                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xxl) {
                        header
                        benefitList
                        planList
                    }
                    .padding(.horizontal, Theme.Spacing.xxl)
                    .padding(.top, Theme.Spacing.sm)
                    .padding(.bottom, Theme.Spacing.xl)
                }

                footer
            }
        }
        // Load real products (and refresh the entitlement) when the paywall appears.
        // Until this resolves, the cards render their placeholder copy.
        .task { await subscriptionManager.loadProducts() }
    }

    // MARK: - Close Row

    private var closeRow: some View {
        HStack {
            Spacer()
            KnotIconButton(icon: Lucide.x, variant: .ghost, size: .md, action: onClose)
        }
        .padding(.horizontal, Theme.Spacing.xxl)
        .padding(.top, Theme.Spacing.sm)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Your most thoughtful\nyear starts here")
                .knotFont(Theme.Typography.onboardingHeader)
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            // Short accent underline echoing the onboarding brand moments.
            RoundedRectangle(cornerRadius: 2)
                .fill(Theme.accent)
                .frame(width: 64, height: 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Benefits

    private var benefitList: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            ForEach(benefits, id: \.self) { line in
                HStack(alignment: .top, spacing: Theme.Spacing.md) {
                    Image(uiImage: Lucide.check)
                        .renderingMode(.template)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 20, height: 20)
                        .foregroundStyle(Theme.accent)

                    Text(line)
                        .knotFont(Theme.Typography.body)
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 0)
                }
            }
        }
    }

    // MARK: - Plans

    private var planList: some View {
        VStack(spacing: Theme.Spacing.md) {
            ForEach(plans) { plan in
                PaywallPlanCard(
                    plan: plan,
                    isSelected: plan == selectedPlan,
                    trialLabel: subscriptionManager.trialLabel(for: plan),
                    onSelect: {
                        selectedPlan = plan
                        // Drop any stale purchase/restore error when the user
                        // changes their selection.
                        subscriptionManager.purchaseError = nil
                    }
                )
            }
        }
    }

    // MARK: - Footer (CTA + fine print)

    private var footer: some View {
        VStack(spacing: Theme.Spacing.md) {
            if let error = subscriptionManager.purchaseError {
                Text(error)
                    .knotFont(Theme.Typography.label)
                    .foregroundStyle(Theme.accent)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .transition(.opacity)
            }

            KnotButton(
                ctaTitle,
                variant: .primary,
                size: .lg,
                isLoading: subscriptionManager.isPurchasing,
                action: startPurchase
            )
            .frame(maxWidth: .infinity)

            if let detail = ctaDetailText {
                // Either the trial → billing terms for the selected plan (e.g.
                // "7-day free trial, then $9.99/month") or, when already entitled,
                // a plain "You already have Knot Premium." note.
                Text(detail)
                    .knotFont(Theme.Typography.label)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: Theme.Spacing.sm) {
                Image(uiImage: Lucide.shieldCheck)
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 16, height: 16)
                    .foregroundStyle(Theme.textSecondary)

                Text("Cancel anytime in your subscription settings.")
                    .knotFont(Theme.Typography.label)
                    .foregroundStyle(Theme.textSecondary)
            }

            Button("Restore Purchases", action: restorePurchases)
                .knotFont(Theme.Typography.label)
                .foregroundStyle(Theme.textSecondary)
                .disabled(subscriptionManager.isPurchasing)

            finePrint
        }
        .padding(.horizontal, Theme.Spacing.xxl)
        .padding(.top, Theme.Spacing.md)
        .padding(.bottom, Theme.Spacing.lg)
        .animation(.easeInOut(duration: 0.2), value: subscriptionManager.purchaseError)
    }

    // MARK: - CTA copy & actions

    /// Resolves the primary CTA label from the current subscription state. Pure and
    /// static so it can be unit-tested without a live `SubscriptionManager`.
    /// - Already entitled → "Continue" (nothing to purchase).
    /// - A free trial is available, or products haven't loaded yet (both plans are
    ///   trial-eligible by design) → "Start Free Trial".
    /// - Otherwise → "Subscribe".
    static func ctaTitle(isSubscribed: Bool, hasTrial: Bool, productsLoaded: Bool) -> String {
        if isSubscribed { return "Continue" }
        if hasTrial || !productsLoaded { return "Start Free Trial" }
        return "Subscribe"
    }

    /// The primary CTA title for the current selection and entitlement.
    private var ctaTitle: String {
        Self.ctaTitle(
            isSubscribed: subscriptionManager.isSubscribed,
            hasTrial: subscriptionManager.trialLabel(for: selectedPlan) != nil,
            productsLoaded: subscriptionManager.productsLoaded
        )
    }

    /// The line rendered under the CTA. When the user already holds Premium it says so
    /// plainly (there's nothing to purchase); otherwise it spells out the selected
    /// plan's trial → billing terms.
    private var ctaDetailText: String? {
        if subscriptionManager.isSubscribed { return "You already have Knot Premium." }
        return trialDetailText
    }

    /// The trial → billing detail line for the selected plan, or nil until products
    /// (and their offers) have loaded.
    private var trialDetailText: String? {
        guard let trial = subscriptionManager.trialLabel(for: selectedPlan),
              let renewal = subscriptionManager.renewalLabel(for: selectedPlan) else { return nil }
        return "\(trial), then \(renewal)"
    }

    /// Purchases the selected plan; finishes onboarding only on a completed purchase.
    /// Cancel / pending leaves the user on the paywall (no error for a plain cancel).
    /// When the user already holds an active entitlement (a returning/restored
    /// subscriber, or leftover StoreKit test state) there's nothing to buy, so this
    /// finishes onboarding directly instead of silently no-opping through a purchase.
    /// `@MainActor`: passed as `KnotButton`'s `@MainActor` action; mutates view state.
    @MainActor
    private func startPurchase() {
        if subscriptionManager.isSubscribed {
            onContinue()
            return
        }
        Task {
            if await subscriptionManager.purchase(selectedPlan) {
                onContinue()
            }
        }
    }

    /// Restores a prior subscription; finishes onboarding if one is active.
    private func restorePurchases() {
        Task {
            if await subscriptionManager.restorePurchases() {
                onContinue()
            }
        }
    }

    private var finePrint: some View {
        VStack(spacing: Theme.Spacing.xxs) {
            Text("By continuing you agree to our")
                .knotFont(Theme.Typography.label)
                .foregroundStyle(Theme.textTertiary)

            HStack(spacing: Theme.Spacing.xs) {
                Link("Terms of Service", destination: termsURL)
                    .knotFont(Theme.Typography.label)
                    .foregroundStyle(Theme.accent)

                Text("and")
                    .knotFont(Theme.Typography.label)
                    .foregroundStyle(Theme.textTertiary)

                Link("Privacy Policy", destination: privacyURL)
                    .knotFont(Theme.Typography.label)
                    .foregroundStyle(Theme.accent)
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Plan Card

/// A single selectable price plan. Uses `KnotCard`'s elevated variant plus an accent
/// ring when selected, and shows a "Most Popular" badge straddling the top edge for
/// the recommended plan.
private struct PaywallPlanCard: View {
    let plan: PaywallPlan
    let isSelected: Bool
    /// A short free-trial label for this plan (e.g. "7-day free trial"), or nil
    /// until the StoreKit offer has loaded.
    let trialLabel: String?
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            KnotCard(variant: isSelected ? .elevated : .default, padding: .lg) {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Text(plan.title)
                        .knotFont(Theme.Typography.cardTitle)
                        .foregroundStyle(Theme.textPrimary)

                    HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
                        Text(plan.priceLabel)
                            .knotFont(Theme.Typography.numeric)
                            .foregroundStyle(Theme.textPrimary)

                        if let originalPriceLabel = plan.originalPriceLabel {
                            Text(originalPriceLabel)
                                .knotFont(Theme.Typography.body)
                                .foregroundStyle(Theme.textTertiary)
                                .strikethrough()
                        }

                        Spacer(minLength: Theme.Spacing.sm)

                        Text(plan.perWeekLabel)
                            .knotFont(Theme.Typography.cta)
                            .foregroundStyle(Theme.accent)
                    }

                    if let trialLabel {
                        Text(trialLabel)
                            .knotFont(Theme.Typography.label)
                            .foregroundStyle(Theme.accent)
                    }
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.lg)
                    .stroke(isSelected ? Theme.accent : Color.clear, lineWidth: 2)
            )
            .overlay(alignment: .topTrailing) {
                if plan.isPopular {
                    Text("MOST POPULAR")
                        .knotFont(Theme.Typography.label)
                        .foregroundStyle(.white)
                        .padding(.horizontal, Theme.Spacing.md)
                        .padding(.vertical, Theme.Spacing.xs)
                        .background(Capsule().fill(Theme.accent))
                        .offset(x: -Theme.Spacing.md, y: -Theme.Spacing.md)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    OnboardingPaywallView(
        subscriptionManager: SubscriptionManager(),
        onContinue: {},
        onClose: {}
    )
}
#endif
