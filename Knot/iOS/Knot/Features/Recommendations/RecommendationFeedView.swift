//
//  RecommendationFeedView.swift
//  Knot
//
//  Step 19.59: The recommendations presentation — a vertically scrolling list
//  where each of the three picks is a bold section heading over a fixed-height,
//  full-width photo card. Replaces the horizontal paged carousel
//  (`SpotlightCarouselView` / `SpotlightCard`, removed in the same step).
//
//  Two views:
//  - `RecommendationFeedCard` — one pick as a pressable photo card: the photo
//    fills it, a dark scrim covers the bottom half, and the title + a two-line
//    description sit over the scrim. Pressing anywhere on the card opens the
//    detail page; there is no separate "See Details" button.
//  - `RecommendationFeedList` — the section-heading + card stack for all
//    picks. It deliberately has NO `ScrollView` of its own: each host
//    (`RecommendationsView`, `OnboardingCompletionView`) supplies one so it can
//    place its own content above the list (the "Knot's Take" briefing card,
//    the onboarding step header) and own the gutters and bottom clearance.
//    Both surfaces render the same list, which is what keeps the For You reveal
//    and the in-onboarding reveal identical (Step 18.49's intent).
//

import SwiftUI
import LucideIcons

// MARK: - Feed Card

/// One recommendation as a fixed-height, full-width photo card.
///
/// Press mechanics mirror `MilestoneCard`: the whole card is a `Button` wearing
/// `KnotPressableStyle`, so it settles under the finger and springs back on
/// release, then opens the detail after the press hold has been seen.
struct RecommendationFeedCard: View {
    let item: RecommendationItemResponse
    let isSaved: Bool
    /// Opens the recommendation's detail page. `@MainActor` — the same
    /// convention as `MilestoneCard.onSeeDetails` and the deck's old callbacks.
    let onOpenDetail: @MainActor () -> Void

    /// The mock's cards are roughly 2:1 against the screen's width (~370pt of
    /// card inside 20pt gutters on a 402pt screen), and both the remote
    /// recommendation photos and the bundled `RecFallback*` fallbacks are
    /// landscape, so 200pt keeps the crop close to the photos' own proportions
    /// while letting two cards and a heading share the viewport.
    static let cardHeight: CGFloat = 200

