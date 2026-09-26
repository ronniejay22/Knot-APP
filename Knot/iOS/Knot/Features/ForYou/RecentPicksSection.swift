//
//  RecentPicksSection.swift
//  Knot
//
//  Step 19.62: The Journal's "Recent picks" — every set of recommendations
//  generated in the last few days, each reopenable until it expires.
//
//  Until this section existed, pressing Back after a generation run lost the
//  cards from the UI: `RecommendationsView` owns its view model as `@State`,
//  so popping it destroyed the picks even though the backend had already stored
//  them. The section is the history surface; the "Get recommendations" actions
//  elsewhere on the Journal keep generating fresh sets. A set leaves the section
//  when it expires, which is why the hint tells the user to save what they want
//  to keep — the Saved library is the permanent copy.
//

import SwiftUI

/// The "Recent picks" block on the Journal: a header with a count, a one-line
/// expiry hint, and one `RecentPickRow` per batch.
///
/// Renders nothing at all when there are no batches. No spinner and no empty
/// state either: the section is secondary to the milestone feed, and gating
/// or padding the screen for it would be the Step 18.18 mistake in reverse.
struct RecentPicksSection: View {
    let batches: [RecentRecommendationBatchResponse]
    /// The backend's recency window, as served alongside the batches. The
    /// number is the backend's to change, and the hint reads it rather than
    /// hardcoding it so the copy can never contradict the expiry badges.
    var windowDays: Int = 7
    /// Resolves a batch to its row title — the Journal's view model owns the
    /// milestone list, so it owns this lookup.
    let occasionLabel: (RecentRecommendationBatchResponse) -> String
    let onOpen: @MainActor (RecentRecommendationBatchResponse) -> Void

    /// The hint is what makes the expiry a feature rather than a surprise.
    static func expiryHint(windowDays: Int) -> String {
        let window = windowDays == 1 ? "a day" : "\(windowDays) days"
        return "Picks disappear after \(window) — save the ones you want to keep."
    }

    var body: some View {
        if !batches.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                header

                Text(Self.expiryHint(windowDays: windowDays))
                    .knotFont(Theme.Typography.label)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: 10) {
                    ForEach(batches) { batch in
                        RecentPickRow(
                            batch: batch,
                            occasionLabel: occasionLabel(batch),
                            onOpen: { onOpen(batch) }
                        )
                    }
                }
            }
        }
    }

    /// Same shape as the "Upcoming" header: title + accent count badge as one
    /// accessibility element. `.accent`, never `.secondary` — that variant's
    /// `surfaceElevated` fill is invisible on the Journal background (19.33).
    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            Text("Recent picks")
                .knotFont(Theme.Typography.sectionHeaderSemibold)
                .foregroundStyle(Theme.textPrimary)

            KnotBadge("\(batches.count)", variant: .accent, size: .sm)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.accessibilityLabel(count: batches.count))
    }

    /// "Recent picks, 1 set" / "Recent picks, 3 sets".
    static func accessibilityLabel(count: Int) -> String {
        "Recent picks, \(count) \(count == 1 ? "set" : "sets")"
    }
}

// MARK: - Row

/// One generated set: an overlapping trio of pick thumbnails, the occasion,
/// when it was generated, and an expiry badge. The whole row is a pressable
/// surface that reopens the set.
struct RecentPickRow: View {
    let batch: RecentRecommendationBatchResponse
    let occasionLabel: String
    let onOpen: @MainActor () -> Void

    /// Injected so the badge and labels are deterministic in tests and the
    /// screenshot harness; production reads the clock.
    var now: Date = Date()

    private static let thumbnailSize: CGFloat = 44
    private static let thumbnailOverlap: CGFloat = -14

    var body: some View {
        // A `Button` wearing `KnotPressableStyle`, not `.onTapGesture` — the
        // same call `MilestoneCard` makes (Step 19.56): `Button` waits for the
        // enclosing `ScrollView` to rule out a scroll before highlighting and
        // cancels the pressed state cleanly if one starts.
        Button(action: { rowTapped() }) {
            KnotCard(padding: .md, radius: Theme.Radius.xl) {
                HStack(alignment: .center, spacing: 12) {
                    thumbnails

                    // Three stacked lines, not "generated + badge" side by
                    // side: the text column is ~146pt on a 390pt device, and
                    // "2 days ago" beside an "Expires in 5 days" badge
                    // overran it and truncated to "2 days…".
                    VStack(alignment: .leading, spacing: 4) {
                        Text(occasionLabel)
                            .knotFont(Theme.Typography.cta)
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)

                        Text(generatedLabel)
                            .knotFont(Theme.Typography.label)
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)

                        // `.outline` for the ordinary state so the last-day
                        // `.destructive` red reads as a change — beside the
                        // accent pink it is all but the same colour.
                        KnotBadge(
                            expiryLabel,
                            variant: isExpiringSoon ? .destructive : .outline,
                            size: .sm
                        )
                        .fixedSize()
                        .padding(.top, 2)
                    }

                    Spacer(minLength: 4)

                    KnotIconView(.chevronRightOutlined, size: 16)
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(KnotPressableStyle())
        .accessibilityLabel(Self.accessibilityLabel(
            occasion: occasionLabel,
            picksCount: batch.recommendations.count,
            generatedLabel: generatedLabel,
            expiryLabel: expiryLabel
        ))
        .accessibilityHint("Opens these picks")
    }

    /// Fires the haptic as the tap lands and opens the set after the press
    /// hold, so the surface's spring-back is seen before the push moves it —
    /// the Step 19.57 rule. `delay: .zero` short-circuits for tests.
    func rowTapped(delay: Duration = Theme.Motion.pressHold) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        guard delay > .zero else {
            onOpen()
            return
        }
        Task {
            try? await Task.sleep(for: delay)
            onOpen()
        }
    }

