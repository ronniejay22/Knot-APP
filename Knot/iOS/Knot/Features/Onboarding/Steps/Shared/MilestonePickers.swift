//
//  MilestonePickers.swift
//  Knot
//
//  Shared month/day picker UI used by the birthday, anniversary, and
//  custom-milestone onboarding screens.
//

import SwiftUI

/// Localized month names ("January" … "December"), cached once.
enum MilestoneMonthNames {
    static let all: [String] = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        return formatter.monthSymbols
    }()
}

/// A styled month picker (January through December).
@MainActor
func milestoneMonthPicker(
    selection: Binding<Int>,
    label: String = "Month"
) -> some View {
    VStack(alignment: .leading, spacing: 4) {
        Text(label)
            .knotFont(Theme.Typography.label)
            .foregroundStyle(Theme.textTertiary)

        Picker(label, selection: selection) {
            ForEach(1...12, id: \.self) { month in
                Text(MilestoneMonthNames.all[month - 1]).tag(month)
            }
        }
        .pickerStyle(.menu)
        .tint(Theme.accent)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
}

/// A styled day picker (1 through daysInMonth).
@MainActor
func milestoneDayPicker(
    selection: Binding<Int>,
    daysInMonth: Int,
    label: String = "Day"
) -> some View {
    VStack(alignment: .leading, spacing: 4) {
        Text(label)
            .knotFont(Theme.Typography.label)
            .foregroundStyle(Theme.textTertiary)

        Picker(label, selection: selection) {
            ForEach(1...daysInMonth, id: \.self) { day in
                Text("\(day)").tag(day)
            }
        }
        .pickerStyle(.menu)
        .tint(Theme.accent)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
}

/// Formats a month/day pair as a human-readable string (e.g., "February 14").
func formattedMilestoneDate(month: Int, day: Int) -> String {
    guard month >= 1, month <= 12 else { return "" }
    return "\(MilestoneMonthNames.all[month - 1]) \(day)"
}
