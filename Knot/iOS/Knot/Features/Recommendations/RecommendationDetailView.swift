//
//  RecommendationDetailView.swift
//  Knot
//
//  Created on June 12, 2026.
//  Spotlight redesign: a single, immersive detail page for EVERY recommendation
//  type (gift / experience / date / idea / plan). Replaces the thin
//  `SelectionConfirmationSheet` for purchasables and is a strict superset of
//  `IdeaDetailView` for Knot Originals.
//

import SwiftUI
import LucideIcons

/// Airbnb-style full-screen detail page for a single recommendation.
///
/// Layout (top → bottom):
/// - Collapsing hero image with overlaid back / share / save buttons
/// - Title + meta (price · merchant · location)
/// - "Why Knot picked this for {partner}" — the personalization note elevated into
///   the emotional centerpiece, with the matched vibes / love languages / interests
///   as proof badges
/// - "About" description
/// - Location row (experiences / dates)
/// - Structured idea content (Knot Originals), via the shared `IdeaContentSectionsView`
/// - A sticky bottom bar: price on the left, primary CTA on the right
///   ("Open in {Merchant}" for purchasables, "Save to Library" for ideas)
struct RecommendationDetailView: View {
    let item: RecommendationItemResponse
    /// Partner's first name, used to personalize the "Why Knot picked this" header.
    /// Falls back to "your partner" when unavailable.
    var partnerName: String?
    let isSaved: Bool

    /// Opens the merchant URL (purchasable types). No-op for ideas.
    let onOpenMerchant: @MainActor () -> Void
    /// Saves the recommendation to the library.
    let onSave: @MainActor () -> Void
    /// Presents the system share sheet.
    let onShare: @MainActor () -> Void
    /// Dismisses the detail page.
    let onDismiss: @MainActor () -> Void

    /// Optimistic local save state so the heart + CTA flip immediately on tap
    /// without coupling this view to the recommendations view model. Synced from
    /// `isSaved` on appear; unsave is not supported, so a one-way flip is correct.
    @State private var savedLocally = false

    private let heroHeight: CGFloat = 320

    private var isIdea: Bool {
        item.isIdea == true || item.recommendationType == "plan"
    }

    /// Saves once (optimistically flips local state) — no-op if already saved.
    private func saveOnce() {
        guard !savedLocally else { return }
        savedLocally = true
        onSave()
    }

    var body: some View {
        ZStack(alignment: .top) {
            Theme.backgroundGradient.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    heroSection
                    VStack(alignment: .leading, spacing: 22) {
                        titleBlock
                        whyBlock
                        aboutBlock
                        locationRow
                        if isIdea, let sections = item.contentSections, !sections.isEmpty {
                            IdeaContentSectionsView(sections: sections)
                        }
                    }
                    .padding(20)
                    // Clearance so the last content clears the sticky bottom bar.
                    .padding(.bottom, 120)
                }
            }
            .scrollIndicators(.hidden)
            .ignoresSafeArea(edges: .top)