    var body: some View {
        // `Button` rather than `.onTapGesture` + a pressed flag, for the reason
        // `MilestoneCard` records: inside a `ScrollView`, `Button` waits for the
        // scroll view to rule out a scroll before highlighting and cancels the
        // pressed state cleanly if one starts. There are no inner controls here
        // (the saved indicator is a glyph, not a button), so the Button's
        // default single accessibility element is the right shape — with an
        // explicit label below, since the merged one would otherwise read the
        // fallback asset's name and the loading spinner's "In progress".
        Button(action: { cardTapped() }) {
            ZStack(alignment: .bottomLeading) {
                imageBackground
                    .accessibilityHidden(true)

                // Bottom-half scrim only. Unlike the old Spotlight card there is
                // no uniform tint — the mock's photos read bright, and the scrim
                // is what keeps the white copy legible.
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.45),
                        .init(color: .black.opacity(0.8), location: 1.0),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                if isSaved {
                    savedIndicator
                }

                textOverlay
            }
            .frame(maxWidth: .infinity)
            .frame(height: Self.cardHeight)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.xl, style: .continuous))
            .shadow(Theme.Shadow.md)
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.xl, style: .continuous))
        }
        .buttonStyle(KnotPressableStyle())
        .accessibilityLabel(Self.accessibilityLabel(title: item.title, description: descriptionText, isSaved: isSaved))
        .accessibilityHint("Opens the details")
    }

    /// Opens the detail: a light impact as the tap lands, then the cover.
    ///
    /// Same shape as `MilestoneCard.cardTapped(delay:)`, for the same reason.
    /// `Button` runs its action on touch-up, and `KnotPressableStyle` keeps the
    /// card pressed for `Theme.Motion.pressHold` after touch-*down* — so
    /// presenting immediately would slide the cover over a card that was still
    /// pressed and hide the spring-back. Waiting the same hold after touch-up
    /// guarantees the release has begun before the cover moves.
    ///
    /// Internal (not folded into the button closure) so the forwarding is
    /// unit-testable without view introspection; `delay: .zero` fires
    /// synchronously for tests that only care *that* it forwards.
    func cardTapped(delay: Duration = Theme.Motion.pressHold) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        guard delay > .zero else {
            onOpenDetail()
            return
        }
        Task {
            try? await Task.sleep(for: delay)
            onOpenDetail()
        }
    }

    /// The card's single VoiceOver label: "Title. Description, Saved". Pure,
    /// so the composition is tested without rendering.
    static func accessibilityLabel(title: String, description: String?, isSaved: Bool) -> String {
        var parts: [String] = [title]
        if let description, !description.isEmpty {
            parts.append(description)
        }
        var label = parts.joined(separator: ". ")
        if isSaved {
            label += ", Saved"
        }
        return label
    }

    // MARK: - Image

    /// The photo layer. Carried over from the Spotlight card unchanged: a local
    /// bundled photo is always underneath, so a real image shows before the
    /// remote loads, when there is no URL, or if the load fails — a
    /// recommendation card never shows a gradient or a blank (Step 19.13).
    ///
    /// Both layers compose their image as an overlay on `Color.clear`, which
    /// accepts whatever size it is proposed, so the card's `.frame` is
    /// authoritative. A `.scaledToFill` image sized directly reports a size
    /// *larger* than its proposal, and that overflow propagates into layout —
    /// the bug that pushed the whole Journal sideways in Step 19.31.
    /// `clipShape` / `clipped` clip pixels; they do not constrain layout.
    @ViewBuilder
    private var imageBackground: some View {
        ZStack {
            RecommendationFallbackImage(recommendationType: item.recommendationType)

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
                    case .empty:
                        // Keep the local photo visible while the remote loads.
                        ProgressView().tint(.white.opacity(0.5))
                    default:
                        // .failure / @unknown — the local photo shows through.
                        Color.clear
                    }
                }
            }
        }
    }

    // MARK: - Saved Indicator

    /// Top-trailing bookmark glyph, shown only for a saved pick. Carried over
    /// from the Spotlight card; the material circle keeps it legible on a
    /// bright photo without needing a top scrim.
    private var savedIndicator: some View {
        VStack {
            HStack(alignment: .top) {
                Spacer()
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
            .padding(14)
            Spacer()
        }
        .accessibilityHidden(true)
    }

    // MARK: - Text Overlay

    private var textOverlay: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(item.title)
                .knotFont(Theme.Typography.cardTitleSemibold)
                .foregroundStyle(.white)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            if let description = descriptionText {
                Text(description)
                    .knotFont(Theme.Typography.bodySmall)
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var descriptionText: String? {
        guard let description = item.description?.trimmingCharacters(in: .whitespacesAndNewlines),
              !description.isEmpty else { return nil }
        return description
    }
}

// MARK: - Feed List

/// The section-heading + card stack for every pick, in order. No `ScrollView`
/// here — see the file header for why the host owns it.
struct RecommendationFeedList: View {
    let items: [RecommendationItemResponse]
    let isSaved: (String) -> Bool
    let onOpenDetail: @MainActor (RecommendationItemResponse) -> Void

    var body: some View {
        // A plain `VStack`: there are three items, so laziness buys nothing and
        // a `LazyVStack`'s deferred layout would only churn the reveal animation.
        VStack(alignment: .leading, spacing: 20) {
            ForEach(items) { item in
                VStack(alignment: .leading, spacing: 12) {
                    Text(Self.sectionLabel(for: item.recommendationType))
                        .knotFont(Theme.Typography.feedSectionHeader)
                        .foregroundStyle(Theme.textPrimary)
                        .accessibilityAddTraits(.isHeader)

                    RecommendationFeedCard(
                        item: item,
                        isSaved: isSaved(item.id),
                        onOpenDetail: { onOpenDetail(item) }
                    )
                }
            }
        }
    }

    /// The editorial heading above a pick, derived on-device from its type so
    /// the feed reads like the mock's "collections" without any backend field.
    ///
    /// Deliberately NOT the uppercase type *tag* that `RecommendationDetailView`'s
    /// hero badge and `RecommendationCard` render (`typeLabel`: "Date", "Idea").
    /// Those are tags; this is a 20pt heading, where "Date" reads as a calendar
    /// date and "Idea" says nothing. "Knot Original" is the phrase the detail
    /// page already uses for a non-purchasable pick. An unknown type from a
    /// newer backend degrades to a generic-but-correct heading rather than
    /// leaking the raw key. Pinned by `RecommendationFeedTests`.
    static func sectionLabel(for recommendationType: String) -> String {
        switch recommendationType {
        case "gift": return "Gift"
        case "experience": return "Experience"
        case "date": return "Date Idea"
        case "idea": return "Knot Original"
        case "plan": return "Date Plan"
        default: return "Recommendation"
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Recommendation feed") {
    ScrollView {
        RecommendationFeedList(
            items: [
                PreviewRecommendations.experience,
                PreviewRecommendations.gift,
                PreviewRecommendations.idea,
            ],
            isSaved: { $0 == PreviewRecommendations.gift.id },
            onOpenDetail: { _ in }
        )
        .padding(20)
    }
    .background(Theme.backgroundGradient.ignoresSafeArea())
}
#endif
