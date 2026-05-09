//
//  RecommendationCard.swift
//  Knot
//
//  Created on February 10, 2026.
//

import SwiftUI
import LucideIcons

/// A compact recommendation card built for the Choice-of-Three pager.
///
/// The card is a *decision aid*, not a product page — it surfaces only the signal
/// needed to confidently pick one of three options, while merchant, location, full
/// description, and full match factors remain available in the confirm sheet.
///
/// Layout (top to bottom):
/// ```
/// ┌─────────────────────────────────────┐
/// │ [Hero image — 160pt]                │
/// │  ┌Gift┐                  ┌$49┐ ┌🔖┐│
/// │  └────┘                  └───┘ └──┘│
/// ├─────────────────────────────────────┤
/// │ Title (2 lines max)                 │
/// │ ✨ Why Knot picked this — 1 line    │
/// │ ❤ Art   ✨ Romantic   +2            │
/// │ ┌──── Select ────┐                  │
/// └─────────────────────────────────────┘
/// ```
struct RecommendationCard: View {

    // MARK: - Properties

    let title: String
    let descriptionText: String?
    let recommendationType: String
    let priceCents: Int?
    let currency: String
    let priceConfidence: String
    let imageURL: String?
    let isSaved: Bool
    let matchedInterests: [String]
    let matchedVibes: [String]
    let matchedLoveLanguages: [String]
    let personalizationNote: String?
    let onSelect: @MainActor @Sendable () -> Void
    let onSave: @MainActor @Sendable () -> Void

    // MARK: - Constants

    private let cardCornerRadius: CGFloat = 18
    private let heroHeight: CGFloat = 160
    private let maxVisibleChips: Int = 3

    // MARK: - Body

    var body: some View {
        KnotCard(variant: .default, padding: .none, radius: cardCornerRadius) {
            VStack(alignment: .leading, spacing: 0) {
                heroSection
                detailsSection
            }
        }
    }

    // MARK: - Hero Image Section

