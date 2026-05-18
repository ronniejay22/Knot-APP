//
//  BudgetTierCard.swift
//  Knot
//
//  Shared budget tier card, preset range model, and toggle/sync helpers
//  used by the three per-tier onboarding screens and by EditBudgetSheet.
//

import SwiftUI

// MARK: - Dollar Formatting

/// Formats a cent amount as a currency string (e.g., "$50", "$1,000").
/// File-level so it's callable from `BudgetRangeOption` (non-isolated type).
func formatBudgetDollars(_ cents: Int) -> String {
    let dollars = cents / 100
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.groupingSeparator = ","
    let formatted = formatter.string(from: NSNumber(value: dollars)) ?? "\(dollars)"
    return "$\(formatted)"
}

// MARK: - Budget Range Option

/// A preset spending range for a budget tier (e.g., $20–$50).
///
/// Stores amounts in cents (matching the ViewModel / database convention).
struct BudgetRangeOption: Identifiable, Equatable, Sendable {
    var id: String { "\(minCents)-\(maxCents)" }
    let minCents: Int
    let maxCents: Int

    var label: String {
        "\(formatBudgetDollars(minCents)) – \(formatBudgetDollars(maxCents))"
    }
}

// MARK: - Preset Range Catalogues

enum BudgetPresets {
    /// Just Because: casual dates and small gifts.
    static let justBecause: [BudgetRangeOption] = [
        BudgetRangeOption(minCents: 500, maxCents: 2000),    // $5 – $20
        BudgetRangeOption(minCents: 2000, maxCents: 5000),   // $20 – $50  (default)
        BudgetRangeOption(minCents: 5000, maxCents: 10000),  // $50 – $100
        BudgetRangeOption(minCents: 10000, maxCents: 20000), // $100 – $200
    ]

    /// Minor Occasion: Mother's/Father's Day, smaller holidays.
    static let minorOccasion: [BudgetRangeOption] = [
        BudgetRangeOption(minCents: 2500, maxCents: 5000),   // $25 – $50
        BudgetRangeOption(minCents: 5000, maxCents: 15000),  // $50 – $150  (default)
        BudgetRangeOption(minCents: 15000, maxCents: 30000), // $150 – $300
        BudgetRangeOption(minCents: 30000, maxCents: 50000), // $300 – $500
    ]

    /// Major Milestone: birthday, anniversary, Christmas, Valentine's.
    static let majorMilestone: [BudgetRangeOption] = [
        BudgetRangeOption(minCents: 5000, maxCents: 10000),   // $50 – $100
        BudgetRangeOption(minCents: 10000, maxCents: 50000),  // $100 – $500  (default)
        BudgetRangeOption(minCents: 50000, maxCents: 75000),  // $500 – $750
        BudgetRangeOption(minCents: 75000, maxCents: 100000), // $750 – $1,000
    ]
}

// MARK: - Budget Tier Card

/// A card displaying a single budget tier with multi-select range buttons.
///
/// Visual design:
/// - Surface background with rounded corners and subtle border
/// - Accent-colored icon badge, title, subtitle, and "Select all" link
/// - 2-column grid of tappable range buttons (multiple can be selected)
/// - Selected button: accent fill, white text, accent border
/// - Unselected button: elevated surface fill, subtle border, primary text
/// - "Select all" in the title row selects every range in the tier
/// - At least one range must always remain selected (last one can't be deselected)
struct BudgetTierCard: View {
    let title: String
    let subtitle: String
    let icon: UIImage
    let accentColor: Color
    let options: [BudgetRangeOption]
    let selectedIDs: Set<String>
    let onToggle: (BudgetRangeOption) -> Void
    let onSelectAll: () -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 2)

    private var allSelected: Bool {
        options.allSatisfy { selectedIDs.contains($0.id) }
    }

    var body: some View {
        KnotCard(padding: .lg, radius: 16) {
            VStack(alignment: .leading, spacing: 14) {
                titleRow
                rangeGrid
            }
        }
    }

    private var titleRow: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(accentColor.opacity(0.15))
                .frame(width: 42, height: 42)
                .overlay {
                    Image(uiImage: icon)
                        .renderingMode(.template)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 20, height: 20)
                        .foregroundStyle(accentColor)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .knotFont(Theme.Typography.cardTitle)
                    .foregroundStyle(Theme.textPrimary)

                Text(subtitle)
                    .knotFont(Theme.Typography.label)
                    .foregroundStyle(Theme.textSecondary)
            }

            Spacer()

            Button {
                onSelectAll()
            } label: {
                Text(allSelected ? "All selected" : "Select all")
                    .knotFont(Theme.Typography.label)
                    .foregroundStyle(allSelected ? Theme.textTertiary : accentColor)
            }
            .buttonStyle(.plain)
            .disabled(allSelected)
            .animation(.easeInOut(duration: 0.2), value: allSelected)
        }
    }

    private var rangeGrid: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(options) { option in
                let isSelected = selectedIDs.contains(option.id)

                Button {
                    onToggle(option)
                } label: {
                    Text(option.label)
                        .knotFont(Theme.Typography.cta)
                        .monospacedDigit()
                        .foregroundStyle(isSelected ? .white : Theme.textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(isSelected ? accentColor : Theme.surfaceElevated)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(
                                    isSelected ? accentColor : Theme.surfaceBorder,
                                    lineWidth: isSelected ? 2 : 0.5
                                )
                        )
                }
                .buttonStyle(.plain)
                .animation(.easeInOut(duration: 0.2), value: isSelected)
            }
        }
    }
}

// MARK: - Toggle & Sync Helpers

/// Toggles a range in the set. At least one must remain selected.
func toggleBudgetRange(_ option: BudgetRangeOption, in ranges: inout Set<String>) {
    if ranges.contains(option.id) {
        guard ranges.count > 1 else { return }
        ranges.remove(option.id)
    } else {
        ranges.insert(option.id)
    }
}

/// Recomputes effective min/max from selected ranges and writes via the setters.
func syncEffectiveBudget(
    _ selectedIDs: Set<String>,
    options: [BudgetRangeOption],
    setMin: (Int) -> Void,
    setMax: (Int) -> Void
) {
    let selected = options.filter { selectedIDs.contains($0.id) }
    if let newMin = selected.map(\.minCents).min(),
       let newMax = selected.map(\.maxCents).max() {
        setMin(newMin)
        setMax(newMax)
    }
}
