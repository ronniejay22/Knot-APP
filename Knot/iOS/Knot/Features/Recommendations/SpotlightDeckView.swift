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
            }

            Spacer(minLength: 0)
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
            isSaved: isSaved(item.id)
        )
        .padding(.horizontal, 20)
        .offset(x: dragOffset.width, y: dragOffset.height * 0.2)
        .rotationEffect(.degrees(Double(dragOffset.width / 22)))
        .overlay(alignment: .topLeading) { decisionStamp(visible: dir < -30, like: false) }
        .overlay(alignment: .topTrailing) { decisionStamp(visible: dir > 30, like: true) }
        .contentShape(Rectangle())
        .onTapGesture { onOpenDetail(item) }
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

/// The enlarged, focused card shown in the deck — a hero image with the type
/// badge and personalization snippet, then title, meta line, and match chips.
/// Tapping is handled by the parent (`SpotlightDeckView`), which opens the
/// detail page.
struct SpotlightCard: View {
    let item: RecommendationItemResponse
    var partnerName: String?
    let isSaved: Bool

    private let heroHeight: CGFloat = 300
    private let cardCornerRadius: CGFloat = 22

    private var isIdea: Bool {
        item.isIdea == true || item.recommendationType == "plan"
    }

    var body: some View {
        KnotCard(variant: .default, padding: .none, radius: cardCornerRadius) {
            VStack(alignment: .leading, spacing: 0) {
                heroSection
                detailsSection
            }
        }
        .shadow(Theme.Shadow.lg)
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

            // Scrims
            VStack {
                LinearGradient(colors: [.black.opacity(0.35), .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: 70)
                Spacer()
                LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 110)
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

            // Personalization snippet bottom-leading
            if let note = personalizationNote {
                VStack {
                    Spacer()
                    HStack {
                        personalizationOverlay(note: note)
                        Spacer(minLength: 0)
                    }
                    .padding(14)
                }
            }
        }
        .frame(height: heroHeight)
        .clipped()
    }

    private var personalizationNote: String? {
        guard let note = item.personalizationNote?.trimmingCharacters(in: .whitespacesAndNewlines),
              !note.isEmpty else { return nil }
        return note
    }

    private func personalizationOverlay(note: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(uiImage: Lucide.sparkles)
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 12, height: 12)
                .foregroundStyle(.white)
                .padding(.top, 2)

            Text(note)
                .knotFont(Theme.Typography.italicQuote)
                .foregroundStyle(.white)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
        )
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

    // MARK: - Details

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(item.title)
                .knotFont(Theme.Typography.cardTitle)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            metaLine

            let chips = RecommendationDisplayChip.build(
                vibes: item.matchedVibes ?? [],
                loveLanguages: item.matchedLoveLanguages ?? [],
                interests: item.matchedInterests ?? []
            )
            if !chips.isEmpty {
                FlowLayout(horizontalSpacing: 6, verticalSpacing: 6) {
                    ForEach(chips) { chip in
                        MatchingFactorChip(label: chip.label, style: chip.style)
                    }
                }
            }

            // Tap affordance
            HStack(spacing: 5) {
                Image(uiImage: Lucide.arrowUpRight)
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 12, height: 12)
                Text("Tap for details")
                    .knotFont(Theme.Typography.label)
            }
            .foregroundStyle(Theme.accent)
            .padding(.top, 2)
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
                            .knotFont(Theme.Typography.label)
                            .lineLimit(1)
                    }
                    .foregroundStyle(Theme.textSecondary)
                }
                Spacer(minLength: 0)
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
        if let loc = locationText {
            parts.append(MetaPart(icon: Lucide.mapPin, text: loc))
        }
        return parts
    }

    private var locationText: String? {
        guard let location = item.location else { return nil }
        let cityState = [location.city, location.state]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
        guard !cityState.isEmpty else { return nil }
        return cityState.joined(separator: ", ")
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
#endif
