//
//  RecommendationCard.swift
//  Knot
//
//  Created on February 10, 2026.
//  Step 6.1: Recommendation card component for the Choice-of-Three UI.
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
/// └───────────────────────────────────┘
/// ```
struct RecommendationCard: View {

    // MARK: - Properties

    let title: String
    let descriptionText: String?
    let recommendationType: String
    let priceCents: Int?
    let currency: String
    let merchantName: String?
    let imageURL: String?
    let onSelect: @MainActor @Sendable () -> Void

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

            Spacer(minLength: 4)

            // Bottom row: price + select button
            HStack {
                // Price badge
                if let priceCents {
                    Text(formattedPrice(cents: priceCents, currency: currency))
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

                // Select button
                Button(action: onSelect) {
                    HStack(spacing: 6) {
                        Text("Select")
                            .font(.subheadline.weight(.semibold))

                        Image(systemName: "arrow.right")
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

    /// Formats price from cents to a currency string (e.g., 4999 → "$49.99").
    func formattedPrice(cents: Int, currency: String) -> String {
        let amount = Double(cents) / 100.0
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        formatter.maximumFractionDigits = (cents % 100 == 0) ? 0 : 2
        return formatter.string(from: NSNumber(value: amount)) ?? "$\(amount)"
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
            merchantName: "Clay Studio Brooklyn",
            imageURL: nil,
            onSelect: {}
        )
        .padding(20)
    }
    .background(Theme.backgroundGradient.ignoresSafeArea())
    .preferredColorScheme(.dark)
}

#Preview("Experience Card with Image") {
    ScrollView {
        RecommendationCard(
            title: "Private Sunset Sailing Experience on the Bay",
            descriptionText: "Enjoy a 2-hour private sailing trip with champagne and charcuterie as the sun sets over the bay.",
            recommendationType: "experience",
            priceCents: 24900,
            currency: "USD",
            merchantName: "Bay Sailing Co.",
            imageURL: "https://images.unsplash.com/photo-1500514966906-fe245eea9344?w=600",
            onSelect: {}
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
            merchantName: "Skyline Restaurant",
            imageURL: nil,
            onSelect: {}
        )
        .padding(20)
    }
    .background(Theme.backgroundGradient.ignoresSafeArea())
    .preferredColorScheme(.dark)
}

#Preview("Minimal Data Card") {
    ScrollView {
        RecommendationCard(
            title: "Vintage Leather Journal",
            descriptionText: nil,
            recommendationType: "gift",
            priceCents: 3200,
            currency: "USD",
            merchantName: nil,
            imageURL: nil,
            onSelect: {}
        )
        .padding(20)
    }
    .background(Theme.backgroundGradient.ignoresSafeArea())
    .preferredColorScheme(.dark)
}
