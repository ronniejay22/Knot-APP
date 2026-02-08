//
//  OnboardingCompletionView.swift
//  Knot
//
//  Created on February 7, 2026.
//  Step 3.1: Placeholder for onboarding Step 9 — Completion / Transition to Home.
//  Step 3.9: Full implementation — success header with comprehensive profile summary.
//

import SwiftUI
import LucideIcons

/// Step 9: Onboarding complete — shows a success celebration and full partner profile summary.
///
/// Displays a scrollable summary of all data entered during onboarding, organized into
/// visual sections: partner info, interests & dislikes, milestones, aesthetic vibes,
/// budget tiers, and love languages. Each section uses the same icons and display names
/// as its originating step for visual consistency.
///
/// The "Get Started" button is handled by `OnboardingContainerView`'s navigation bar
/// (it detects `.isLast` on the current step and swaps the Next button for Get Started).
///
/// Features:
/// - Animated success header with party popper icon and personalized message
/// - 6 summary sections matching the onboarding steps
/// - Vibes shown as colored accent pills
/// - Interests/dislikes as compact tags
/// - Upcoming milestone with computed date label
/// - Love languages with Primary/Secondary badges
/// - Budget tiers with formatted dollar ranges
struct OnboardingCompletionView: View {
    @Environment(OnboardingViewModel.self) private var viewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // MARK: - Success Header
                successHeader
                    .padding(.top, 8)

                // MARK: - Profile Summary Sections
                partnerInfoSection
                interestsSection
                milestonesSection
                vibesSection
                budgetSection
                loveLanguagesSection

