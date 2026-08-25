//
//  OccasionCopy.swift
//  Knot
//
//  Per-occasion copy and illustration for the entry modal shown when a user
//  taps a milestone push notification.
//
//  Keyed on the milestone's `occasion_category` — the stable key resolved
//  server-side (see backend `app/services/occasion_category.py`), which is why
//  a legacy milestone with a NULL column still lands on a sensible entry here
//  rather than falling off the end.
//

import UIKit

/// Resolved copy for one occasion's entry modal.
struct OccasionCopy: Equatable {
    let title: String
    let body: String
    let ctaLabel: String

    /// Asset-catalog name for the illustration band, or `nil` when no artwork
    /// exists for this occasion. The modal renders title/body/CTA without an
    /// image in that case rather than showing a broken or placeholder band.
    let illustrationName: String?
}

extension OccasionCopy {

    // MARK: - Public API

    /// Builds the modal copy for a milestone.
    ///
    /// - Parameters:
    ///   - category: `occasion_category` from the milestone. Unknown values
    ///     fall back to `default`, so a key written by a newer backend can
    ///     never produce an empty modal.
    ///   - partnerName: Used for `{partner}`. Falls back to "your partner".
    ///   - daysUntil: Used for `{timing}`. `nil` for undated occasions.
    ///   - milestoneName: Used for `{milestone}` in the fallback copy.
    static func resolve(
        category: String,
        partnerName: String?,
        daysUntil: Int?,
        milestoneName: String?
    ) -> OccasionCopy {
        let template = templates[category] ?? templates[defaultCategory]!

        let partner = partnerName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedPartner = (partner?.isEmpty == false) ? partner! : "your partner"

        let milestone = milestoneName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedMilestone = (milestone?.isEmpty == false) ? milestone! : "Something special"

        let timing = timingPhrase(daysUntil: daysUntil)

        func fill(_ text: String) -> String {
            text
                .replacingOccurrences(of: "{partner}", with: resolvedPartner)
                .replacingOccurrences(of: "{milestone}", with: resolvedMilestone)
                .replacingOccurrences(of: "{timing}", with: timing)
        }

        return OccasionCopy(
            title: fill(template.title),
            body: fill(template.body),
            ctaLabel: template.ctaLabel,
            illustrationName: illustrationName(for: category)
        )
    }

    /// Every category this file has copy for. Used by tests to prove no
    /// occasion the backend can emit is missing an entry.
    static var knownCategories: Set<String> { Set(templates.keys) }

    static let defaultCategory = "default"

    // MARK: - Timing

    /// Turns a day count into a phrase that reads correctly after "is".
    ///
    /// Pushes fire at 14/7/3 days out, but the user may open the notification
    /// later, so every value has to produce something sensible — including
    /// same-day and past-due.
    static func timingPhrase(daysUntil: Int?) -> String {
        guard let days = daysUntil else { return "coming up" }

        switch days {
        case ..<0: return "here"
        case 0: return "today"
        case 1: return "tomorrow"
        case 7: return "next week"
        case 14: return "two weeks away"
        default: return "in \(days) days"
        }
    }

    // MARK: - Illustrations

    /// `occasion_category` → asset name, or nil when the artwork is absent.
    ///
    /// Checked against the bundle rather than assumed, so adding a missing
    /// illustration later (notably `occasion-default`) needs no code change.
    static func illustrationName(for category: String) -> String? {
        let slug = category.replacingOccurrences(of: "_", with: "-")
        let name = "OccasionIllustrations/occasion-\(slug)"
        return UIImage(named: name) != nil ? name : nil
    }

    // MARK: - Templates

    private struct Template {
        let title: String
        let body: String
        var ctaLabel: String = "See recommendations"
    }

