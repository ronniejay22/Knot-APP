//
//  OnboardingBudgetView.swift
//  Knot
//
//  Created on February 7, 2026.
//  Step 3.1: Placeholder for onboarding Step 7 — Budget Tiers.
//  Step 3.7: Full implementation — dark-themed budget tier cards with
//            preset range buttons (multi-select) per occasion type.
//

import SwiftUI
import LucideIcons

/// Step 7: Set budget ranges for three occasion types.
///
/// Dark-themed screen with three budget tier cards, each containing
/// tappable preset range buttons. The user can select **multiple** ranges
/// per tier — the effective min/max is computed from the union of
/// selected ranges. A "Select all" button selects every range in the tier.
///
/// Tiers and preset ranges:
/// - **Just Because:** $5–$20, $20–$50 (default), $50–$100, $100–$200
/// - **Minor Occasion:** $25–$50, $50–$150 (default), $150–$300, $300–$500
/// - **Major Milestone:** $50–$100, $100–$500 (default), $500–$750, $750–$1,000
struct OnboardingBudgetView: View {
    @Environment(OnboardingViewModel.self) private var viewModel

    var body: some View {
        VStack(spacing: 0) {
            // MARK: - Header
            headerSection
                .padding(.horizontal, 24)
                .padding(.bottom, 20)

            // MARK: - Tier Cards
            ScrollView {
                VStack(spacing: 16) {
                    justBecauseTier
                    minorOccasionTier
                    majorMilestoneTier
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }
        }
        .onAppear {
            viewModel.validateCurrentStep()
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 8) {
            let name = viewModel.partnerName.trimmingCharacters(in: .whitespacesAndNewlines)
            let displayName = name.isEmpty ? "your partner" : name

            Text("Budget for \(displayName)")
                .font(.title.weight(.bold))
                .foregroundStyle(Theme.textPrimary)

            Text("Set comfortable spending ranges\nfor each type of occasion.")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
        }
        .padding(.top, 4)
    }

    // MARK: - Tier Cards

    private var justBecauseTier: some View {
        BudgetTierCard(
            title: "Just Because",
            subtitle: "Spontaneous dates & small surprises",
            icon: Lucide.coffee,
            accentColor: Color(hue: 0.50, saturation: 0.45, brightness: 0.75),
            options: Self.justBecauseOptions,
            selectedIDs: viewModel.justBecauseRanges,
            onToggle: { option in
                toggle(option, in: &viewModel.justBecauseRanges)
                syncBudget(viewModel.justBecauseRanges, options: Self.justBecauseOptions,
                           setMin: { viewModel.justBecauseMin = $0 },
                           setMax: { viewModel.justBecauseMax = $0 })
            },
            onSelectAll: {
                Self.justBecauseOptions.forEach { viewModel.justBecauseRanges.insert($0.id) }
                syncBudget(viewModel.justBecauseRanges, options: Self.justBecauseOptions,
                           setMin: { viewModel.justBecauseMin = $0 },
                           setMax: { viewModel.justBecauseMax = $0 })
            }
        )
    }

    private var minorOccasionTier: some View {
        BudgetTierCard(
            title: "Minor Occasion",
            subtitle: "Smaller holidays & celebrations",
            icon: Lucide.gift,
            accentColor: Color(hue: 0.08, saturation: 0.50, brightness: 0.85),
            options: Self.minorOccasionOptions,
            selectedIDs: viewModel.minorOccasionRanges,
            onToggle: { option in
                toggle(option, in: &viewModel.minorOccasionRanges)
                syncBudget(viewModel.minorOccasionRanges, options: Self.minorOccasionOptions,
                           setMin: { viewModel.minorOccasionMin = $0 },
                           setMax: { viewModel.minorOccasionMax = $0 })
            },
            onSelectAll: {
                Self.minorOccasionOptions.forEach { viewModel.minorOccasionRanges.insert($0.id) }
                syncBudget(viewModel.minorOccasionRanges, options: Self.minorOccasionOptions,
                           setMin: { viewModel.minorOccasionMin = $0 },
                           setMax: { viewModel.minorOccasionMax = $0 })
            }
        )
    }

    private var majorMilestoneTier: some View {
        BudgetTierCard(
            title: "Major Milestone",
            subtitle: "Birthdays, anniversaries & big holidays",
            icon: Lucide.sparkles,
            accentColor: Theme.accent,
            options: Self.majorMilestoneOptions,
            selectedIDs: viewModel.majorMilestoneRanges,
            onToggle: { option in
                toggle(option, in: &viewModel.majorMilestoneRanges)
                syncBudget(viewModel.majorMilestoneRanges, options: Self.majorMilestoneOptions,
                           setMin: { viewModel.majorMilestoneMin = $0 },
                           setMax: { viewModel.majorMilestoneMax = $0 })
            },
            onSelectAll: {
                Self.majorMilestoneOptions.forEach { viewModel.majorMilestoneRanges.insert($0.id) }
                syncBudget(viewModel.majorMilestoneRanges, options: Self.majorMilestoneOptions,
                           setMin: { viewModel.majorMilestoneMin = $0 },
                           setMax: { viewModel.majorMilestoneMax = $0 })
            }
        )
    }

    // MARK: - Toggle & Sync Helpers

    /// Toggles a range in the set. At least one must remain selected.
    private func toggle(_ option: BudgetRangeOption, in ranges: inout Set<String>) {
        if ranges.contains(option.id) {
            guard ranges.count > 1 else { return }
            ranges.remove(option.id)
        } else {
            ranges.insert(option.id)
        }
    }

    /// Recomputes effective min/max from selected ranges and writes to the ViewModel.
    private func syncBudget(
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

    // MARK: - Preset Range Options

    /// Just Because: casual dates and small gifts.
    fileprivate static let justBecauseOptions: [BudgetRangeOption] = [
        BudgetRangeOption(minCents: 500, maxCents: 2000),    // $5 – $20
        BudgetRangeOption(minCents: 2000, maxCents: 5000),   // $20 – $50  (default)
        BudgetRangeOption(minCents: 5000, maxCents: 10000),  // $50 – $100
        BudgetRangeOption(minCents: 10000, maxCents: 20000), // $100 – $200
    ]

    /// Minor Occasion: Mother's/Father's Day, smaller holidays.
    fileprivate static let minorOccasionOptions: [BudgetRangeOption] = [
        BudgetRangeOption(minCents: 2500, maxCents: 5000),   // $25 – $50
        BudgetRangeOption(minCents: 5000, maxCents: 15000),  // $50 – $150  (default)
        BudgetRangeOption(minCents: 15000, maxCents: 30000), // $150 – $300
        BudgetRangeOption(minCents: 30000, maxCents: 50000), // $300 – $500
    ]

    /// Major Milestone: birthday, anniversary, Christmas, Valentine's.
    fileprivate static let majorMilestoneOptions: [BudgetRangeOption] = [
        BudgetRangeOption(minCents: 5000, maxCents: 10000),   // $50 – $100
        BudgetRangeOption(minCents: 10000, maxCents: 50000),  // $100 – $500  (default)
        BudgetRangeOption(minCents: 50000, maxCents: 75000),  // $500 – $750
        BudgetRangeOption(minCents: 75000, maxCents: 100000), // $750 – $1,000
    ]
}

// MARK: - Dollar Formatting

/// Formats a cent amount as a currency string (e.g., "$50", "$1,000").
/// File-level function (not on the View) to avoid @MainActor isolation issues
/// when called from non-isolated types like `BudgetRangeOption`.
private func formatDollars(_ cents: Int) -> String {
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
/// The `label` is computed from `minCents` / `maxCents` using the dollar
/// formatter (e.g., "$20 – $50", "$750 – $1,000").
fileprivate struct BudgetRangeOption: Identifiable, Equatable, Sendable {
    var id: String { "\(minCents)-\(maxCents)" }
    let minCents: Int
    let maxCents: Int

    var label: String {
        "\(formatDollars(minCents)) – \(formatDollars(maxCents))"
    }
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
private struct BudgetTierCard: View {
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
        VStack(alignment: .leading, spacing: 14) {
            // MARK: Title Row
            HStack(spacing: 12) {
                // Icon badge
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
                        .font(.headline.weight(.bold))
                        .foregroundStyle(Theme.textPrimary)

                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }

                Spacer()

                // Select All button
                Button {
                    onSelectAll()
                } label: {
                    Text(allSelected ? "All selected" : "Select all")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(allSelected ? Theme.textTertiary : accentColor)
                }
                .buttonStyle(.plain)
                .disabled(allSelected)
                .animation(.easeInOut(duration: 0.2), value: allSelected)
            }

            // MARK: Range Buttons (2-column grid)
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(options) { option in
                    let isSelected = selectedIDs.contains(option.id)

                    Button {
                        onToggle(option)
                    } label: {
                        Text(option.label)
                            .font(.subheadline.weight(.medium).monospacedDigit())
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
        .padding(18)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Theme.surfaceBorder, lineWidth: 0.5)
        )
    }
}

// MARK: - Previews

#Preview("Default") {
    OnboardingBudgetView()
        .background(Theme.backgroundGradient.ignoresSafeArea())
        .environment(OnboardingViewModel())
}

#Preview("With Name") {
    let vm = OnboardingViewModel()
    vm.partnerName = "Alex"
    return OnboardingBudgetView()
        .background(Theme.backgroundGradient.ignoresSafeArea())
        .environment(vm)
}

#Preview("Multiple Selected") {
    let vm = OnboardingViewModel()
    vm.partnerName = "Jordan"
    vm.justBecauseRanges = ["500-2000", "2000-5000", "5000-10000"]
    vm.justBecauseMin = 500
    vm.justBecauseMax = 10000
    vm.minorOccasionRanges = ["5000-15000", "15000-30000"]
    vm.minorOccasionMin = 5000
    vm.minorOccasionMax = 30000
    vm.majorMilestoneRanges = ["5000-10000", "10000-50000", "50000-75000", "75000-100000"]
    vm.majorMilestoneMin = 5000
    vm.majorMilestoneMax = 100000
    return OnboardingBudgetView()
        .background(Theme.backgroundGradient.ignoresSafeArea())
        .environment(vm)
}
