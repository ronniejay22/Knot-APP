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
/// - Full-bleed hero image with a single overlaid back button
/// - A gray uppercase category pill (the matched vibes, or the type), the title,
///   and a one-line "{location} • {merchant}" meta row
/// - A white three-column stats strip built only from data the pipeline populates:
///   profile-match count · "Knot Pick" + the matched love language · type + merchant
///   (see `RecommendationDetailContent` — Knot has no ratings or bookings to show)
/// - "Why Knot picked this for {partner}" — a tinted card with a heart, the
///   personalization note, and the matched vibes / love languages / interests as chips
/// - "About" card
/// - "Where you'll meet" card (experiences / dates)
/// - Structured idea content (Knot Originals), via the shared `IdeaContentSectionsView`
/// - A sticky bottom bar: price on the left, primary CTA on the right
///   ("Open in {Merchant}" for purchasables, the Save → Saved → Continue CTA otherwise)
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
    /// Dismisses the detail page.
    let onDismiss: @MainActor () -> Void

    /// Optimistic local save state so the CTA flips immediately on tap without
    /// coupling this view to the recommendations view model. Synced from `isSaved`
    /// on appear; unsave is not supported, so a one-way flip is correct.
    @State private var savedLocally = false

    /// True once the brief "Saved" confirmation has run its course, at which point
    /// the CTA becomes "Continue". Seeded from `isSaved` on appear so an item opened
    /// already-saved (the Saved tab, or a card saved earlier this session) shows a
    /// forward action immediately rather than an inert "Saved" button.
    @State private var confirmationElapsed = false

    private let heroHeight: CGFloat = 320

    /// How long the "Saved" confirmation holds before the CTA becomes "Continue".
    private static let savedConfirmationDelay: Duration = .seconds(2)

    private var isIdea: Bool {
        RecommendationDetailContent.isIdea(type: item.recommendationType, isIdeaFlag: item.isIdea)
    }

    /// The three states of the save-flavored CTA. Pure so it can be unit-tested
    /// without hosting the view.
    enum SaveCTAState: Equatable {
        case save
        case saved
        case continueOn
    }

    /// Resolves the save CTA: unsaved → "Save to Library"; saved → a brief "Saved"
    /// confirmation; then "Continue", which moves the user on.
    static func saveCTAState(isSavedLocally: Bool, confirmationElapsed: Bool) -> SaveCTAState {
        guard isSavedLocally else { return .save }
        return confirmationElapsed ? .continueOn : .saved
    }

    private var saveCTAState: SaveCTAState {
        Self.saveCTAState(isSavedLocally: savedLocally, confirmationElapsed: confirmationElapsed)
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
                    VStack(alignment: .leading, spacing: 16) {
                        titleBlock
                        statsStrip
                        whyBlock
                        aboutBlock
                        locationCard
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
        .onAppear {
            savedLocally = isSaved
            confirmationElapsed = isSaved
        }
        // Hold the "Saved" confirmation briefly, then swap the CTA to "Continue".
        // `.task(id:)` cancels automatically when the page is dismissed.
        .task(id: savedLocally) {
            guard savedLocally, !confirmationElapsed else { return }
            try? await Task.sleep(for: Self.savedConfirmationDelay)
            guard !Task.isCancelled else { return }
            withAnimation(Theme.Motion.standard) { confirmationElapsed = true }
        }
    }

    // MARK: - Hero

    private var heroSection: some View {
        ZStack {
            // Local bundled photo is always present, with the remote hero overlaid
            // when it loads. A real photo shows in every state — never a gradient.
            fallbackImage
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
                    case .empty:
                        // Keep the local photo visible while the remote loads.
                        ProgressView().tint(.white.opacity(0.5))
                    default:
                        // .failure / @unknown — the local photo shows through.
                        Color.clear
                    }
                }
            }

            // Scrims so the back button and the hero-to-content transition read cleanly.
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
        }
        .frame(height: heroHeight)
        .clipped()
    }

    /// The bundled per-type photo, sized to the hero. Always shown beneath the
    /// remote image so the detail hero never falls back to a gradient.
    private var fallbackImage: some View {
        RecommendationFallbackImage(recommendationType: item.recommendationType)
            .frame(minWidth: 0, maxWidth: .infinity)
            .frame(height: heroHeight)
            .clipped()
    }

    // MARK: - Top Bar (overlaid circular back button)

    /// Only Back lives over the hero. The former Share and Save circle buttons were
    /// removed — saving is the bottom CTA's job, and Share was redundant chrome.
    private var topBar: some View {
        HStack {
            circleButton(icon: Lucide.arrowLeft, label: "Back") { onDismiss() }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private func circleButton(
        icon: UIImage,
        label: String,
        action: @escaping @MainActor () -> Void
    ) -> some View {
        Button(action: action) {
            Image(uiImage: icon)
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 18, height: 18)
                .foregroundStyle(.white)
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
            categoryPill

            Text(item.title)
                .knotFont(Theme.Typography.sectionHeaderSemibold)
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            if let meta = metaLine {
                Text(meta)
                    .knotFont(Theme.Typography.bodySmall)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
    }

    /// Gray uppercase eyebrow above the title — the matched vibes, or the type.
    /// A private capsule rather than `KnotBadge`: its `.default`/`.secondary`
    /// fills are white / #F5F5F7, which vanish on the page's #F7F7FA gradient.
    /// `Theme.surfaceBorder` is the one existing gray that reads as a filled pill.
    private var categoryPill: some View {
        Text(RecommendationDetailContent.categoryLabel(
            vibes: item.matchedVibes ?? [],
            type: item.recommendationType
        ))
        .knotFont(Theme.Typography.label)
        .tracking(0.8)
        .foregroundStyle(Theme.textSecondary)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(Theme.surfaceBorder))
    }

    private var metaLine: String? {
        RecommendationDetailContent.metaLine(
            locationText: locationText,
            merchantName: item.merchantName,
            isIdea: isIdea
        )
    }

    // MARK: - Stats Strip

    /// Three contextual columns in a white card. Omitted entirely when the item
    /// matched no profile factors (Saved-tab snapshots), so it never shows a "0".
    @ViewBuilder
    private var statsStrip: some View {
        if let stats = RecommendationDetailContent.stats(
            type: item.recommendationType,
            isIdea: isIdea,
            merchantName: item.merchantName,
            vibes: item.matchedVibes ?? [],
            loveLanguages: item.matchedLoveLanguages ?? [],
            interests: item.matchedInterests ?? []
        ) {
            KnotCard(padding: .none) {
                DetailStatsStrip(stats: stats)
            }
        }
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
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(uiImage: Lucide.heart)
                        .renderingMode(.template)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 16, height: 16)
                        .foregroundStyle(Theme.accent)
                        .accessibilityHidden(true)
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

    /// The description in a white card, for every type — each section on the
    /// page reads as a card, and the structured idea content that follows has
    /// its own headings.
    @ViewBuilder
    private var aboutBlock: some View {
        if let description = item.description, !description.isEmpty {
            KnotCard(padding: .lg) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("About")
                        .knotFont(Theme.Typography.cardTitleSemibold)
                        .foregroundStyle(Theme.textPrimary)
                    Text(description)
                        .knotFont(Theme.Typography.body)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: - Location

    @ViewBuilder
    private var locationCard: some View {
        if let whereText = RecommendationDetailContent.whereText(
            address: item.location?.address,
            city: item.location?.city,
            state: item.location?.state
        ) {
            KnotCard(padding: .lg) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Where you'll meet")
                        .knotFont(Theme.Typography.cardTitleSemibold)
                        .foregroundStyle(Theme.textPrimary)
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(uiImage: Lucide.mapPin)
                            .renderingMode(.template)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 16, height: 16)
                            .foregroundStyle(Theme.accent)
                            .accessibilityHidden(true)
                        Text(whereText)
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

    /// A purchasable item is "openable" only when it carries a real merchant link.
    /// The backend guarantees a resolved page or converts the card to an idea, so a
    /// linkless purchasable is rare — but never show a dead "Open" button if it happens,
    /// and never for a stale web-search/shopping link (degrade to Save instead).
    private var hasOpenableLink: Bool {
        guard let urlString = item.externalUrl, !urlString.isEmpty,
              let url = URL(string: urlString) else { return false }
        return !url.isSearchOrShoppingLink
    }

    @ViewBuilder
    private var primaryCTA: some View {
        if isIdea || !hasOpenableLink {
            saveFlavoredCTA
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

    /// Save → Saved → Continue. Shown for Knot Originals and for any purchasable
    /// that has no openable merchant link.
    @ViewBuilder
    private var saveFlavoredCTA: some View {
        switch saveCTAState {
        case .save:
            KnotButton(
                "Save to Library",
                variant: .primary,
                size: .lg,
                shape: .pill,
                leadingIcon: Lucide.bookmark,
                action: saveOnce
            )
        case .saved:
            KnotButton(
                "Saved",
                variant: .secondary,
                size: .lg,
                shape: .pill,
                leadingIcon: Lucide.bookmarkCheck,
                action: saveOnce
            )
        case .continueOn:
            KnotButton(
                "Continue",
                variant: .primary,
                size: .lg,
                shape: .pill,
                trailingIcon: Lucide.arrowRight,
                action: onDismiss
            )
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
        RecommendationDetailContent.locationText(city: item.location?.city, state: item.location?.state)
    }
}

// MARK: - Stats Strip

/// Three equal columns separated by hairline vertical rules — a bold value over
/// a small caption. Kept as its own struct (not inlined in `body`) so the detail
/// page's already-long body doesn't push the type-checker over its budget.
///
/// `.top` alignment keeps the three values on one line even when a caption
/// wraps to two; a `Divider` inside an `HStack` renders as a row-height
/// vertical hairline (the app's standard divider idiom).
private struct DetailStatsStrip: View {
    let stats: [RecommendationDetailContent.Stat]

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(stats.indices, id: \.self) { index in
                if index > 0 {
                    Divider().overlay(Theme.surfaceBorder)
                }
                column(stats[index])
            }
        }
    }

    private func column(_ stat: RecommendationDetailContent.Stat) -> some View {
        VStack(spacing: 3) {
            Text(stat.value)
                .knotFont(Theme.Typography.numeric)
                .foregroundStyle(stat.isAccent ? Theme.accent : Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            // Long captions ("Words of Affirmation", a merchant name) don't fit a
            // ~105pt column on one line; two lines, then truncate.
            Text(stat.label)
                .knotFont(Theme.Typography.label)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .padding(.horizontal, 6)
        .accessibilityElement(children: .combine)
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
        onDismiss: {}
    )
}

/// Shared sample recommendations for SwiftUI previews of the Spotlight views.
enum PreviewRecommendations {
    static let gift = decode(type: "gift", isIdea: false)
    static let experience = decode(type: "experience", isIdea: false)
    static let idea = decode(type: "idea", isIdea: true)

    /// A purchasable item with a real, resolved ticketing page — the CTA reads
    /// "Open in <merchant>" and opens a dedicated purchase page (never a web search).
    /// Used by the PR screenshot harness (see KnotApp.rootView).
    static let bookablePurchasable: RecommendationItemResponse = {
        let json = """
        {
            "id": "date-fonda", "recommendation_type": "date",
            "title": "Sunset Dinner & Live Jazz at The Fonda Theatre",
            "description": "Spend an evening at this iconic Hollywood Boulevard venue catching a live jazz performance, then grab dinner at a nearby quiet-luxury spot.",
            "price_cents": 8000, "currency": "USD", "price_confidence": "estimated",
            "external_url": "https://www.ticketmaster.com/the-fonda-theatre-tickets-los-angeles/venue/229121",
            "image_url": null, "merchant_name": "The Fonda Theatre / Ticketmaster", "source": "unified",
            "location": {"city": "Los Angeles", "state": "CA", "country": "US", "address": null},
            "is_idea": false,
            "interest_score": 0.9, "vibe_score": 0.8, "love_language_score": 0.7, "final_score": 0.82,
            "matched_interests": ["Music", "Travel"], "matched_vibes": ["quiet_luxury", "street_urban"],
            "matched_love_languages": ["words_of_affirmation", "acts_of_service"],
            "personalization_note": "You know how much Ronnie loves music and the energy of live performance—this hits that directly."
        }
        """.data(using: .utf8)!
        return try! JSONDecoder().decode(RecommendationItemResponse.self, from: json)
    }()

    /// A purchasable whose stored `external_url` is a stale Google-Shopping link (from
    /// before the URL fix). The detail CTA must degrade to "Save to Library" rather than
    /// open a Google results page. Used by the PR screenshot harness.
    static let staleSearchLink: RecommendationItemResponse = {
        let json = """
        {
            "id": "date-republique", "recommendation_type": "date",
            "title": "Dinner + Bookstore Evening in Los Feliz",
            "description": "An upscale French-California dinner paired with a browse through a beloved neighborhood bookstore — an easy, literary evening in Los Feliz.",
            "price_cents": 12000, "currency": "USD", "price_confidence": "estimated",
            "external_url": "https://www.google.com/search?tbm=shop&q=Republique+Los+Feliz+location",
            "image_url": null, "merchant_name": "Republique (Los Feliz location)", "source": "unified",
            "location": {"city": "Los Angeles", "state": "CA", "country": "US", "address": null},
            "is_idea": false,
            "interest_score": 0.9, "vibe_score": 0.8, "love_language_score": 0.7, "final_score": 0.82,
            "matched_interests": ["Cooking", "Reading", "Travel"], "matched_vibes": ["quiet_luxury", "street_urban"],
            "matched_love_languages": ["acts_of_service"],
            "personalization_note": "This weaves Ronnie's love of cooking, reading, and exploring a great neighborhood into one thoughtful evening."
        }
        """.data(using: .utf8)!
        return try! JSONDecoder().decode(RecommendationItemResponse.self, from: json)
    }()

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