                // MARK: - Footer Hint
                Text("Tap \"Get Started\" below to begin")
                    .font(.footnote)
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.top, 4)
                    .padding(.bottom, 16)
            }
            .padding(.horizontal, 20)
        }
    }

    // MARK: - Success Header

    private var successHeader: some View {
        VStack(spacing: 14) {
            Image(uiImage: Lucide.partyPopper)
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 64, height: 64)
                .foregroundStyle(Theme.accent)

            let name = viewModel.partnerName.trimmingCharacters(in: .whitespacesAndNewlines)

            Text("You're All Set!")
                .font(.system(size: 26, weight: .bold))
                .tracking(-0.5)
                .foregroundStyle(Theme.textPrimary)

            Text(name.isEmpty
                 ? "Your Partner Vault is ready.\nKnot will find personalized gifts, dates, and experiences."
                 : "\(name)'s vault is ready.\nKnot will find personalized gifts, dates, and experiences.")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
        }
        .padding(.bottom, 4)
    }

    // MARK: - Partner Info Section

    private var partnerInfoSection: some View {
        SummaryCard(icon: Lucide.user, title: "Partner Info") {
            VStack(alignment: .leading, spacing: 10) {
                if !viewModel.partnerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    summaryRow(label: "Name", value: viewModel.partnerName.trimmingCharacters(in: .whitespacesAndNewlines))
                }

                summaryRow(label: "Together", value: formatTenure(viewModel.relationshipTenureMonths))
                summaryRow(label: "Living", value: formatCohabitation(viewModel.cohabitationStatus))

                let city = viewModel.locationCity.trimmingCharacters(in: .whitespacesAndNewlines)
                let state = viewModel.locationState.trimmingCharacters(in: .whitespacesAndNewlines)
                let location = [city, state].filter { !$0.isEmpty }.joined(separator: ", ")
                if !location.isEmpty {
                    summaryRow(label: "Location", value: location)
                }
            }
        }
    }

    // MARK: - Interests & Dislikes Section

    private var interestsSection: some View {
        SummaryCard(icon: Lucide.sparkles, title: "Interests & Dislikes") {
            VStack(alignment: .leading, spacing: 14) {
                // Likes
                if !viewModel.selectedInterests.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Label {
                            Text("\(viewModel.selectedInterests.count) Likes")
                                .font(.caption.weight(.semibold))
                        } icon: {
                            Image(uiImage: Lucide.heart)
                                .renderingMode(.template)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 13, height: 13)
                        }
                        .foregroundStyle(Theme.accent)

                        FlowLayout(horizontalSpacing: 6, verticalSpacing: 6) {
                            ForEach(viewModel.selectedInterests.sorted(), id: \.self) { interest in
                                CompactTag(text: interest, style: .accent)
                            }
                        }
                    }
                }

                // Dislikes
                if !viewModel.selectedDislikes.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Label {
                            Text("\(viewModel.selectedDislikes.count) Hard Avoids")
                                .font(.caption.weight(.semibold))
                        } icon: {
                            Image(uiImage: Lucide.ban)
                                .renderingMode(.template)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 13, height: 13)
                        }
                        .foregroundStyle(Theme.textSecondary)

                        FlowLayout(horizontalSpacing: 6, verticalSpacing: 6) {
                            ForEach(viewModel.selectedDislikes.sorted(), id: \.self) { dislike in
                                CompactTag(text: dislike, style: .muted)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Milestones Section

    private var milestonesSection: some View {
        SummaryCard(icon: Lucide.calendar, title: "Milestones") {
            VStack(alignment: .leading, spacing: 10) {
                // Birthday (always present)
                milestoneRow(
                    icon: "birthday.cake.fill",
                    name: "Birthday",
                    date: formatMonthDay(month: viewModel.partnerBirthdayMonth, day: viewModel.partnerBirthdayDay)
                )

                // Anniversary (optional)
                if viewModel.hasAnniversary {
                    milestoneRow(
                        icon: "heart.circle.fill",
                        name: "Anniversary",
                        date: formatMonthDay(month: viewModel.anniversaryMonth, day: viewModel.anniversaryDay)
                    )
                }

                // Holidays
                let selectedHolidayObjects = HolidayOption.allHolidays.filter {
                    viewModel.selectedHolidays.contains($0.id)
                }
                ForEach(selectedHolidayObjects) { holiday in
                    milestoneRow(
                        icon: holiday.iconName,
                        name: holiday.displayName,
                        date: formatMonthDay(month: holiday.month, day: holiday.day)
                    )
                }

                // Custom milestones
                ForEach(viewModel.customMilestones) { milestone in
                    milestoneRow(
                        icon: "star.fill",
                        name: milestone.name,
                        date: formatMonthDay(month: milestone.month, day: milestone.day),
                        recurrence: milestone.recurrence
                    )
                }

                // Upcoming milestone indicator
                if let upcoming = nextUpcomingMilestone() {
                    HStack(spacing: 6) {
                        Image(uiImage: Lucide.bellRing)
                            .renderingMode(.template)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 12, height: 12)
                        Text("Next up: \(upcoming.name) \(upcoming.daysAway)")
                            .font(.caption)
                    }
                    .foregroundStyle(Theme.accent)
                    .padding(.top, 4)
                }
            }
        }
    }

    // MARK: - Vibes Section

    private var vibesSection: some View {
        SummaryCard(icon: Lucide.palette, title: "Aesthetic Vibes") {
            if viewModel.selectedVibes.isEmpty {
                Text("None selected")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textTertiary)
            } else {
                FlowLayout(horizontalSpacing: 8, verticalSpacing: 8) {
                    ForEach(viewModel.selectedVibes.sorted(), id: \.self) { vibe in
                        HStack(spacing: 5) {
                            Image(uiImage: OnboardingVibesView.vibeIcon(for: vibe))
                                .renderingMode(.template)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 13, height: 13)

                            Text(OnboardingVibesView.displayName(for: vibe))
                                .font(.caption.weight(.medium))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Theme.accent.opacity(0.75))
                        .clipShape(Capsule())
                    }
                }
            }
        }
    }

    // MARK: - Budget Section

    private var budgetSection: some View {
        SummaryCard(icon: Lucide.wallet, title: "Budget Tiers") {
            VStack(alignment: .leading, spacing: 10) {
                budgetRow(
                    icon: Lucide.coffee,
                    label: "Just Because",
                    min: viewModel.justBecauseMin,
                    max: viewModel.justBecauseMax
                )
                budgetRow(
                    icon: Lucide.gift,
                    label: "Minor Occasion",
                    min: viewModel.minorOccasionMin,
                    max: viewModel.minorOccasionMax
                )
                budgetRow(
                    icon: Lucide.sparkles,
                    label: "Major Milestone",
                    min: viewModel.majorMilestoneMin,
                    max: viewModel.majorMilestoneMax
                )
            }
        }
    }

    // MARK: - Love Languages Section

    private var loveLanguagesSection: some View {
        SummaryCard(icon: Lucide.heart, title: "Love Languages") {
            VStack(alignment: .leading, spacing: 10) {
                if !viewModel.primaryLoveLanguage.isEmpty {
                    loveLanguageRow(
                        language: viewModel.primaryLoveLanguage,
                        rank: "Primary"
                    )
                }
                if !viewModel.secondaryLoveLanguage.isEmpty {
                    loveLanguageRow(
                        language: viewModel.secondaryLoveLanguage,
                        rank: "Secondary"
                    )
                }
            }
        }
    }

    // MARK: - Reusable Row Components

    private func summaryRow(label: String, value: String) -> some View {
        HStack(spacing: 0) {
            Text(label)
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
                .frame(width: 68, alignment: .leading)

            Text(value)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.textPrimary)
        }
    }

    private func milestoneRow(icon: String, name: String, date: String, recurrence: String? = nil) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(Theme.accent)
                .frame(width: 18)

            Text(name)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.textPrimary)

            Spacer()

            Text(date)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)

            if let recurrence, recurrence == "one_time" {
                Text("once")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Theme.surface)
                    .clipShape(Capsule())
            }
        }
    }

    private func budgetRow(icon: UIImage, label: String, min: Int, max: Int) -> some View {
        HStack(spacing: 8) {
            Image(uiImage: icon)
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 14, height: 14)
                .foregroundStyle(Theme.accent)

            Text(label)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.textPrimary)

            Spacer()

            Text("\(formatDollars(min)) – \(formatDollars(max))")
                .font(.caption.weight(.medium))
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private func loveLanguageRow(language: String, rank: String) -> some View {
        HStack(spacing: 10) {
            Image(uiImage: OnboardingLoveLanguagesView.languageIcon(for: language))
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 16, height: 16)
                .foregroundStyle(rank == "Primary" ? Theme.accent : Theme.textSecondary)

            Text(OnboardingLoveLanguagesView.displayName(for: language))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.textPrimary)

            Spacer()

            Text(rank.uppercased())
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(rank == "Primary" ? Theme.accent : Theme.textSecondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    (rank == "Primary" ? Theme.accent : Theme.textSecondary).opacity(0.15)
                )
                .clipShape(Capsule())
        }
    }

    // MARK: - Formatting Helpers

    private func formatTenure(_ months: Int) -> String {
        let years = months / 12
        let remaining = months % 12
        if years == 0 {
            return "\(remaining) month\(remaining == 1 ? "" : "s")"
        } else if remaining == 0 {
            return "\(years) year\(years == 1 ? "" : "s")"
        } else {
            return "\(years)y \(remaining)m"
        }
    }

    private func formatCohabitation(_ status: String) -> String {
        switch status {
        case "living_together": return "Living Together"
        case "separate": return "Separate"
        case "long_distance": return "Long Distance"
        default: return status.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    private func formatMonthDay(month: Int, day: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        var components = DateComponents()
        components.month = month
        components.day = day
        components.year = 2000
        if let date = Calendar.current.date(from: components) {
            return formatter.string(from: date)
        }
        return "\(month)/\(day)"
    }

    /// Computes the next upcoming milestone from all entered milestones.
    private func nextUpcomingMilestone() -> (name: String, daysAway: String)? {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let currentYear = calendar.component(.year, from: today)

        // Gather all milestones with their month/day
        var milestones: [(name: String, month: Int, day: Int)] = []

        milestones.append(("Birthday", viewModel.partnerBirthdayMonth, viewModel.partnerBirthdayDay))

        if viewModel.hasAnniversary {
            milestones.append(("Anniversary", viewModel.anniversaryMonth, viewModel.anniversaryDay))
        }

        for holidayID in viewModel.selectedHolidays {
            if let holiday = HolidayOption.allHolidays.first(where: { $0.id == holidayID }) {
                milestones.append((holiday.displayName, holiday.month, holiday.day))
            }
        }

        for milestone in viewModel.customMilestones {
            milestones.append((milestone.name, milestone.month, milestone.day))
        }

        // Find the nearest future occurrence
        var nearest: (name: String, days: Int)?

        for m in milestones {
            var components = DateComponents()
            components.month = m.month
            components.day = m.day
            components.year = currentYear

            guard let thisYear = calendar.date(from: components) else { continue }

            let target: Date
            if thisYear >= today {
                target = thisYear
            } else {
                components.year = currentYear + 1
                guard let nextYear = calendar.date(from: components) else { continue }
                target = nextYear
            }

            let days = calendar.dateComponents([.day], from: today, to: target).day ?? 999
            if nearest == nil || days < nearest!.days {
                nearest = (m.name, days)
            }
        }

        guard let result = nearest else { return nil }
        let daysText: String
        if result.days == 0 {
            daysText = "is today!"
        } else if result.days == 1 {
            daysText = "is tomorrow"
        } else {
            daysText = "in \(result.days) days"
        }
        return (result.name, daysText)
    }
}

// MARK: - Summary Card Component

/// A reusable card container for profile summary sections.
/// Displays a Lucide icon + title header followed by custom content.
private struct SummaryCard<Content: View>: View {
    let icon: UIImage
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Section header
            HStack(spacing: 8) {
                Image(uiImage: icon)
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 16, height: 16)
                    .foregroundStyle(Theme.accent)

                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
            }

            // Section content
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Theme.surfaceBorder, lineWidth: 0.5)
        )
    }
}