    private static let templates: [String: Template] = [

        // MARK: Relationship

        "birthday": Template(
            title: "Happy Birthday to {partner}!",
            body: "{partner}'s birthday is {timing}! We've handcrafted some gifts and date ideas we know will hit the mark. Tell {partner} happy birthday from us :)"
        ),
        "anniversary": Template(
            title: "An Anniversary With {partner}!",
            body: "Your anniversary is {timing}! We've put together gift ideas and date plans to make it feel like more than a date on the calendar."
        ),

        // MARK: Romantic

        "valentines_day": Template(
            title: "Valentine's Day With {partner}!",
            body: "Valentine's is {timing}. We've gathered gifts and date ideas that go past the usual roses — picked around what {partner} actually loves."
        ),
        "new_years": Template(
            title: "Ring In The New Year With {partner}!",
            body: "New Year's Eve is {timing}. We've found ways to celebrate together — a big night out or something quieter at home."
        ),

        // MARK: Family role

        "mothers_day": Template(
            title: "Mother's Day Is Coming!",
            body: "Mother's Day is {timing}. We've found gifts and thoughtful gestures to celebrate everything {partner} is to your family."
        ),
        "fathers_day": Template(
            title: "Father's Day Is Coming!",
            body: "Father's Day is {timing}. We've pulled together gifts and plans {partner} will actually use — no last-minute scrambling this year."
        ),

        // MARK: Gifting season

        "christmas": Template(
            title: "Christmas With {partner}!",
            body: "Christmas is {timing}! We've handpicked gift ideas and festive plans to make this one land. Beat the shipping deadlines while you're at it."
        ),
        "hanukkah": Template(
            title: "Hanukkah With {partner}!",
            body: "Hanukkah begins {timing}. We've picked out gift ideas for the eight nights, chosen around what {partner} actually loves."
        ),
        "diwali": Template(
            title: "Diwali With {partner}!",
            body: "Diwali is {timing}. We've gathered gifts and ways to celebrate the festival of lights with {partner}."
        ),
        "lunar_new_year": Template(
            title: "Lunar New Year With {partner}!",
            body: "Lunar New Year is {timing}. We've found gifts and plans to welcome the year in alongside {partner}."
        ),
        "eid": Template(
            title: "Eid With {partner}!",
            body: "Eid is {timing}. We've put together gift ideas and ways to mark the day together with {partner}."
        ),

        // MARK: Seasonal

        "thanksgiving": Template(
            title: "Thanksgiving With {partner}!",
            body: "Thanksgiving is {timing}. We've gathered ideas to make the day feel warm — a small gift, a hosting hand, or a plan just for the two of you."
        ),
        "easter": Template(
            title: "Easter Is Almost Here!",
            body: "Easter is {timing}. We've found small gifts and spring plans to make the weekend with {partner} feel like something."
        ),
        "halloween": Template(
            title: "Halloween With {partner}!",
            body: "Halloween is {timing}. We've pulled together costume ideas, treats, and plans for a night out or a night in with {partner}."
        ),

        // MARK: Life events

        "graduation": Template(
            title: "{partner} Did It!",
            body: "{partner}'s graduation is {timing}. We've found gifts and ways to celebrate everything it took to get here."
        ),
        "new_job": Template(
            title: "A New Chapter For {partner}!",
            body: "{partner} is starting something new. We've pulled together gifts and ways to mark the win — however big they're letting you make it."
        ),
        "new_home": Template(
            title: "New Home, New Chapter!",
            body: "{partner} just moved in! We have housewarming gift ideas and decor inspiration to help make their new space feel like home."
        ),
        "big_day": Template(
            title: "{partner} Has A Big Day Coming!",
            body: "{partner}'s big day is {timing}. We've found small ways to show up beforehand — a gesture, a note, something to steady the nerves."
        ),
        // No exclamation mark, and a softer CTA: this fires after a hard week or
        // a loss, and the house voice needs to get out of the way.
        "thinking_of_you": Template(
            title: "Thinking Of {partner}",
            body: "It's been a heavy stretch for {partner}. We've gathered a few quiet ways to show up — nothing flashy, just thoughtful.",
            ctaLabel: "See ideas"
        ),

        // MARK: Non-date

        "just_because": Template(
            title: "Surprise {partner} Today!",
            body: "No occasion, no reason. We've pulled together small gifts and spontaneous date ideas to catch {partner} off guard."
        ),
        "hint_followup": Template(
            title: "{partner} Mentioned Something!",
            body: "You noted something {partner} said a while back. We've turned it into a few gift ideas before the moment passes."
        ),

        // MARK: Fallback

        defaultCategory: Template(
            title: "{milestone} Is Coming Up!",
            body: "{milestone} is {timing}. We've put together gift ideas and plans so you and {partner} can make the most of it."
        ),
    ]
}