    private var heroSection: some View {
        ZStack(alignment: .top) {
            // Background: async image or gradient fallback
            if let imageURL, let url = URL(string: imageURL) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(minWidth: 0, maxWidth: .infinity)
                            .frame(height: heroHeight)
                            .clipped()
                    case .failure:
                        fallbackGradient
                    case .empty:
                        ZStack {
                            fallbackGradient
                            ProgressView()
                                .tint(.white.opacity(0.5))
                        }
                    @unknown default:
                        fallbackGradient
                    }
                }
            } else {
                fallbackGradient
            }

            // Top edge gradient for overlay readability
            VStack {
                LinearGradient(
                    colors: [.black.opacity(0.35), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 60)
                Spacer()
            }

            // Top row: type badge (left) + price + save (right)
            HStack(alignment: .top) {
                typeBadge
                Spacer()
                HStack(spacing: 8) {
                    priceOverlay
                    saveOverlay
                }
            }
            .padding(12)
        }
        .frame(height: heroHeight)
        .clipped()
    }

    // MARK: - Gradient Fallback

    private var fallbackGradient: some View {
        ZStack {
            LinearGradient(
                colors: fallbackGradientColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Image(systemName: typeIconSystemName)
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.white.opacity(0.15))
        }
    }

    private var fallbackGradientColors: [Color] {
        switch recommendationType {
        case "gift":
            return [Color.pink.opacity(0.4), Color.purple.opacity(0.3)]
        case "experience":
            return [Color.blue.opacity(0.4), Color.indigo.opacity(0.3)]
        case "date":
            return [Color.orange.opacity(0.3), Color.pink.opacity(0.4)]
        case "idea":
            return [Color.yellow.opacity(0.3), Color.orange.opacity(0.3)]
        default:
            return [Color.purple.opacity(0.3), Color.pink.opacity(0.3)]
        }
    }

    // MARK: - Hero Overlays

    private var typeBadge: some View {
        HStack(spacing: 5) {
            Image(uiImage: typeIconLucide)
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 12, height: 12)

            Text(typeLabel)
                .font(.caption2.weight(.bold))
                .textCase(.uppercase)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
        )
    }

    @ViewBuilder
    private var priceOverlay: some View {
        if let priceCents {
            let prefix = priceConfidence == "estimated" ? "~" : ""
            Text(prefix + Self.formattedPrice(cents: priceCents, currency: currency))
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(.ultraThinMaterial)
                        .environment(\.colorScheme, .dark)
                )
        }
    }

    private var saveOverlay: some View {
        Button(action: onSave) {
            Image(uiImage: isSaved ? Lucide.bookmarkCheck : Lucide.bookmark)
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 14, height: 14)
                .foregroundStyle(isSaved ? Theme.accent : .white)
                .padding(8)
                .background(
                    Circle()
                        .fill(.ultraThinMaterial)
                        .environment(\.colorScheme, .dark)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isSaved ? "Saved" : "Save")
    }

    // MARK: - Details Section

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Title
            Text(title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            // Why line: personalization note (preferred) or short description fallback
            whyLine

            // Matching factors — capped, single row, with overflow indicator
            if !orderedChips.isEmpty {
                matchingFactorsSection
            }

            // Full-width Select / Read button
            let isIdea = recommendationType == "idea" || recommendationType == "plan"
            KnotButton(
                isIdea ? "Read" : "Select",
                variant: .primary,
                size: .md,
                shape: .pill,
                trailingIcon: isIdea ? Lucide.book : Lucide.arrowRight,
                action: onSelect
            )
            .padding(.top, 4)
        }
        .padding(16)
    }

    @ViewBuilder
    private var whyLine: some View {
        if let personalizationNote, !personalizationNote.isEmpty {
            HStack(alignment: .top, spacing: 6) {
                Image(uiImage: Lucide.sparkles)
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 12, height: 12)
                    .foregroundStyle(Theme.accent)
                    .padding(.top, 2)

                Text(personalizationNote)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Theme.accent.opacity(0.9))
                    .italic()
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        } else if let descriptionText, !descriptionText.isEmpty {
            Text(descriptionText)
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Helpers

    private var typeIconLucide: UIImage {
        switch recommendationType {
        case "gift": return Lucide.gift
        case "experience": return Lucide.sparkles
        case "date": return Lucide.heart
        case "idea": return Lucide.lightbulb
        case "plan": return Lucide.calendarHeart
        default: return Lucide.star
        }
    }

    private var typeIconSystemName: String {
        switch recommendationType {
        case "gift": return "gift.fill"
        case "experience": return "sparkles"
        case "date": return "heart.fill"
        case "idea": return "lightbulb.fill"
        case "plan": return "calendar.badge.clock"
        default: return "star.fill"
        }
    }

    private var typeLabel: String {
        switch recommendationType {
        case "gift": return "Gift"
        case "experience": return "Experience"
        case "date": return "Date"
        case "idea": return "Idea"
        case "plan": return "Date Plan"
        default: return recommendationType.capitalized
        }
    }

    // MARK: - Matching Factors

    /// All matched factors in priority order: vibes → love languages → interests.
    /// Vibes and love languages reflect personality more directly than interest tags,
    /// so they're surfaced first when the chip row is capped.
    private var orderedChips: [DisplayChip] {
        var chips: [DisplayChip] = []
        chips.append(contentsOf: matchedVibes.map {
            DisplayChip(label: OnboardingVibesView.displayName(for: $0), style: .vibe)
        })
        chips.append(contentsOf: matchedLoveLanguages.map {
            DisplayChip(label: OnboardingLoveLanguagesView.displayName(for: $0), style: .loveLanguage)
        })
        chips.append(contentsOf: matchedInterests.map {
            DisplayChip(label: $0, style: .interest)
        })
        return chips
    }

    private var matchingFactorsSection: some View {
        let visible = Array(orderedChips.prefix(maxVisibleChips))
        let overflow = max(0, orderedChips.count - maxVisibleChips)

        return HStack(spacing: 6) {
            ForEach(visible) { chip in
                MatchingFactorChip(label: chip.label, style: chip.style)
            }
            if overflow > 0 {
                MatchingFactorChip(label: "+\(overflow)", style: .overflow)
            }
            Spacer(minLength: 0)
        }
    }

    /// Formats price from cents to a currency string (e.g., 4999 → "$49.99").
    static func formattedPrice(cents: Int, currency: String) -> String {
        let amount = Double(cents) / 100.0
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        formatter.maximumFractionDigits = (cents % 100 == 0) ? 0 : 2
        return formatter.string(from: NSNumber(value: amount)) ?? "$\(amount)"
    }
}

// MARK: - Display Chip Model

private struct DisplayChip: Identifiable {
    let id = UUID()
    let label: String
    let style: MatchingFactorChip.ChipStyle
}

// MARK: - Matching Factor Chip

private struct MatchingFactorChip: View {
    let label: String
    let style: ChipStyle

    enum ChipStyle {
        case interest
        case vibe
        case loveLanguage
        case overflow
    }

