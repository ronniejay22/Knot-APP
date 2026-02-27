//
//  RecommendationCard.swift
//  Knot
//
//  Created on February 10, 2026.
//  Step 6.1: Recommendation card component for the Choice-of-Three UI.
//  Step 6.6: Added Save and Share action buttons below the Select row.
//

import SwiftUI
import LucideIcons

/// A single recommendation card displaying a hero image, title, short description,
/// price badge, merchant name, and a "Select" action button.
///
/// Designed for horizontal paging in the Choice-of-Three scroll view (Step 6.2).
/// Uses the app's dark-purple aesthetic with frosted-glass surfaces and pink accents.
///
/// Layout (top to bottom):
/// ```
/// ┌───────────────────────────────────┐
/// │  [Hero Image / Gradient Fallback] │
/// │  ┌─ Type Badge ─┐                │
/// │  │ 🎁 Gift      │                │
/// │  └──────────────┘                │
/// ├───────────────────────────────────┤
/// │  Title (2 lines max)              │
/// │  📍 Merchant Name                 │
/// │  Description (3 lines max)        │
/// │                                   │
/// │  ┌─ Price ─┐         ┌─ Select ─┐│
/// │  │  $49.99 │         │  Select  ││
/// │  └─────────┘         └──────────┘│
/// │                                   │
/// │  ┌─ Save ─┐   ┌─ Share ─┐       │
/// │  │ 🔖 Save│   │ 📤 Share│       │
/// │  └────────┘   └─────────┘       │
/// └───────────────────────────────────┘
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
    let imageURL: String?
    let isSaved: Bool
    let matchedInterests: [String]
    let matchedVibes: [String]
    let matchedLoveLanguages: [String]
    let onSelect: @MainActor @Sendable () -> Void
    let onSave: @MainActor @Sendable () -> Void
    let onShare: @MainActor @Sendable () -> Void

    // MARK: - Constants

    private let cardCornerRadius: CGFloat = 18
    private let heroHeight: CGFloat = 200

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            heroSection
            detailsSection
        }
        .background(
            RoundedRectangle(cornerRadius: cardCornerRadius)
                .fill(Theme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: cardCornerRadius)
                .stroke(Theme.surfaceBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: cardCornerRadius))
    }

    // MARK: - Hero Image Section

    private var heroSection: some View {
        ZStack(alignment: .topLeading) {
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

            // Bottom gradient overlay for badge readability
            VStack {
                Spacer()
                LinearGradient(
                    colors: [.clear, .black.opacity(0.4)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 60)
            }

            // Type badge — top-left
            typeBadge
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

    /// Returns gradient colors based on recommendation type.
    private var fallbackGradientColors: [Color] {
        switch recommendationType {
        case "gift":
            return [Color.pink.opacity(0.4), Color.purple.opacity(0.3)]
        case "experience":
            return [Color.blue.opacity(0.4), Color.indigo.opacity(0.3)]
        case "date":
            return [Color.orange.opacity(0.3), Color.pink.opacity(0.4)]
        default:
            return [Color.purple.opacity(0.3), Color.pink.opacity(0.3)]
        }
    }

    // MARK: - Type Badge

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

    // MARK: - Details Section

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Title
            Text(title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            // Merchant name
            if let merchantName, !merchantName.isEmpty {
                HStack(spacing: 5) {
                    Image(uiImage: Lucide.store)
                        .renderingMode(.template)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 12, height: 12)
                        .foregroundStyle(Theme.textTertiary)

                    Text(merchantName)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
            }

            // Description
            if let descriptionText, !descriptionText.isEmpty {
                Text(descriptionText)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Matching factor chips
            if !matchedInterests.isEmpty || !matchedVibes.isEmpty || !matchedLoveLanguages.isEmpty {
                matchingFactorsSection
            }

            Spacer(minLength: 4)

            // Bottom row: price + select button
            HStack {
                // Price badge
                if let priceCents {
                    let prefix = priceConfidence == "estimated" ? "~" : ""
                    Text(prefix + Self.formattedPrice(cents: priceCents, currency: currency))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(
                            Capsule()
                                .fill(Theme.surfaceElevated)
                                .overlay(
                                    Capsule()
                                        .stroke(Theme.surfaceBorder, lineWidth: 1)
                                )
                        )
                } else {
                    Text("Price varies")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Theme.textTertiary)
                }

                Spacer()

                // Select / Read button
                Button(action: onSelect) {
                    HStack(spacing: 6) {
                        Text(recommendationType == "idea" ? "Read" : "Select")
                            .font(.subheadline.weight(.semibold))

                        Image(systemName: recommendationType == "idea" ? "book" : "arrow.right")
                            .font(.caption.weight(.bold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(
                        Capsule()
                            .fill(Theme.accent)
                    )
                }
                .buttonStyle(.plain)
            }

            // Save / Share row (Step 6.6)
            HStack(spacing: 12) {
                // Save button
                Button(action: onSave) {
                    HStack(spacing: 6) {
                        Image(uiImage: isSaved ? Lucide.bookmarkCheck : Lucide.bookmark)
                            .renderingMode(.template)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 14, height: 14)

                        Text(isSaved ? "Saved" : "Save")
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(isSaved ? Theme.accent : Theme.textSecondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(isSaved ? Theme.accent.opacity(0.15) : Theme.surfaceElevated)
                            .overlay(
                                Capsule()
                                    .stroke(isSaved ? Theme.accent.opacity(0.4) : Theme.surfaceBorder, lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(.plain)

                // Share button
                Button(action: onShare) {
                    HStack(spacing: 6) {
                        Image(uiImage: Lucide.share2)
                            .renderingMode(.template)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 14, height: 14)

                        Text("Share")
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(Theme.surfaceElevated)
                            .overlay(
                                Capsule()
                                    .stroke(Theme.surfaceBorder, lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(.plain)

                Spacer()
            }
        }
        .padding(16)
    }

    // MARK: - Helpers

    /// Maps recommendation type to a Lucide icon.
    private var typeIconLucide: UIImage {
        switch recommendationType {
        case "gift": return Lucide.gift
        case "experience": return Lucide.sparkles
        case "date": return Lucide.heart
        default: return Lucide.star
        }
    }

    /// Maps recommendation type to an SF Symbol for the fallback gradient.
    private var typeIconSystemName: String {
        switch recommendationType {
        case "gift": return "gift.fill"
        case "experience": return "sparkles"
        case "date": return "heart.fill"
        default: return "star.fill"
        }
    }

    /// Human-readable label for the recommendation type.
    private var typeLabel: String {
        switch recommendationType {
        case "gift": return "Gift"
        case "experience": return "Experience"
        case "date": return "Date"
        default: return recommendationType.capitalized
        }
    }

    // MARK: - Matching Factors

    private var matchingFactorsSection: some View {
        FlowLayout(horizontalSpacing: 6, verticalSpacing: 6) {
            ForEach(matchedInterests, id: \.self) { interest in
                MatchingFactorChip(label: interest, style: .interest)
            }
            ForEach(matchedVibes, id: \.self) { vibe in
                MatchingFactorChip(
                    label: OnboardingVibesView.displayName(for: vibe),
                    style: .vibe
                )
            }
            ForEach(matchedLoveLanguages, id: \.self) { language in
                MatchingFactorChip(
                    label: OnboardingLoveLanguagesView.displayName(for: language),
                    style: .loveLanguage
                )
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

// MARK: - Matching Factor Chip

/// A compact chip displaying a matched factor (interest, vibe, or love language)
/// that contributed to the recommendation's score.
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
        case .interest: return .white
        case .vibe: return .white.opacity(0.9)
        case .loveLanguage: return .white.opacity(0.9)
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

#Preview("Gift Card") {
    ScrollView {
        RecommendationCard(
            title: "Ceramic Pottery Class for Two",
            descriptionText: "A hands-on pottery experience where you and your partner create custom pieces together. Includes all materials and firing.",
            recommendationType: "gift",
            priceCents: 8500,
            currency: "USD",
            priceConfidence: "verified",
            merchantName: "Clay Studio Brooklyn",
            imageURL: nil,
            isSaved: false,
            matchedInterests: ["Art", "Cooking"],
            matchedVibes: ["bohemian"],
            matchedLoveLanguages: ["quality_time"],
            onSelect: {},
            onSave: {},
            onShare: {}
        )
        .padding(20)
    }
    .background(Theme.backgroundGradient.ignoresSafeArea())
    .preferredColorScheme(.dark)
}

#Preview("Experience Card — Saved") {
    ScrollView {
        RecommendationCard(
            title: "Private Sunset Sailing Experience on the Bay",
            descriptionText: "Enjoy a 2-hour private sailing trip with champagne and charcuterie as the sun sets over the bay.",
            recommendationType: "experience",
            priceCents: 24900,
            currency: "USD",
            priceConfidence: "verified",
            merchantName: "Bay Sailing Co.",
            imageURL: "https://images.unsplash.com/photo-1500514966906-fe245eea9344?w=600",
            isSaved: true,
            matchedInterests: ["Travel"],
            matchedVibes: ["romantic", "quiet_luxury"],
            matchedLoveLanguages: ["quality_time"],
            onSelect: {},
            onSave: {},
            onShare: {}
        )
        .padding(20)
    }
    .background(Theme.backgroundGradient.ignoresSafeArea())
    .preferredColorScheme(.dark)
}

#Preview("Date Card - No Price") {
    ScrollView {
        RecommendationCard(
            title: "Rooftop Dinner at Skyline",
            descriptionText: "An intimate rooftop dining experience with panoramic city views and a seasonal tasting menu.",
            recommendationType: "date",
            priceCents: nil,
            currency: "USD",
            priceConfidence: "unknown",
            merchantName: "Skyline Restaurant",
            imageURL: nil,
            isSaved: false,
            matchedInterests: ["Food"],
            matchedVibes: ["romantic"],
            matchedLoveLanguages: [],
            onSelect: {},
            onSave: {},
            onShare: {}
        )
        .padding(20)
    }
    .background(Theme.backgroundGradient.ignoresSafeArea())
    .preferredColorScheme(.dark)
}

#Preview("Minimal Data Card — No Factors") {
    ScrollView {
        RecommendationCard(
            title: "Vintage Leather Journal",
            descriptionText: nil,
            recommendationType: "gift",
            priceCents: 3200,
            currency: "USD",
            priceConfidence: "estimated",
            merchantName: nil,
            imageURL: nil,
            isSaved: false,
            matchedInterests: [],
            matchedVibes: [],
            matchedLoveLanguages: [],
            onSelect: {},
            onSave: {},
            onShare: {}
        )
        .padding(20)
    }
    .background(Theme.backgroundGradient.ignoresSafeArea())
    .preferredColorScheme(.dark)
}
