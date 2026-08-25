//
//  MilestoneOccasionOption.swift
//  Knot
//
//  The occasions a user can pick when adding a milestone after onboarding.
//
//  Kept separate from `milestone_type` on purpose: that column is
//  CHECK-constrained to birthday / anniversary / holiday / custom, so every
//  occasion beyond those four is stored as `custom` plus an
//  `occasion_category`. Adding an occasion here needs no migration.
//

import Foundation

struct MilestoneOccasionOption: Identifiable, Sendable, Hashable {
    /// The persisted `occasion_category`.
    let id: String
    let displayName: String

    /// The `milestone_type` this occasion is stored under.
    let milestoneType: String

    /// True when the backend computes the real date from a calendar rule or
    /// lookup table, so the month/day the user picks is only a placeholder.
    let hasComputedDate: Bool

    static let defaultCategory = "default"

    init(
        id: String,
        displayName: String,
        milestoneType: String,
        hasComputedDate: Bool = false
    ) {
        self.id = id
        self.displayName = displayName
        self.milestoneType = milestoneType
        self.hasComputedDate = hasComputedDate
    }

    // MARK: - Catalogue

    /// Holidays, in roughly calendar order.
    static let holidays: [MilestoneOccasionOption] = [
        .init(id: "lunar_new_year", displayName: "Lunar New Year", milestoneType: "holiday", hasComputedDate: true),
        .init(id: "valentines_day", displayName: "Valentine's Day", milestoneType: "holiday"),
        .init(id: "eid", displayName: "Eid", milestoneType: "holiday", hasComputedDate: true),
        .init(id: "easter", displayName: "Easter", milestoneType: "holiday", hasComputedDate: true),
        .init(id: "mothers_day", displayName: "Mother's Day", milestoneType: "holiday", hasComputedDate: true),
        .init(id: "fathers_day", displayName: "Father's Day", milestoneType: "holiday", hasComputedDate: true),
        .init(id: "halloween", displayName: "Halloween", milestoneType: "holiday"),
        .init(id: "diwali", displayName: "Diwali", milestoneType: "holiday", hasComputedDate: true),
        .init(id: "thanksgiving", displayName: "Thanksgiving", milestoneType: "holiday", hasComputedDate: true),
        .init(id: "hanukkah", displayName: "Hanukkah", milestoneType: "holiday", hasComputedDate: true),
        .init(id: "christmas", displayName: "Christmas", milestoneType: "holiday"),
        .init(id: "new_years", displayName: "New Year's Eve", milestoneType: "holiday"),
    ]

    /// One-off moments in the partner's life.
    static let lifeEvents: [MilestoneOccasionOption] = [
        .init(id: "graduation", displayName: "Graduation", milestoneType: "custom"),
        .init(id: "new_job", displayName: "New Job or Promotion", milestoneType: "custom"),
        .init(id: "new_home", displayName: "New Home", milestoneType: "custom"),
        .init(id: "big_day", displayName: "A Big Day", milestoneType: "custom"),
        .init(id: "thinking_of_you", displayName: "A Hard Stretch", milestoneType: "custom"),
        .init(id: defaultCategory, displayName: "Something Else", milestoneType: "custom"),
    ]

    /// Occasions offered for a given `milestone_type`. Birthday and anniversary
    /// are their own category, so there is nothing to choose.
    static func options(for milestoneType: String) -> [MilestoneOccasionOption] {
        switch milestoneType {
        case "holiday": return holidays
        case "custom": return lifeEvents
        default: return []
        }
    }

    /// Options for a type, guaranteed to contain `selection`.
    ///
    /// Editing a legacy holiday whose name matched nothing — "Our Christmas in
    /// July" — hydrates the form with `default`, which isn't in `holidays`. A
    /// `Picker` with no matching tag renders blank, so keep the current value
    /// selectable instead of silently rewriting it.
    static func options(
        for milestoneType: String,
        including selection: String
    ) -> [MilestoneOccasionOption] {
        let base = options(for: milestoneType)
        guard !base.isEmpty, !base.contains(where: { $0.id == selection }) else {
            return base
        }
        let existing = option(id: selection)
            ?? .init(id: selection, displayName: "Other", milestoneType: milestoneType)
        return base + [existing]
    }

    static func option(id: String) -> MilestoneOccasionOption? {
        (holidays + lifeEvents).first { $0.id == id }
    }

    /// The category to store for a type the user cannot pick an occasion for.
    static func implicitCategory(for milestoneType: String) -> String? {
        switch milestoneType {
        case "birthday": return "birthday"
        case "anniversary": return "anniversary"
        default: return nil
        }
    }
}