// MARK: - Compact Tag Component

/// A small pill/chip used to display interests and dislikes compactly.
private struct CompactTag: View {
    let text: String
    let style: TagStyle

    enum TagStyle {
        case accent
        case muted
    }

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(style == .accent ? Theme.textPrimary : Theme.textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(style == .accent ? Theme.accent.opacity(0.18) : Theme.surface)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(
                        style == .accent ? Theme.accent.opacity(0.3) : Theme.surfaceBorder,
                        lineWidth: 0.5
                    )
            )
    }
}

// MARK: - Dollar Formatting (file-level to avoid @MainActor isolation)

/// Formats cents to a dollar string (e.g., 5000 → "$50").
private func formatDollars(_ cents: Int) -> String {
    let dollars = cents / 100
    return "$\(dollars)"
}

// MARK: - Previews

#Preview("Empty") {
    OnboardingCompletionView()
        .background(Theme.backgroundGradient.ignoresSafeArea())
        .environment(OnboardingViewModel())
}

#Preview("Full Profile") {
    let vm = OnboardingViewModel()
    vm.partnerName = "Alex"
    vm.relationshipTenureMonths = 26
    vm.cohabitationStatus = "living_together"
    vm.locationCity = "San Francisco"
    vm.locationState = "CA"
    vm.selectedInterests = ["Cooking", "Travel", "Photography", "Music", "Hiking"]
    vm.selectedDislikes = ["Gaming", "Sports", "Cars", "Skiing", "Surfing"]
    vm.partnerBirthdayMonth = 3
    vm.partnerBirthdayDay = 15
    vm.hasAnniversary = true
    vm.anniversaryMonth = 9
    vm.anniversaryDay = 22
    vm.selectedHolidays = ["valentines_day", "christmas"]
    vm.customMilestones = [
        CustomMilestone(name: "First Date", month: 6, day: 10, recurrence: "yearly"),
        CustomMilestone(name: "Trip to Paris", month: 11, day: 5, recurrence: "one_time")
    ]
    vm.selectedVibes = ["quiet_luxury", "romantic", "minimalist"]
    vm.justBecauseMin = 2000
    vm.justBecauseMax = 5000
    vm.minorOccasionMin = 5000
    vm.minorOccasionMax = 15000
    vm.majorMilestoneMin = 10000
    vm.majorMilestoneMax = 50000
    vm.primaryLoveLanguage = "quality_time"
    vm.secondaryLoveLanguage = "receiving_gifts"
    return OnboardingCompletionView()
        .background(Theme.backgroundGradient.ignoresSafeArea())
        .environment(vm)
}

#Preview("Minimal Profile") {
    let vm = OnboardingViewModel()
    vm.partnerName = "Jordan"
    vm.relationshipTenureMonths = 6
    vm.cohabitationStatus = "long_distance"
    vm.selectedInterests = ["Art", "Coffee", "Movies", "Yoga", "Baking"]
    vm.selectedDislikes = ["Cars", "DIY", "Gardening", "Running", "Cycling"]
    vm.partnerBirthdayMonth = 12
    vm.partnerBirthdayDay = 1
    vm.selectedVibes = ["bohemian"]
    vm.primaryLoveLanguage = "words_of_affirmation"
    vm.secondaryLoveLanguage = "acts_of_service"
    return OnboardingCompletionView()
        .background(Theme.backgroundGradient.ignoresSafeArea())
        .environment(vm)
}