            topBar
        }
        .safeAreaInset(edge: .bottom) {
            stickyBottomBar
        }
        .onAppear { savedLocally = isSaved }
    }

    // MARK: - Hero

    private var heroSection: some View {
        ZStack {
            if let imageURL = item.imageUrl, let url = URL(string: imageURL) {
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
                            ProgressView().tint(.white.opacity(0.5))
                        }
                    @unknown default:
                        fallbackGradient
                    }
                }
            } else {
                fallbackGradient
            }

            // Bottom scrim so the type badge + scroll transition read cleanly.
            VStack {
                LinearGradient(
                    colors: [.black.opacity(0.35), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 120)
                Spacer()
                LinearGradient(
                    colors: [.clear, .black.opacity(0.45)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 90)
            }

            // Type badge anchored bottom-leading over the hero.
            VStack {
                Spacer()
                HStack {
                    typeBadge
                    Spacer()
                }
                .padding(16)
            }
        }
        .frame(height: heroHeight)
        .clipped()
    }

    private var fallbackGradient: some View {
        ZStack {
            LinearGradient(
                colors: fallbackGradientColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: typeIconSystemName)
                .font(.system(size: 64, weight: .light))
                .foregroundStyle(.white.opacity(0.15))
        }
        .frame(height: heroHeight)
    }

    private var fallbackGradientColors: [Color] {
        switch item.recommendationType {
        case "gift": return [Color.pink.opacity(0.4), Color.purple.opacity(0.3)]
        case "experience": return [Color.blue.opacity(0.4), Color.indigo.opacity(0.3)]
        case "date": return [Color.orange.opacity(0.3), Color.pink.opacity(0.4)]
        case "idea", "plan": return [Color.yellow.opacity(0.3), Color.orange.opacity(0.3)]
        default: return [Color.purple.opacity(0.3), Color.pink.opacity(0.3)]
        }
    }

    private var typeBadge: some View {
        HStack(spacing: 5) {
            Image(uiImage: typeIconLucide)
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 12, height: 12)
            Text(typeLabel)
                .knotFont(Theme.Typography.label)
                .textCase(.uppercase)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
        )
    }

    // MARK: - Top Bar (overlaid circular buttons)

    private var topBar: some View {
        HStack {
            circleButton(icon: Lucide.arrowLeft, label: "Back") { onDismiss() }
            Spacer()
            HStack(spacing: 10) {
                circleButton(icon: Lucide.share, label: "Share") { onShare() }
                circleButton(
                    icon: Lucide.heart,
                    label: savedLocally ? "Saved" : "Save",
                    tint: savedLocally ? Theme.accent : .white
                ) { saveOnce() }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private func circleButton(
        icon: UIImage,
        label: String,
        tint: Color = .white,
        action: @escaping @MainActor () -> Void
    ) -> some View {
        Button(action: action) {
            Image(uiImage: icon)
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 18, height: 18)
                .foregroundStyle(tint)
                .padding(11)
                .background(
                    Circle()
                        .fill(.ultraThinMaterial)
                        .environment(\.colorScheme, .dark)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    // MARK: - Title Block

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(item.title)
                .knotFont(Theme.Typography.sectionHeaderSemibold)
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            if !metaParts.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(metaParts.enumerated()), id: \.offset) { _, part in
                        HStack(spacing: 5) {
                            Image(uiImage: part.icon)
                                .renderingMode(.template)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 13, height: 13)
                            Text(part.text)
                                .knotFont(Theme.Typography.bodySmall)
                                .lineLimit(1)
                        }
                        .foregroundStyle(Theme.textSecondary)
                    }
                }
            }
        }
    }

    private struct MetaPart {
        let icon: UIImage
        let text: String
    }

    private var metaParts: [MetaPart] {
        var parts: [MetaPart] = []
        if !isIdea, let merchant = item.merchantName, !merchant.isEmpty {
            parts.append(MetaPart(icon: Lucide.store, text: merchant))
        }
        if !isIdea, let priceCents = item.priceCents {
            let prefix = item.priceConfidence == "estimated" ? "~" : ""
            parts.append(MetaPart(
                icon: Lucide.dollarSign,
                text: prefix + RecommendationCard.formattedPrice(cents: priceCents, currency: item.currency)
            ))
        }
        if let locationText {
            parts.append(MetaPart(icon: Lucide.mapPin, text: locationText))
        }
        return parts
    }

    // MARK: - Why Knot Picked This

    @ViewBuilder
    private var whyBlock: some View {
        let chips = RecommendationDisplayChip.build(
            vibes: item.matchedVibes ?? [],
            loveLanguages: item.matchedLoveLanguages ?? [],
            interests: item.matchedInterests ?? []
        )
        let note = item.personalizationNote?.trimmingCharacters(in: .whitespacesAndNewlines)

        if (note?.isEmpty == false) || !chips.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Image(uiImage: Lucide.sparkles)
                        .renderingMode(.template)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 16, height: 16)
                        .foregroundStyle(Theme.accent)
                    Text("Why Knot picked this for \(partnerDisplayName)")
                        .knotFont(Theme.Typography.cta)
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let note, !note.isEmpty {
                    Text("\"\(note)\"")
                        .knotFont(Theme.Typography.bodySmall)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !chips.isEmpty {
                    FlowLayout(horizontalSpacing: 6, verticalSpacing: 6) {
                        ForEach(chips) { chip in
                            MatchingFactorChip(label: chip.label, style: chip.style)
                        }
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.lg)
                    .fill(Theme.accent.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.lg)
                            .stroke(Theme.accent.opacity(0.15), lineWidth: 1)
                    )
            )
        }
    }

    private var partnerDisplayName: String {
        if let name = partnerName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return name
        }
        return "your partner"
    }

    // MARK: - About

    @ViewBuilder
    private var aboutBlock: some View {
        // For ideas, the description already leads the structured content, so we
        // skip a duplicate "About" block.
        if !isIdea, let description = item.description, !description.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("About")
                    .knotFont(Theme.Typography.cardTitle)
                    .foregroundStyle(Theme.textPrimary)
                Text(description)
                    .knotFont(Theme.Typography.body)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else if isIdea, let description = item.description, !description.isEmpty {
            Text(description)
                .knotFont(Theme.Typography.body)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Location

    @ViewBuilder
    private var locationRow: some View {
        if let location = item.location {
            let parts = [location.address, location.city, location.state]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
            if !parts.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Where")
                        .knotFont(Theme.Typography.cardTitle)
                        .foregroundStyle(Theme.textPrimary)
                    HStack(spacing: 8) {
                        Image(uiImage: Lucide.mapPin)
                            .renderingMode(.template)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 16, height: 16)
                            .foregroundStyle(Theme.accent)
                        Text(parts.joined(separator: ", "))
                            .knotFont(Theme.Typography.body)
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    // MARK: - Sticky Bottom Bar

    private var stickyBottomBar: some View {
        HStack(spacing: 16) {
            // Price (purchasables only)
            if !isIdea, let priceCents = item.priceCents {
                let prefix = item.priceConfidence == "estimated" ? "~" : ""
                VStack(alignment: .leading, spacing: 2) {
                    Text(prefix + RecommendationCard.formattedPrice(cents: priceCents, currency: item.currency))
                        .knotFont(Theme.Typography.numeric)
                        .foregroundStyle(Theme.textPrimary)
                    Text("You stay the hero")
                        .knotFont(Theme.Typography.label)
                        .foregroundStyle(Theme.textTertiary)
                }
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Knot Original")
                        .knotFont(Theme.Typography.cta)
                        .foregroundStyle(Theme.textPrimary)
                    Text("Yours to make happen")
                        .knotFont(Theme.Typography.label)
                        .foregroundStyle(Theme.textTertiary)
                }
            }

            Spacer(minLength: 0)

            primaryCTA
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .background(
            Theme.backgroundBottom
                .opacity(0.96)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(Theme.surfaceBorder)
                        .frame(height: 1)
                }
                .ignoresSafeArea(edges: .bottom)
        )
    }

    @ViewBuilder
    private var primaryCTA: some View {
        if isIdea {
            KnotButton(
                savedLocally ? "Saved" : "Save to Library",
                variant: savedLocally ? .secondary : .primary,
                size: .lg,
                shape: .pill,
                leadingIcon: savedLocally ? Lucide.bookmarkCheck : Lucide.bookmark,
                action: saveOnce
            )
            .frame(maxWidth: 220)
        } else {
            KnotButton(
                openLabel,
                variant: .primary,
                size: .lg,
                shape: .pill,
                trailingIcon: Lucide.externalLink,
                action: onOpenMerchant
            )
            .frame(maxWidth: 220)
        }
    }

    private var openLabel: String {
        if let merchant = item.merchantName, !merchant.isEmpty {
            return "Open in \(merchant)"
        }
        return "Open Link"
    }

    // MARK: - Helpers

    private var locationText: String? {
        guard let location = item.location else { return nil }
        let cityState = [location.city, location.state]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
        guard !cityState.isEmpty else { return nil }
        return cityState.joined(separator: ", ")
    }

    private var typeIconLucide: UIImage {
        switch item.recommendationType {
        case "gift": return Lucide.gift
        case "experience": return Lucide.sparkles
        case "date": return Lucide.heart
        case "idea": return Lucide.lightbulb
        case "plan": return Lucide.calendarHeart
        default: return Lucide.star
        }
    }

    private var typeIconSystemName: String {
        switch item.recommendationType {
        case "gift": return "gift.fill"
        case "experience": return "sparkles"
        case "date": return "heart.fill"
        case "idea": return "lightbulb.fill"
        case "plan": return "calendar.badge.clock"
        default: return "star.fill"
        }
    }

    private var typeLabel: String {
        switch item.recommendationType {
        case "gift": return "Gift"
        case "experience": return "Experience"
        case "date": return "Date"
        case "idea": return "Idea"
        case "plan": return "Date Plan"
        default: return item.recommendationType.capitalized
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Detail — Gift") {
    RecommendationDetailView(
        item: PreviewRecommendations.gift,
        partnerName: "Alex",
        isSaved: false,
        onOpenMerchant: {},
        onSave: {},
        onShare: {},
        onDismiss: {}
    )
}

#Preview("Detail — Idea") {
    RecommendationDetailView(
        item: PreviewRecommendations.idea,
        partnerName: "Alex",
        isSaved: false,
        onOpenMerchant: {},
        onSave: {},
        onShare: {},
        onDismiss: {}
    )
}

/// Shared sample recommendations for SwiftUI previews of the Spotlight views.
enum PreviewRecommendations {
    static let gift = decode(type: "gift", isIdea: false)
    static let experience = decode(type: "experience", isIdea: false)
    static let idea = decode(type: "idea", isIdea: true)

    static func decode(type: String, isIdea: Bool) -> RecommendationItemResponse {
        let sections = isIdea
            ? """
              , "content_sections": [
                {"type": "overview", "heading": "The Idea", "body": "A cozy night in built around what they love.", "items": null},
                {"type": "steps", "heading": "How to pull it off", "body": null, "items": ["Cook their favorite meal", "Queue up a film", "End with a slow dance"]},
                {"type": "tips", "heading": "Pro Tips", "body": "Small touches matter.", "items": ["Dim the lights"]}
              ]
              """
            : ""
        let json = """
        {
            "id": "\(type)-preview", "recommendation_type": "\(type)", "title": "\(type.capitalized) for Alex",
            "description": "A thoughtful \(type) chosen around her love of art and quiet luxury evenings.",
            "price_cents": \(isIdea ? "null" : "8500"), "currency": "USD",
            "external_url": \(isIdea ? "null" : "\"https://example.com/x\""),
            "image_url": null, "merchant_name": \(isIdea ? "null" : "\"Clay Studio Brooklyn\""), "source": "test",
            "location": {"city": "Brooklyn", "state": "NY", "country": "US", "address": "1 Main St"},
            "is_idea": \(isIdea ? "true" : "false")\(sections),
            "interest_score": 0.8, "vibe_score": 0.7, "love_language_score": 0.6, "final_score": 0.7,
            "matched_interests": ["Art", "Cooking"], "matched_vibes": ["romantic", "quiet_luxury"],
            "matched_love_languages": ["quality_time"],
            "personalization_note": "She mentioned wanting to try pottery after that gallery visit."
        }
        """.data(using: .utf8)!
        return try! JSONDecoder().decode(RecommendationItemResponse.self, from: json)
    }
}
#endif
