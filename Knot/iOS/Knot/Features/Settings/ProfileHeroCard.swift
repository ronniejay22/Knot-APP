//
//  ProfileHeroCard.swift
//  Knot
//
//  The couple card at the top of the Profile tab: the partner's initial,
//  "You & <partner>", how long they've been together and where, and an
//  Edit profile shortcut.
//

import SwiftUI

/// What the Profile hero displays, derived from the partner summary.
///
/// Pure so every formatting rule is unit-testable. It deliberately does not
/// reuse `relationshipTenureSummary` ("0 years, 5 months"), which is too long
/// for the hero's single subtitle line.
struct ProfileHeroContent: Equatable {

    enum TenureStyle {
        /// "3 yrs", "8 mos" — for the visible subtitle.
        case abbreviated
        /// "3 years", "8 months" — for VoiceOver.
        case spoken
    }

    let title: String
    /// The subtitle's parts ("Together 3 yrs", "Austin"): one line joined by
    /// " · " where it fits, stacked where it doesn't. Empty hides the line.
    let subtitleParts: [String]
    /// The name `PartnerInitialAvatar` draws its initial from ("" draws "?").
    let avatarName: String
    let accessibilityLabel: String

    /// The one-line subtitle, "Together 3 yrs · Austin", or nil when empty.
    var subtitle: String? {
        subtitleParts.isEmpty ? nil : subtitleParts.joined(separator: " · ")
    }

    /// Shown until the first partner load finishes. The text is redacted, so
    /// only its rough length matters.
    static let placeholder = ProfileHeroContent(
        title: "You & your partner",
        subtitleParts: ["Together 1 yr", "Your city"],
        avatarName: "",
        accessibilityLabel: "Loading profile"
    )

    /// Relationship length for the hero: whole months under a year, whole
    /// years (floored) after. Nil for a missing, zero, or negative tenure.
    static func tenure(months: Int?, style: TenureStyle) -> String? {
        guard let months, months > 0 else { return nil }
        if months < 12 {
            switch style {
            case .abbreviated: return months == 1 ? "1 mo" : "\(months) mos"
            case .spoken: return months == 1 ? "1 month" : "\(months) months"
            }
        }
        let years = months / 12
        switch style {
        case .abbreviated: return years == 1 ? "1 yr" : "\(years) yrs"
        case .spoken: return years == 1 ? "1 year" : "\(years) years"
        }
    }

    /// The city, else the state, else nil — trimmed, ignoring blanks.
    static func place(city: String?, state: String?) -> String? {
        for candidate in [city, state] {
            let trimmed = candidate?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !trimmed.isEmpty { return trimmed }
        }
        return nil
    }

    /// ["Together <tenure>", "<place>"], dropping whichever part is missing.
    static func detailParts(tenure: String?, place: String?) -> [String] {
        [tenure.map { "Together \($0)" }, place].compactMap { $0 }
    }
}

// In an extension so the memberwise init (used by `placeholder`) survives.
extension ProfileHeroContent {
    init(summary: PartnerProfileSummary?) {
        let name = summary?.partnerName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let months = summary?.relationshipTenureMonths
        let place = Self.place(city: summary?.locationCity, state: summary?.locationState)

        let spokenTitle = name.isEmpty ? "You and your partner" : "You and \(name)"
        let spokenParts = Self.detailParts(tenure: Self.tenure(months: months, style: .spoken), place: place)

        self.init(
            title: name.isEmpty ? "You & your partner" : "You & \(name)",
            subtitleParts: Self.detailParts(tenure: Self.tenure(months: months, style: .abbreviated), place: place),
            avatarName: name,
            accessibilityLabel: spokenParts.isEmpty
                ? spokenTitle
                : "\(spokenTitle). \(spokenParts.joined(separator: ", "))"
        )
    }
}

/// The couple card at the top of the Profile tab.
///
/// While the partner is loading, the text is redacted but Edit profile stays
/// live — it doesn't depend on the load.
struct ProfileHeroCard: View {

    let content: ProfileHeroContent
    let isPlaceholder: Bool
    let onEditProfile: @MainActor () -> Void

    private var redaction: RedactionReasons {
        isPlaceholder ? .placeholder : []
    }

    var body: some View {
        KnotCard(padding: .xl) {
            HStack(spacing: Theme.Spacing.lg) {
                PartnerInitialAvatar(name: content.avatarName, diameter: 56)
                    .redacted(reason: redaction)

                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text(content.title)
                        .knotFont(Theme.Typography.cardTitleSemibold)
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    if let subtitle = content.subtitle {
                        // One line where it fits. Beside the Edit profile pill
                        // a standard iPhone leaves ~120pt, so the parts stack
                        // rather than truncating the place away.
                        ViewThatFits(in: .horizontal) {
                            subtitleText(subtitle)
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(Array(content.subtitleParts.enumerated()), id: \.offset) { _, part in
                                    subtitleText(part)
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .redacted(reason: redaction)
                // One spoken sentence ("You and Jas. Together 3 years,
                // Austin") instead of the abbreviated "3 yrs · Austin".
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(content.accessibilityLabel)
                .accessibilityAddTraits(.isHeader)

                KnotButton(
                    "Edit profile",
                    variant: .outline,
                    size: .sm,
                    shape: .pill,
                    action: onEditProfile
                )
                .fixedSize()
            }
        }
    }

    private func subtitleText(_ text: String) -> some View {
        Text(text)
            .knotFont(Theme.Typography.label)
            .foregroundStyle(Theme.textSecondary)
            .lineLimit(1)
    }
}

// MARK: - Previews

#if DEBUG
#Preview("ProfileHeroCard") {
    ZStack {
        Theme.backgroundGradient.ignoresSafeArea()
        VStack(spacing: 16) {
            ProfileHeroCard(
                content: ProfileHeroContent(summary: PartnerProfileSummary(
                    partnerName: "Jas",
                    relationshipTenureMonths: 38,
                    locationCity: "Austin",
                    locationState: "TX"
                )),
                isPlaceholder: false,
                onEditProfile: {}
            )
            ProfileHeroCard(content: ProfileHeroContent(summary: nil), isPlaceholder: false, onEditProfile: {})
            ProfileHeroCard(content: .placeholder, isPlaceholder: true, onEditProfile: {})
        }
        .padding()
    }
}
#endif
