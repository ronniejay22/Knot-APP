//
//  SpotlightDeckView.swift
//  Knot
//
//  Created on June 12, 2026.
//  Spotlight redesign: a focused, one-at-a-time recommendation deck with
//  👍 save / 👎 pass voting and tap-through to the rich detail page. Shared by
//  the onboarding reveal (`OnboardingCompletionView`) and the main For You loop
//  (`RecommendationsView`).
//

import SwiftUI
import LucideIcons

/// A Blinkist-style swipe/vote deck. Renders one `SpotlightCard` at a time from
/// `items`; the user can pass (👎), save (👍), or tap the card to open its detail
/// page. Drag-to-swipe mirrors the buttons (left = pass, right = save).
///
/// The deck owns only the current index and the swipe animation. Persistence,
/// feedback recording, detail presentation, and deck top-up are delegated to the
/// host via the callbacks below.
struct SpotlightDeckView: View {
    let items: [RecommendationItemResponse]
    var partnerName: String?

    /// Returns whether a recommendation is already saved (drives the card's badge).
    let isSaved: (String) -> Bool

    /// 👍 — save to library and advance.
    let onLike: @MainActor (RecommendationItemResponse) -> Void
    /// 👎 — record a dislike and advance.
    let onPass: @MainActor (RecommendationItemResponse) -> Void
    /// Tap — open the recommendation's detail page.
    let onOpenDetail: @MainActor (RecommendationItemResponse) -> Void
    /// Fired when the user advances past the last available card — the host should
    /// fetch more (or no-op if this is a fixed-size deck, e.g. onboarding).
    let onNeedMore: @MainActor () -> Void

    /// Whether a top-up fetch is currently in flight (drives the end-of-deck spinner).
    var isLoadingMore: Bool = false

    /// Changes when the host replaces the deck wholesale (fresh generate / full
    /// refresh) — the deck resets to the first card. A top-up append leaves this
    /// unchanged so the user keeps their place.
    var resetToken: Int = 0

    @State private var index: Int = 0
    @State private var dragOffset: CGSize = .zero
    /// True while a like/pass decision is animating out. Blocks a second tap/swipe
    /// from acting on the same card (double-recording feedback and skipping the
    /// next card), and is cleared if the deck is reset mid-fling.
    @State private var isDeciding = false

    private var currentItem: RecommendationItemResponse? {
        guard index >= 0, index < items.count else { return nil }
        return items[index]
    }

    private let swipeThreshold: CGFloat = 110

    var body: some View {
        VStack(spacing: 0) {
            progressRow
                .padding(.horizontal, 20)
                .padding(.bottom, 14)

            if let item = currentItem {
                cardStack(item: item)
                actionButtons(item: item)
                    .padding(.top, 20)
                    .padding(.bottom, 8)
            } else {
                endOfDeck
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: resetToken) { _, _ in
            index = 0
            dragOffset = .zero
            isDeciding = false
        }
    }

    // MARK: - Progress Row

    private var progressRow: some View {
        HStack(spacing: 6) {
            ForEach(0..<max(items.count, 1), id: \.self) { i in
                Capsule()
                    .fill(i == min(index, items.count - 1) ? Theme.accent : Theme.surfaceBorder)
                    .frame(width: i == min(index, items.count - 1) ? 22 : 7, height: 7)
                    .animation(Theme.Motion.standard, value: index)
            }
            Spacer()
            Text("\(min(index + 1, items.count)) of \(items.count)")
                .knotFont(Theme.Typography.label)
                .foregroundStyle(Theme.textTertiary)
        }
    }

    // MARK: - Card

    private func cardStack(item: RecommendationItemResponse) -> some View {
        let dir = dragOffset.width
        return SpotlightCard(
            item: item,
            partnerName: partnerName,
            isSaved: isSaved(item.id),
            onSeeDetails: { onOpenDetail(item) }
        )
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .offset(x: dragOffset.width, y: dragOffset.height * 0.2)
        .rotationEffect(.degrees(Double(dragOffset.width / 22)))
        .overlay(alignment: .topLeading) { decisionStamp(visible: dir < -30, like: false) }
        .overlay(alignment: .topTrailing) { decisionStamp(visible: dir > 30, like: true) }
        .gesture(
            DragGesture()
                .onChanged { value in
                    dragOffset = value.translation
                }
                .onEnded { value in
                    if value.translation.width > swipeThreshold {
                        performDecision(like: true)
                    } else if value.translation.width < -swipeThreshold {
                        performDecision(like: false)
                    } else {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                            dragOffset = .zero
                        }
                    }
                }
        )
    }