    var body: some View {
        HStack(spacing: 3) {
            if let icon = iconName {
                Image(systemName: icon)
                    .font(.system(size: 8, weight: .bold))
            }
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .lineLimit(1)
        }
        .foregroundStyle(foregroundColor)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(backgroundColor)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(borderColor, lineWidth: 0.5)
        )
    }

    private var iconName: String? {
        switch style {
        case .interest: return "heart.fill"
        case .vibe: return "sparkles"
        case .loveLanguage: return "hand.raised.fill"
        case .overflow: return nil
        }
    }

    private var foregroundColor: Color {
        switch style {
        case .interest: return Theme.accent
        case .vibe: return Color.purple
        case .loveLanguage: return Color.orange
        case .overflow: return Theme.textTertiary
        }
    }

    private var backgroundColor: Color {
        switch style {
        case .interest: return Theme.accent.opacity(0.18)
        case .vibe: return Color.purple.opacity(0.18)
        case .loveLanguage: return Color.orange.opacity(0.18)
        case .overflow: return Theme.surfaceElevated
        }
    }

    private var borderColor: Color {
        switch style {
        case .interest: return Theme.accent.opacity(0.3)
        case .vibe: return Color.purple.opacity(0.3)
        case .loveLanguage: return Color.orange.opacity(0.3)
        case .overflow: return Theme.surfaceBorder
        }
    }
}

// MARK: - Preview

#Preview("Gift Card") {
    VStack {
        RecommendationCard(
            title: "Ceramic Pottery Class for Two",
            descriptionText: "A hands-on pottery experience.",
            recommendationType: "gift",
            priceCents: 8500,
            currency: "USD",
            priceConfidence: "verified",
            imageURL: nil,
            isSaved: false,
            matchedInterests: ["Art", "Cooking"],
            matchedVibes: ["bohemian"],
            matchedLoveLanguages: ["quality_time"],
            personalizationNote: "Perfect — combines her love of art with quality time.",
            onSelect: {},
            onSave: {}
        )
        .padding(20)
    }
    .background(Theme.backgroundGradient.ignoresSafeArea())
}

#Preview("Experience Card — Saved") {
    VStack {
        RecommendationCard(
            title: "Private Sunset Sailing on the Bay",
            descriptionText: "2-hour private sailing trip with champagne.",
            recommendationType: "experience",
            priceCents: 24900,
            currency: "USD",
            priceConfidence: "verified",
            imageURL: "https://images.unsplash.com/photo-1500514966906-fe245eea9344?w=600",
            isSaved: true,
            matchedInterests: ["Travel"],
            matchedVibes: ["romantic", "quiet_luxury"],
            matchedLoveLanguages: ["quality_time"],
            personalizationNote: "Matches her romantic vibe and love of outdoor moments.",
            onSelect: {},
            onSave: {}
        )
        .padding(20)
    }
    .background(Theme.backgroundGradient.ignoresSafeArea())
}

#Preview("Date Card — No Price, Description Fallback") {
    VStack {
        RecommendationCard(
            title: "Rooftop Dinner at Skyline",
            descriptionText: "An intimate rooftop dining experience with panoramic city views and a seasonal tasting menu.",
            recommendationType: "date",
            priceCents: nil,
            currency: "USD",
            priceConfidence: "unknown",
            imageURL: nil,
            isSaved: false,
            matchedInterests: ["Food"],
            matchedVibes: ["romantic"],
            matchedLoveLanguages: [],
            personalizationNote: nil,
            onSelect: {},
            onSave: {}
        )
        .padding(20)
    }
    .background(Theme.backgroundGradient.ignoresSafeArea())
}

#Preview("Minimal Data Card — No Factors") {
    VStack {
        RecommendationCard(
            title: "Vintage Leather Journal",
            descriptionText: nil,
            recommendationType: "gift",
            priceCents: 3200,
            currency: "USD",
            priceConfidence: "estimated",
            imageURL: nil,
            isSaved: false,
            matchedInterests: [],
            matchedVibes: [],
            matchedLoveLanguages: [],
            personalizationNote: nil,
            onSelect: {},
            onSave: {}
        )
        .padding(20)
    }
    .background(Theme.backgroundGradient.ignoresSafeArea())
}

#Preview("Many Chips — Overflow") {
    VStack {
        RecommendationCard(
            title: "Cooking Class & Wine Pairing",
            descriptionText: nil,
            recommendationType: "experience",
            priceCents: 12500,
            currency: "USD",
            priceConfidence: "verified",
            imageURL: nil,
            isSaved: false,
            matchedInterests: ["Food", "Wine", "Cooking"],
            matchedVibes: ["romantic", "playful"],
            matchedLoveLanguages: ["quality_time", "acts_of_service"],
            personalizationNote: "She's mentioned wanting to learn together.",
            onSelect: {},
            onSave: {}
        )
        .padding(20)
    }
    .background(Theme.backgroundGradient.ignoresSafeArea())
}