    // MARK: Pieces

    /// Up to three overlapping thumbnails, first pick in front. Each is the
    /// bundled per-type photo with the remote image overlaid — a thumbnail is
    /// never blank in any `AsyncImage` phase (Step 19.13). The remote image is
    /// composed on `Color.clear` and clipped rather than sized directly: a
    /// `scaledToFill` image reports a size larger than its proposal and that
    /// overflow propagates into layout (Step 19.31).
    private var thumbnails: some View {
        HStack(spacing: Self.thumbnailOverlap) {
            ForEach(Array(batch.recommendations.prefix(3).enumerated()), id: \.element.id) { index, item in
                thumbnail(for: item)
                    .zIndex(Double(3 - index))
            }
        }
        .accessibilityHidden(true)
    }

    private func thumbnail(for item: MilestoneRecommendationItemResponse) -> some View {
        RecommendationFallbackImage(recommendationType: item.recommendationType)
            .overlay {
                if let urlString = item.imageUrl, let url = URL(string: urlString) {
                    AsyncImage(url: url) { phase in
                        if case .success(let remote) = phase {
                            Color.clear
                                .overlay { remote.resizable().scaledToFill() }
                                .clipped()
                        }
                    }
                }
            }
            .frame(width: Self.thumbnailSize, height: Self.thumbnailSize)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                    .stroke(Theme.surface, lineWidth: 2)
            )
    }

    private var generatedLabel: String {
        ForYouViewModel.generatedLabel(generatedAt: batch.generatedAt, now: now)
    }

    private var expiryLabel: String {
        ForYouViewModel.expiryLabel(expiresAt: batch.expiresAt, now: now)
    }

    private var isExpiringSoon: Bool {
        ForYouViewModel.isExpiringSoon(expiresAt: batch.expiresAt, now: now)
    }

    /// "Christmas, 3 picks, generated 2 days ago, expires in 5 days".
    static func accessibilityLabel(
        occasion: String,
        picksCount: Int,
        generatedLabel: String,
        expiryLabel: String
    ) -> String {
        let generated = generatedLabel == "Today" || generatedLabel == "Yesterday"
            ? "generated \(generatedLabel.lowercased())"
            : "generated \(generatedLabel)"
        return "\(occasion), \(ForYouViewModel.picksCountLabel(picksCount)), \(generated), \(expiryLabel.lowercased())"
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Recent picks") {
    let now = Date()
    let iso = ISO8601DateFormatter()
    func item(_ id: String, _ type: String, _ title: String) -> MilestoneRecommendationItemResponse {
        MilestoneRecommendationItemResponse(
            id: id, recommendationType: type, title: title, description: nil,
            externalUrl: nil, priceCents: 4200, merchantName: nil, imageUrl: nil,
            createdAt: iso.string(from: now), personalizationNote: nil,
            isIdea: type == "idea", contentSections: nil, headline: nil
        )
    }
    let fresh = RecentRecommendationBatchResponse(
        id: "b1", milestoneId: "m1",
        generatedAt: iso.string(from: now.addingTimeInterval(-2 * 86_400)),
        expiresAt: iso.string(from: now.addingTimeInterval(5 * 86_400)),
        recommendations: [item("1", "experience", "Pottery"), item("2", "gift", "Mug"), item("3", "idea", "Bake")]
    )
    let expiring = RecentRecommendationBatchResponse(
        id: "b2", milestoneId: nil,
        generatedAt: iso.string(from: now.addingTimeInterval(-6 * 86_400)),
        expiresAt: iso.string(from: now.addingTimeInterval(3 * 3_600)),
        recommendations: [item("4", "date", "Dinner"), item("5", "gift", "Book")]
    )

    return ScrollView {
        RecentPicksSection(
            batches: [fresh, expiring],
            occasionLabel: { $0.milestoneId == nil ? "Just because" : "Christmas" },
            onOpen: { _ in }
        )
        .padding(20)
    }
    .background(Theme.backgroundGradient.ignoresSafeArea())
}
#endif
