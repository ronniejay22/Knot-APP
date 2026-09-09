//
//  RecommendationDetailContent.swift
//  Knot
//
//  Created on September 8, 2026.
//  Pure derivations for the recommendation detail page's contextual chrome —
//  the category pill, the one-line meta row, and the three-column stats strip.
//  Takes primitive inputs (not the DTO) so each rule can be unit-tested the way
//  `RecommendationDetailView.saveCTAState` is, without hosting a view.
//

import Foundation

/// The copy behind the detail page's category pill, meta line, and stats strip.
///
/// Knot has no ratings, review counts, or booking volumes, so the strip is built
/// only from fields the pipeline actually populates: the matched vibes / love
/// languages / interests, the recommendation type, and the merchant. The four
/// pipeline scores (`interestScore` etc.) are deliberately **not** used — the
/// unified generator leaves them at 0, so a "match %" would be a fabrication.
enum RecommendationDetailContent {

    /// One column of the stats strip: a bold value over a small caption.
    struct Stat: Equatable {
        let value: String
        let label: String
        /// Renders the value in `Theme.accent` (the "Knot Pick" column).
        let isAccent: Bool
    }

    /// Ideas and date plans are both Knot Originals: no merchant, no link,
    /// saved rather than opened. Honors the `is_idea` flag and the two idea
    /// types, matching how `RecommendationCard` classifies the same item.
    nonisolated static func isIdea(type: String, isIdeaFlag: Bool?) -> Bool {
        isIdeaFlag == true || type == "idea" || type == "plan"
    }

    /// "City, ST" from the parts that are present; nil when both are empty.
    nonisolated static func locationText(city: String?, state: String?) -> String? {
        joinedLocation([city, state])
    }

    /// "Address, City, ST" for the "Where you'll meet" card — the same trim +
    /// join rule as `locationText`, so the two location surfaces on the page
    /// agree on what counts as present.
    nonisolated static func whereText(address: String?, city: String?, state: String?) -> String? {
        joinedLocation([address, city, state])
    }

    private nonisolated static func joinedLocation(_ raw: [String?]) -> String? {
        let parts = raw
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: ", ")
    }

    /// Total number of profile factors this recommendation matched.
    nonisolated static func matchCount(
        vibes: [String],
        loveLanguages: [String],
        interests: [String]
    ) -> Int {
        vibes.count + loveLanguages.count + interests.count
    }

    /// Uppercase eyebrow shown above the title: the first two matched vibes
    /// ("QUIET LUXURY & OUTDOORSY"), or the type label when nothing matched.
    nonisolated static func categoryLabel(vibes: [String], type: String) -> String {
        let names = vibes.prefix(2).map { OnboardingVibesView.displayName(for: $0) }
        guard !names.isEmpty else {
            return RecommendationTypeDisplay.label(for: type).uppercased()
        }
        return names.joined(separator: " & ").uppercased()
    }

    /// One-line "{location} • {merchant}" row under the title. Ideas carry no
    /// merchant, so they show location only. Nil when there is nothing to show.
    nonisolated static func metaLine(
        locationText: String?,
        merchantName: String?,
        isIdea: Bool
    ) -> String? {
        var parts: [String] = []
        if let location = locationText?.trimmingCharacters(in: .whitespacesAndNewlines), !location.isEmpty {
            parts.append(location)
        }
        if !isIdea, let merchant = merchantName?.trimmingCharacters(in: .whitespacesAndNewlines), !merchant.isEmpty {
            parts.append(merchant)
        }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " • ")
    }

    /// Caption under the "Knot Pick" value: the first matched love language,
    /// humanized ("Quality Time"), or "Hand-picked" when none matched.
    nonisolated static func knotPickLabel(loveLanguages: [String]) -> String {
        guard let first = loveLanguages.first else { return "Hand-picked" }
        return LoveLanguageDisplay.name(for: first)
    }

    /// Caption under the type value: "Knot Original" for ideas/plans, else the
    /// merchant, else a neutral "Purchasable".
    nonisolated static func typeStatLabel(isIdea: Bool, merchantName: String?) -> String {
        if isIdea { return "Knot Original" }
        if let merchant = merchantName?.trimmingCharacters(in: .whitespacesAndNewlines), !merchant.isEmpty {
            return merchant
        }
        return "Purchasable"
    }

    /// The three stats-strip columns, or nil when the item matched no profile
    /// factors at all (Saved-tab snapshots carry no matched arrays) — the strip
    /// is omitted rather than rendered with a "0".
    nonisolated static func stats(
        type: String,
        isIdea: Bool,
        merchantName: String?,
        vibes: [String],
        loveLanguages: [String],
        interests: [String]
    ) -> [Stat]? {
        let count = matchCount(vibes: vibes, loveLanguages: loveLanguages, interests: interests)
        guard count > 0 else { return nil }
        return [
            Stat(value: "\(count)", label: "Profile matches", isAccent: false),
            Stat(value: "Knot Pick", label: knotPickLabel(loveLanguages: loveLanguages), isAccent: true),
            Stat(
                value: RecommendationTypeDisplay.label(for: type),
                label: typeStatLabel(isIdea: isIdea, merchantName: merchantName),
                isAccent: false
            )
        ]
    }
}
