//
//  RecommendationCard.swift
//  Knot
//
//  Created on February 10, 2026.
//

import SwiftUI
import LucideIcons

/// Restaurant-list-style recommendation card for vertical scrolling.
///
/// Designed for a vertically-scrolled feed (Rappi/DoorDash pattern). Each card
/// has visual presence via a tall hero image, restaurant-style meta line under
/// the title, all matched factors as chips, and a full-width Select button.
///
/// Layout (top to bottom):
/// ```
/// ┌─────────────────────────────────────┐
/// │ [Hero — 220pt]                      │
/// │  ┌Gift┐                       ┌🔖┐ │
/// │  └────┘                       └──┘ │
/// │  ┌─ ✨ Why Knot picked... ──┐      │
/// │  └─────────────────────────────┘   │
/// ├─────────────────────────────────────┤
/// │ Title (large bold, 2 lines)         │
/// │ 🏪 Merchant · 💰 $49 · 📍 City      │
/// │ ❤ Art  ✨ Romantic  💕 Quality Time │
/// │ ┌────────── Select ──────────┐      │
/// │ └─────────────────────────────┘     │
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
    let merchantName: String?
    let locationCity: String?
    let locationState: String?
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
    private let heroHeight: CGFloat = 220

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
        ZStack {
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

            // Top edge gradient for top-overlay readability
            VStack {
                LinearGradient(
                    colors: [.black.opacity(0.35), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 70)
                Spacer()
            }

            // Bottom edge gradient for personalization-overlay readability
            if hasPersonalization {
                VStack {
                    Spacer()
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.55)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 100)
                }
            }

            // Top row: type badge (left) + save (right)
            VStack {
                HStack(alignment: .top) {
                    typeBadge
                    Spacer()
                    saveOverlay
                }
                .padding(12)
                Spacer()
            }

            // Bottom personalization snippet — Rappi's "ordered recently" pattern
            // applied to Knot's "why we picked this" signal.
            if let personalizationNote, !personalizationNote.isEmpty {
                VStack {
                    Spacer()
                    HStack {
                        personalizationOverlay(note: personalizationNote)
                        Spacer(minLength: 0)
                    }
                    .padding(12)
                }
            }
        }
        .frame(height: heroHeight)
        .clipped()
    }

    private var hasPersonalization: Bool {
        if let note = personalizationNote, !note.isEmpty { return true }
        return false
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
                .font(.system(size: 48, weight: .light))
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

    private func personalizationOverlay(note: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(uiImage: Lucide.sparkles)
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 11, height: 11)
                .foregroundStyle(.white)
                .padding(.top, 2)

            Text(note)
                .font(.caption.weight(.medium))
                .foregroundStyle(.white)
                .italic()
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
        )
        .frame(maxWidth: 280, alignment: .leading)
    }

    // MARK: - Details Section

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Title — larger and bolder than v1 since vertical scroll gives us room
            Text(title)
                .font(.title3.weight(.bold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            // Restaurant-style meta line: merchant · price · location
            metaLine

            // All matched factors (no cap) — vertical scroll affords more space
            if !orderedChips.isEmpty {
                matchingFactorsSection
            }

            // Description (optional, used when personalization isn't shown
            // on the hero — i.e. when personalizationNote is nil/empty)
            if !hasPersonalization, let descriptionText, !descriptionText.isEmpty {
                Text(descriptionText)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
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
    private var metaLine: some View {
        let parts = metaParts
        if !parts.isEmpty {
            HStack(spacing: 6) {
                ForEach(Array(parts.enumerated()), id: \.offset) { index, part in
                    if index > 0 {
                        Circle()
                            .fill(Theme.textTertiary)
                            .frame(width: 3, height: 3)
                    }
                    HStack(spacing: 4) {
                        Image(uiImage: part.icon)
                            .renderingMode(.template)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 11, height: 11)
                        Text(part.text)
                            .font(.caption.weight(.medium))
                            .lineLimit(1)
                    }
                    .foregroundStyle(Theme.textSecondary)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var metaParts: [MetaPart] {
        var parts: [MetaPart] = []
        if let merchantName, !merchantName.isEmpty {
            parts.append(MetaPart(icon: Lucide.store, text: merchantName))
        }
        if let priceCents {
            let prefix = priceConfidence == "estimated" ? "~" : ""
            parts.append(MetaPart(
                icon: Lucide.dollarSign,
                text: prefix + Self.formattedPrice(cents: priceCents, currency: currency)
            ))
        }
        if let locationText {
            parts.append(MetaPart(icon: Lucide.mapPin, text: locationText))
        }
        return parts
    }

    private var locationText: String? {
        let cityState = [locationCity, locationState]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
        guard !cityState.isEmpty else { return nil }
        return cityState.joined(separator: ", ")
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

    /// Vibes → love languages → interests; vertical scroll lets us show all of them.
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
        FlowLayout(horizontalSpacing: 6, verticalSpacing: 6) {
            ForEach(orderedChips) { chip in
                MatchingFactorChip(label: chip.label, style: chip.style)
            }
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

// MARK: - Meta Part

private struct MetaPart {
    let icon: UIImage
    let text: String
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
    }

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: iconName)
                .font(.system(size: 8, weight: .bold))
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

    private var iconName: String {
        switch style {
        case .interest: return "heart.fill"
        case .vibe: return "sparkles"
        case .loveLanguage: return "hand.raised.fill"
        }
    }

    private var foregroundColor: Color {
        switch style {
        case .interest: return Theme.accent
        case .vibe: return Color.purple
        case .loveLanguage: return Color.orange
        }
    }

    private var backgroundColor: Color {
        switch style {
        case .interest: return Theme.accent.opacity(0.18)
        case .vibe: return Color.purple.opacity(0.18)
        case .loveLanguage: return Color.orange.opacity(0.18)
        }
    }

    private var borderColor: Color {
        switch style {
        case .interest: return Theme.accent.opacity(0.3)
        case .vibe: return Color.purple.opacity(0.3)
        case .loveLanguage: return Color.orange.opacity(0.3)
        }
    }
}

// MARK: - Preview

#Preview("Vertical Feed") {
    ScrollView {
        VStack(spacing: 16) {
            RecommendationCard(
                title: "Ceramic Pottery Class for Two",
                descriptionText: "A hands-on pottery experience.",
                recommendationType: "gift",
                priceCents: 8500,
                currency: "USD",
                priceConfidence: "verified",
                merchantName: "Clay Studio Brooklyn",
                locationCity: "Brooklyn",
                locationState: "NY",
                imageURL: nil,
                isSaved: false,
                matchedInterests: ["Art", "Cooking"],
                matchedVibes: ["bohemian"],
                matchedLoveLanguages: ["quality_time"],
                personalizationNote: "Combines her love of art with quality time.",
                onSelect: {},
                onSave: {}
            )
            RecommendationCard(
                title: "Private Sunset Sailing on the Bay",
                descriptionText: nil,
                recommendationType: "experience",
                priceCents: 24900,
                currency: "USD",
                priceConfidence: "verified",
                merchantName: "Bay Sailing Co.",
                locationCity: "San Francisco",
                locationState: "CA",
                imageURL: "https://images.unsplash.com/photo-1500514966906-fe245eea9344?w=600",
                isSaved: true,
                matchedInterests: ["Travel"],
                matchedVibes: ["romantic", "quiet_luxury"],
                matchedLoveLanguages: ["quality_time"],
                personalizationNote: "Matches her romantic vibe and love of outdoor moments.",
                onSelect: {},
                onSave: {}
            )
            RecommendationCard(
                title: "Rooftop Dinner at Skyline",
                descriptionText: "An intimate rooftop dining experience with panoramic city views.",
                recommendationType: "date",
                priceCents: nil,
                currency: "USD",
                priceConfidence: "unknown",
                merchantName: "Skyline Restaurant",
                locationCity: nil,
                locationState: nil,
                imageURL: nil,
                isSaved: false,
                matchedInterests: ["Food"],
                matchedVibes: ["romantic"],
                matchedLoveLanguages: [],
                personalizationNote: nil,
                onSelect: {},
                onSave: {}
            )
        }
        .padding(20)
    }
    .background(Theme.backgroundGradient.ignoresSafeArea())
}
