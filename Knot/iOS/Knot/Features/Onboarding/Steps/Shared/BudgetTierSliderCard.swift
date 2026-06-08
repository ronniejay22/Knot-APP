//
//  BudgetTierSliderCard.swift
//  Knot
//
//  Shared budget tier card built around a dual-thumb range slider. Used by the
//  consolidated onboarding budget page and by the Settings → Edit Budget sheet.
//  Hosts the dollar formatter and the per-tier slider configuration.
//

import SwiftUI

// MARK: - Dollar Formatting

/// Formats a cent amount as a currency string (e.g., "$50", "$1,000").
/// File-level so it's callable from non-isolated contexts and the test target.
func formatBudgetDollars(_ cents: Int) -> String {
    let dollars = cents / 100
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.groupingSeparator = ","
    let formatted = formatter.string(from: NSNumber(value: dollars)) ?? "\(dollars)"
    return "$\(formatted)"
}

/// Formats a budget min–max range for summary display, rendering an open-ended
/// max (the `BudgetTierConfig.unlimitedMaxCents` sentinel) as "$min+" instead
/// of a literal "$1,000,000".
func formatBudgetRange(minCents: Int, maxCents: Int) -> String {
    let minStr = formatBudgetDollars(minCents)
    guard maxCents < BudgetTierConfig.unlimitedMaxCents else { return "\(minStr)+" }
    return "\(minStr) – \(formatBudgetDollars(maxCents))"
}

// MARK: - Tier Configuration

/// Per-tier slider bounds and step (all in cents). The `ceiling` is the
/// open-ended "+" point; reaching it stores `unlimitedMaxCents`.
enum BudgetTierConfig {
    /// Sentinel max representing "no upper limit" ($1,000,000). Safe across the
    /// DB (INTEGER, no upper CHECK), Pydantic (only validates max >= min >= 0),
    /// and all dollar formatters.
    static let unlimitedMaxCents = 100_000_000

    struct Tier {
        let lower: Int
        let ceiling: Int
        let step: Int
    }

    /// Just Because: casual dates and small gifts. $5–$200+, $5 step.
    static let justBecause = Tier(lower: 500, ceiling: 20000, step: 500)

    /// Minor Occasion: Mother's/Father's Day, smaller holidays. $25–$500+, $25 step.
    static let minorOccasion = Tier(lower: 2500, ceiling: 50000, step: 2500)

    /// Major Milestone: birthday, anniversary, Christmas. $50–$1,000+, $50 step.
    static let majorMilestone = Tier(lower: 5000, ceiling: 100000, step: 5000)
}

// MARK: - Budget Tier Slider Card

/// A card displaying a single budget tier with a dual-thumb range slider.
///
/// Visual design:
/// - Accent-colored icon badge, title, and subtitle
/// - A right-aligned "$X – $Y" readout (or "$X – $Y+" when open-ended)
/// - A `BudgetRangeSlider` tinted in the tier accent color
/// - Floor / ceiling end labels beneath the track
struct BudgetTierSliderCard: View {
    let title: String
    let subtitle: String
    let accent: Color
    let tier: BudgetTierConfig.Tier
    @Binding var minCents: Int
    @Binding var maxCents: Int

    private var maxReadout: String {
        maxCents >= tier.ceiling
            ? "\(formatBudgetDollars(tier.ceiling))+"
            : formatBudgetDollars(maxCents)
    }

    var body: some View {
        KnotCard(padding: .lg, radius: 16) {
            VStack(alignment: .leading, spacing: 14) {
                titleRow
                BudgetRangeSlider(
                    minCents: $minCents,
                    maxCents: $maxCents,
                    lower: tier.lower,
                    ceiling: tier.ceiling,
                    step: tier.step,
                    accent: accent
                )
                .padding(.horizontal, 2)
                endLabels
            }
        }
    }

    private var titleRow: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .knotFont(Theme.Typography.cardTitle)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text(subtitle)
                    .knotFont(Theme.Typography.label)
                    .foregroundStyle(Theme.textSecondary)
            }

            Spacer()

            Text("\(formatBudgetDollars(minCents)) – \(maxReadout)")
                .knotFont(Theme.Typography.cta)
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .fixedSize()
                .layoutPriority(1)
        }
    }

    private var endLabels: some View {
        HStack {
            Text(formatBudgetDollars(tier.lower))
            Spacer()
            Text("\(formatBudgetDollars(tier.ceiling))+")
        }
        .knotFont(Theme.Typography.label)
        .foregroundStyle(Theme.textTertiary)
    }
}

#Preview {
    struct Harness: View {
        @State private var minCents = 2000
        @State private var maxCents = 5000
        var body: some View {
            BudgetTierSliderCard(
                title: "Just Because",
                subtitle: "Spontaneous dates & small surprises",
                accent: Color(hue: 0.50, saturation: 0.45, brightness: 0.75),
                tier: BudgetTierConfig.justBecause,
                minCents: $minCents,
                maxCents: $maxCents
            )
            .padding(20)
            .background(Theme.backgroundGradient.ignoresSafeArea())
        }
    }
    return Harness()
}
