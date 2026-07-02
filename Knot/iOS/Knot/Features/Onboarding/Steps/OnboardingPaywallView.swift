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
//  NOTE: this is a branded UI screen only. It does not yet wire up StoreKit
//  purchases, receipt validation, or entitlements — both the CTA and the close (X)
//  simply finish onboarding and drop the user into the app. `PaywallPlan` is modeled
//  so real StoreKit `Product`s can replace the placeholder plans later without
//  touching the view layout.
//

import SwiftUI
import LucideIcons

/// A placeholder subscription plan rendered by `OnboardingPaywallView`. Purely
/// presentational for now — swap the static `all` list for StoreKit-derived
/// products when in-app purchases are wired up.
struct PaywallPlan: Identifiable, Equatable {
    let id: String
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

    /// The plans offered on the onboarding paywall. Placeholder pricing until
    /// StoreKit products are introduced.
    static let all: [PaywallPlan] = [
        PaywallPlan(
            id: "annual",
            title: "Knot Premium — 12 Months",
            priceLabel: "$59.99",
            perWeekLabel: "$1.15 / week",
            originalPriceLabel: "$119.88",
            isPopular: true
        ),
        PaywallPlan(
            id: "monthly",
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
    /// Invoked when the user taps the primary "Continue" CTA (chose a plan).
    let onContinue: () -> Void
    /// Invoked when the user dismisses the paywall via the close (X) button.
    let onClose: () -> Void

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
                    onSelect: { selectedPlan = plan }
                )
            }
        }
    }

    // MARK: - Footer (CTA + fine print)

    private var footer: some View {
        VStack(spacing: Theme.Spacing.md) {
            KnotButton("Continue", variant: .primary, size: .lg, action: onContinue)
                .frame(maxWidth: .infinity)

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

            finePrint
        }
        .padding(.horizontal, Theme.Spacing.xxl)
        .padding(.top, Theme.Spacing.md)
        .padding(.bottom, Theme.Spacing.lg)
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
    OnboardingPaywallView(onContinue: {}, onClose: {})
}
#endif
