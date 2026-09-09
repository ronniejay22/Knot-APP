//
//  MilestoneRecommendationCopy.swift
//  Knot
//
//  The content framework behind `MilestoneRecommendationSheet` — the bottom
//  sheet a Journal card's recommendation icon raises before starting a ~30s
//  generation run.
//
//  Keyed on the milestone's `occasion_category`, the stable key resolved
//  server-side (backend `app/services/occasion_category.py`) and surfaced by
//  `MilestoneItemResponse.occasionCategory`, which is never empty — a legacy
//  row with a NULL column still lands on `default` rather than falling off the
//  end.
//
//  Why five framings rather than 22 templates
//  ------------------------------------------
//  `OccasionCopy` is the other occasion-keyed catalogue, and it holds one
//  hand-written template per category. That is right for `OccasionEntryModal`,
//  which fires *after* generation and announces a result ("Christmas is
//  {timing}! We've handpicked…"). This sheet fires *before* generation and asks
//  a question ("…?" / "We'll find…") — different tense, different job — so its
//  copy could not be reused, and mirroring its shape would mean 22 more strings
//  to keep in sync.
//
//  Instead a framing decides two things: the question the title asks, and which
//  recommendation types the body names. The occasion name, the timing phrase and
//  the partner's name are the fill. Bespoke per-occasion copy remains a one-map
//  addition on top — `framing(for:)` is the only lookup between a category and
//  its strings.
//
//  Why the body names a mix
//  ------------------------
//  The pipeline emits five recommendation types (`gift`, `experience`, `date`,
//  `idea`, `plan` — backend `app/agents/state.py`) and the unified system
//  prompt's DIVERSITY rule mixes them on every run. `OCCASION_GUIDANCE` varies
//  price and flavour by budget tier, not type. So naming a mix is true for every
//  framing; naming only gifts was not.
//

import Foundation

/// Fully resolved copy for one showing of the recommendation sheet.
struct MilestoneRecommendationCopy: Equatable {
    let badge: String
    let title: String
    let body: String
}

extension MilestoneRecommendationCopy {

    // MARK: - Framings

    /// How an occasion wants to be talked about, and what the recommendations
    /// for it are mostly made of.
    enum Framing: CaseIterable, Equatable {
        /// The occasion centres on giving them something — birthdays, the
        /// gifting holidays, life wins.
        case giftForward
        /// The occasion is something the two of you mark together.
        case sharedOccasion
        /// Showing up for them. Low-key, and never celebratory.
        case gesture
        /// No occasion at all.
        case spontaneous
        /// A category this build doesn't recognise, including `default`.
        /// Deliberately reachable: a key written by a newer backend must land
        /// on generic-but-correct copy, never on an empty sheet.
        case unknown
    }

    /// Unknown keys resolve to `.unknown` rather than trapping, so a category
    /// added on the backend can't break this screen.
    static func framing(for occasionCategory: String) -> Framing {
        framingByCategory[occasionCategory] ?? .unknown
    }

    /// Every category this file frames. Pinned in tests against
    /// `OccasionCopy.knownCategories`, so an occasion added to the copy
    /// catalogue cannot ship without a framing here.
    static var framedCategories: Set<String> { Set(framingByCategory.keys) }

    private static let framingByCategory: [String: Framing] = [
        // Gift-forward
        "birthday": .giftForward,
        "christmas": .giftForward,
        "hanukkah": .giftForward,
        "diwali": .giftForward,
        "lunar_new_year": .giftForward,
        "eid": .giftForward,
        "mothers_day": .giftForward,
        "fathers_day": .giftForward,
        "graduation": .giftForward,
        "new_job": .giftForward,
        "new_home": .giftForward,
        "hint_followup": .giftForward,

        // Shared occasion
        "anniversary": .sharedOccasion,
        "valentines_day": .sharedOccasion,
        "new_years": .sharedOccasion,
        "thanksgiving": .sharedOccasion,
        "easter": .sharedOccasion,
        "halloween": .sharedOccasion,

        // Gesture
        "thinking_of_you": .gesture,
        "big_day": .gesture,

        // Spontaneous
        "just_because": .spontaneous,

        // Fallback — `default` means "we don't know what this occasion is",
        // which is exactly what `.unknown` is for. Listed explicitly so the
        // parity test against `OccasionCopy.knownCategories` covers it.
        OccasionCopy.defaultCategory: .unknown,
    ]

    // MARK: - Resolution

    static func resolve(
        milestone: MilestoneItemResponse,
        partnerName: String,
        formattedDate: String
    ) -> MilestoneRecommendationCopy {
        let framing = framing(for: milestone.occasionCategory)

        return MilestoneRecommendationCopy(
            badge: badge(
                milestoneName: milestone.milestoneName,
                emoji: OccasionCopy.emoji(for: milestone.occasionCategory),
                formattedDate: formattedDate
            ),
            title: title(
                framing: framing,
                milestoneName: milestone.milestoneName,
                partnerName: partnerName
            ),
            body: body(
                framing: framing,
                milestoneName: milestone.milestoneName,
                partnerName: partnerName,
                daysUntil: milestone.daysUntil
            )
        )
    }