    /// A "SAVE" / "PASS" stamp that fades in as the card is dragged toward a side.
    private func decisionStamp(visible: Bool, like: Bool) -> some View {
        Text(like ? "SAVE" : "PASS")
            .knotFont(Theme.Typography.cta)
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                Capsule().fill(like ? Theme.statusSuccess : Theme.textTertiary)
            )
            .rotationEffect(.degrees(like ? -12 : 12))
            .padding(36)
            .opacity(visible ? 1 : 0)
            .animation(Theme.Motion.quick, value: visible)
    }

    // MARK: - Action Buttons

    private func actionButtons(item: RecommendationItemResponse) -> some View {
        HStack(spacing: 36) {
            circleActionButton(
                icon: Lucide.thumbsDown,
                fill: Theme.surfaceElevated,
                tint: Theme.textSecondary,
                label: "Pass"
            ) {
                performDecision(like: false)
            }

            circleActionButton(
                icon: Lucide.thumbsUp,
                fill: Theme.statusSuccess,
                tint: .white,
                label: "Save"
            ) {
                performDecision(like: true)
            }
        }
    }

    private func circleActionButton(
        icon: UIImage,
        fill: Color,
        tint: Color,
        label: String,
        action: @escaping @MainActor () -> Void
    ) -> some View {
        Button(action: action) {
            Image(uiImage: icon)
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 30, height: 30)
                .foregroundStyle(tint)
                .frame(width: 72, height: 72)
                .background(Circle().fill(fill))
                .shadow(Theme.Shadow.md)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    // MARK: - End of Deck

    private var endOfDeck: some View {
        VStack(spacing: 16) {
            if isLoadingMore {
                ProgressView()
                    .tint(Theme.accent)
                    .scaleEffect(1.2)
                Text("Finding more for you…")
                    .knotFont(Theme.Typography.cta)
                    .foregroundStyle(Theme.textSecondary)
            } else {
                Image(uiImage: Lucide.check)
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 36, height: 36)
                    .foregroundStyle(Theme.accent)
                Text("That's all for now")
                    .knotFont(Theme.Typography.cardTitle)
                    .foregroundStyle(Theme.textPrimary)
                Text("Saved picks are waiting in your library.")
                    .knotFont(Theme.Typography.body)
                    .foregroundStyle(Theme.textTertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    // MARK: - Decision Logic

    private func performDecision(like: Bool) {
        guard !isDeciding, let item = currentItem else { return }
        isDeciding = true

        UIImpactFeedbackGenerator(style: like ? .medium : .light).impactOccurred()

        let direction: CGFloat = like ? 1 : -1
        withAnimation(.easeIn(duration: 0.22)) {
            dragOffset = CGSize(width: direction * 700, height: 0)
        }

        if like {
            onLike(item)
        } else {
            onPass(item)
        }

        // After the card flings off-screen, reset and advance — unless the deck
        // was replaced mid-fling (resetToken change clears isDeciding), in which
        // case this stale advance is skipped so we don't desync the new deck.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            guard isDeciding else { return }
            dragOffset = .zero
            advance()
            isDeciding = false
        }
    }

    private func advance() {
        let next = index + 1
        index = next
        if next >= items.count {
            onNeedMore()
        }
    }
}

// MARK: - Spotlight Card

/// The enlarged, focused card shown in the deck and the onboarding carousel — a
/// full-bleed hero image with the type badge, and the match chips, title,
/// description, and a "See Details" button overlaid over a scrim at the bottom.
/// The card itself owns the "See Details" action; swipe/vote (deck) and paging
/// (carousel) are handled by the parent container.
struct SpotlightCard: View {
    let item: RecommendationItemResponse
    var partnerName: String?
    let isSaved: Bool
    /// Opens the recommendation's detail page (the pink "See Details" button).
    var onSeeDetails: () -> Void

    private let cardCornerRadius: CGFloat = 22

    var body: some View {
        ZStack(alignment: .bottom) {
            imageBackground

            // Uniform dark tint over the whole photo (#1F1A29 @ 85%) so the image
            // reads as a moody backdrop and the overlaid content stays legible.
            Color(red: 0x1F / 255, green: 0x1A / 255, blue: 0x29 / 255)
                .opacity(0.85)

            // Scrims — light at the top (badge legibility), heavy at the bottom
            // so the overlaid chips/title/description/button stay readable.
            VStack(spacing: 0) {
                LinearGradient(colors: [.black.opacity(0.35), .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: 90)
                Spacer(minLength: 0)
                LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 340)
            }

            // Top row: type badge + saved indicator
            VStack {
                HStack(alignment: .top) {
                    typeBadge
                    Spacer()
                    if isSaved {
                        Image(uiImage: Lucide.bookmarkCheck)
                            .renderingMode(.template)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 14, height: 14)
                            .foregroundStyle(Theme.accent)
                            .padding(8)
                            .background(
                                Circle().fill(.ultraThinMaterial).environment(\.colorScheme, .dark)
                            )
                    }
                }
                .padding(14)
                Spacer()
            }

            bottomOverlay
                .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: cardCornerRadius))
        .shadow(Theme.Shadow.lg)
    }

    // MARK: - Image

    @ViewBuilder
    private var imageBackground: some View {
        if let imageURL = item.imageUrl, let url = URL(string: imageURL) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    Color.clear.overlay {
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    }
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
    }

    // MARK: - Bottom Overlay

    private var bottomOverlay: some View {
        VStack(alignment: .leading, spacing: 12) {
            let chips = RecommendationDisplayChip.build(
                vibes: item.matchedVibes ?? [],
                loveLanguages: item.matchedLoveLanguages ?? [],
                interests: item.matchedInterests ?? []
            )
            if !chips.isEmpty {
                FlowLayout(horizontalSpacing: 8, verticalSpacing: 8) {
                    ForEach(chips) { chip in
                        MatchingFactorChip(label: chip.label, style: chip.style, onImage: true)
                    }
                }
                // Force the flow layout to measure against the real card width
                // (not an unconstrained one), so its reported height accounts for
                // wrapped rows and the title below it never overlaps the chips.
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Text(item.title)
                .knotFont(Theme.Typography.cardTitle)
                .foregroundStyle(.white)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            if let description = descriptionText {
                Text(description)
                    .knotFont(Theme.Typography.body)
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
            }

            KnotButton(
                "See Details",
                variant: .primary,
                size: .lg,
                shape: .rounded,
                action: onSeeDetails
            )
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var descriptionText: String? {
        guard let description = item.description?.trimmingCharacters(in: .whitespacesAndNewlines),
              !description.isEmpty else { return nil }
        return description
    }

    private var fallbackGradient: some View {
        ZStack {
            LinearGradient(colors: fallbackGradientColors, startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: typeIconSystemName)
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.white.opacity(0.15))
        }
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
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule().fill(.ultraThinMaterial).environment(\.colorScheme, .dark)
        )
    }

    // MARK: - Type Helpers

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

// MARK: - Spotlight Carousel

/// A browse-only, paged version of the Spotlight cards used by the onboarding
/// reveal. Unlike `SpotlightDeckView`, there is no save/pass voting — the user
/// swipes horizontally between a fixed set of `SpotlightCard`s (page dots track
/// position) and taps "See Details" to open the detail page. Saving happens later
/// (the For You deck, or the detail page's Save button).
struct SpotlightCarouselView: View {
    let items: [RecommendationItemResponse]
    var partnerName: String?

    /// Returns whether a recommendation is already saved (drives the card badge).
    let isSaved: (String) -> Bool

    /// Tap — open the recommendation's detail page.
    let onOpenDetail: @MainActor (RecommendationItemResponse) -> Void

    @State private var index: Int = 0

    var body: some View {
        VStack(spacing: 16) {
            TabView(selection: $index) {
                ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                    SpotlightCard(
                        item: item,
                        partnerName: partnerName,
                        isSaved: isSaved(item.id),
                        onSeeDetails: { onOpenDetail(item) }
                    )
                    .padding(.horizontal, 20)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            if items.count > 1 {
                pageDots
            }
        }
    }

    private var pageDots: some View {
        HStack(spacing: 7) {
            ForEach(0..<items.count, id: \.self) { i in
                Circle()
                    .fill(i == index ? Theme.accent : Theme.surfaceBorder)
                    .frame(width: 7, height: 7)
                    .animation(Theme.Motion.standard, value: index)
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Spotlight Deck") {
    ZStack {
        Theme.backgroundGradient.ignoresSafeArea()
        SpotlightDeckView(
            items: [
                PreviewRecommendations.decode(type: "gift", isIdea: false),
                PreviewRecommendations.decode(type: "experience", isIdea: false),
                PreviewRecommendations.decode(type: "idea", isIdea: true),
            ],
            partnerName: "Alex",
            isSaved: { _ in false },
            onLike: { _ in },
            onPass: { _ in },
            onOpenDetail: { _ in },
            onNeedMore: {}
        )
    }
}

#Preview("Spotlight Carousel") {
    ZStack {
        Theme.backgroundGradient.ignoresSafeArea()
        VStack(spacing: 0) {
            SpotlightCarouselView(
                items: [
                    PreviewRecommendations.decode(type: "date", isIdea: false),
                    PreviewRecommendations.decode(type: "experience", isIdea: false),
                    PreviewRecommendations.decode(type: "idea", isIdea: true),
                ],
                partnerName: "Jas",
                isSaved: { _ in false },
                onOpenDetail: { _ in }
            )
        }
        .padding(.vertical, 24)
    }
}
#endif