    // MARK: - Badge

    /// "🎄 Christmas · Dec 25", degrading to "Christmas · Dec 25" when the
    /// occasion has no emoji and to the bare name when the date is unavailable.
    static func badge(
        milestoneName: String,
        emoji: String?,
        formattedDate: String
    ) -> String {
        let name = milestoneName.trimmingCharacters(in: .whitespacesAndNewlines)
        let date = formattedDate.trimmingCharacters(in: .whitespacesAndNewlines)

        let leading = [emoji, name.isEmpty ? nil : name]
            .compactMap { $0 }
            .joined(separator: " ")

        guard !date.isEmpty else { return leading }
        guard !leading.isEmpty else { return date }
        return "\(leading) · \(date)"
    }

    // MARK: - Title

    /// The question the sheet asks. Never names a single recommendation type —
    /// that promise is what this framework exists to stop making.
    static func title(
        framing: Framing,
        milestoneName: String,
        partnerName: String
    ) -> String {
        let milestone = resolvedMilestoneName(milestoneName)
        let partner = resolvedPartnerName(partnerName)

        switch framing {
        case .giftForward, .unknown:
            return "Get ideas for \(milestone)?"
        case .sharedOccasion:
            return "Plan \(milestone) together?"
        case .gesture:
            return "Ways to show up for \(partner)?"
        case .spontaneous:
            return "Surprise \(partner) today?"
        }
    }

    // MARK: - Body

    /// Two sentences: what is coming and when, then what we'll go find.
    static func body(
        framing: Framing,
        milestoneName: String,
        partnerName: String,
        daysUntil: Int?
    ) -> String {
        [
            leadClause(framing: framing, milestoneName: milestoneName, daysUntil: daysUntil),
            offerClause(framing: framing, partnerName: partnerName),
        ]
        .compactMap { $0 }
        .joined(separator: " ")
    }

    /// "Christmas is in 175 days." — the contextual half.
    ///
    /// Returns `nil` when there is no day count, so an undated milestone
    /// degrades to the offer clause alone rather than asserting a timing it
    /// doesn't have. `.spontaneous` substitutes its own lead: a timing sentence
    /// is nonsense for an occasion that is the absence of one.
    static func leadClause(
        framing: Framing,
        milestoneName: String,
        daysUntil: Int?
    ) -> String? {
        if framing == .spontaneous { return "No occasion needed." }
        guard daysUntil != nil else { return nil }

        // `timingPhrase` is written to read correctly after "is" — "here",
        // "today", "tomorrow", "next week", "in 175 days". Reused rather than
        // re-derived so the two occasion surfaces phrase time identically.
        let timing = OccasionCopy.timingPhrase(daysUntil: daysUntil)
        return "\(resolvedMilestoneName(milestoneName)) is \(timing)."
    }

    /// What the sheet promises to go and find, per framing.
    ///
    /// Every variant ends with the same grounding tail — "built from their
    /// interests and how they like to be loved" — naming the two vault fields
    /// the user actually fills in and can still edit (Settings → Edit Profile →
    /// Interests / Love Languages), which the generation prompt reads on every
    /// run.
    ///
    /// **The tail must only name mechanisms the user can actually reach.** Two
    /// have already had to be removed for failing that test:
    ///
    /// - the comp's "her wishlist and past gifts" — the app has neither a
    ///   wishlist nor purchase history, and never collects a gender;
    /// - "the hints you've saved" — hint capture has had **no UI entry point**
    ///   since the Refresh button was removed, which left `SessionHintsSheet`
    ///   defined but never presented and `HintService.createHint` unreachable.
    ///   The backend still retrieves hints and feeds them to the prompt, so a
    ///   legacy row can still influence a result, but a user cannot add one —
    ///   and copy that invites them to is a promise the app can't keep.
    ///
    /// `testNoBodyClaimsAnythingTheAppDoesNotDo` forbids all of the above.
    /// Anything new added here has to be checked the same way: find the control
    /// that produces it, not just the field that stores it.
    static func offerClause(framing: Framing, partnerName: String) -> String {
        let partner = resolvedPartnerName(partnerName)

        switch framing {
        case .giftForward:
            return "We'll find gifts, experiences and plans for \(partner), built from their interests and how they like to be loved."
        case .sharedOccasion:
            // "for the two of you", not "to mark it" — the lead clause is
            // dropped for an undated milestone, and a pronoun with nothing to
            // refer back to would dangle.
            return "We'll find date plans, experiences and gifts for the two of you, built from \(partner)'s interests and how they like to be loved."
        case .gesture:
            return "We'll find small gestures, thoughtful gifts and low-key ideas for \(partner), built from their interests and how they like to be loved."
        case .spontaneous:
            return "We'll find small gifts, spontaneous dates and ideas for \(partner), built from their interests and how they like to be loved."
        case .unknown:
            return "We'll find gifts, dates and plans for \(partner), built from their interests and how they like to be loved."
        }
    }

    // MARK: - Names

    static func resolvedMilestoneName(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "this event" : trimmed
    }

    static func resolvedPartnerName(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "your partner" : trimmed
    }
}
