//
//  SavedIdeaCard.swift
//  Knot
//
//  Created on September 6, 2026 (inside MilestoneDetailView.swift).
//  Moved here so the Saved tab and a Journal event's detail screen render a
//  saved idea with the same card.
//

import SwiftUI
import LucideIcons

/// One saved idea, mirroring the comp's `Gift Card Item`: photo, title + price,
/// note, then a status tag opposite a control that removes it.
///
/// Used by `MilestoneDetailView` (an event's saved ideas) and `SavedView` (the
/// whole library). The Saved tab layers two extras on top, both opt-in so the
/// event detail screen renders exactly as it did before the card was shared:
/// a "We did this" footer action for date plans (`onMarkDone`), and the
/// `.moment` style for completed dates, which swaps the tag and shows the
/// rating and reflection the user left.
struct SavedIdeaCard: View {

    enum Style {
        /// Still to be done — the "SAVED" tag.
        case saved
        /// A date plan the user marked done — the "DONE" tag, plus stars and
        /// the reflection note.
        case moment
    }

    let saved: SavedRecommendation
    var style: Style = .saved
    let onOpen: @MainActor () -> Void
    let onRemove: @MainActor () -> Void
    /// Shows a "We did this" action in the footer when set. The Saved tab
    /// passes it only for items that can be done (`saved.isDoable`).
    var onMarkDone: (@MainActor () -> Void)? = nil

    private static let imageHeight: CGFloat = 110

    var body: some View {
        KnotCard(padding: .md, radius: Theme.Radius.xl) {
            VStack(alignment: .leading, spacing: 12) {
                image
                titleRow
                notes

                if style == .moment {
                    reflection
                }

                Divider()
                    .overlay(Theme.surfaceBorder)

                actionsRow
            }
        }
        // `.onTapGesture` rather than a wrapping `Button` so the controls
        // inside keep hit-testing (the Step 19.9 pattern from `SavedView`).
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        .accessibilityElement(children: .contain)
    }

    /// The bundled per-type photo is an always-present base beneath the remote
    /// image, so a card is never blank in any `AsyncImage` phase — the Step
    /// 19.13 rule. No gradient fallbacks on recommendation surfaces.
    private var image: some View {
        RecommendationFallbackImage(recommendationType: saved.recommendationType)
            .overlay {
                if let urlString = saved.imageURL, let url = URL(string: urlString) {
                    AsyncImage(url: url) { phase in
                        if case .success(let remote) = phase {
                            Color.clear
                                .overlay { remote.resizable().scaledToFill() }
                                .clipped()
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: Self.imageHeight)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
            .accessibilityHidden(true)
    }

    private var titleRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(saved.title)
                .knotFont(Theme.Typography.cta)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            Spacer(minLength: 8)

            if let priceCents = saved.priceCents {
                Text(RecommendationCard.formattedPrice(cents: priceCents, currency: saved.currency))
                    .knotFont(Theme.Typography.cta)
                    .foregroundStyle(Theme.accent)
                    .lineLimit(1)
                    .fixedSize()
                    .layoutPriority(1)
            }
        }
    }

    @ViewBuilder
    private var notes: some View {
        if let text = saved.descriptionText, !text.isEmpty {
            Text(text)
                .knotFont(Theme.Typography.bodySmall)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The rating and note left in the post-date reflection. Either can be
    /// missing — the reflection sheet makes the note optional.
    @ViewBuilder
    private var reflection: some View {
        if let rating = saved.rating {
            HStack(spacing: 4) {
                ForEach(1...5, id: \.self) { star in
                    Image(systemName: star <= rating ? "star.fill" : "star")
                        .font(.caption)
                        .foregroundStyle(star <= rating ? .yellow : Theme.textTertiary)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Rated \(rating) out of 5")
        }

        if let note = saved.reflectionNote, !note.isEmpty {
            Text("“\(note)”")
                .knotFont(Theme.Typography.bodySmall)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var actionsRow: some View {
        if let onMarkDone {
            // At large text sizes the tag, the pill and the bookmark stop
            // fitting on one line of a small phone, and the pill's
            // `.fixedSize()` would push the bookmark out of the card. Keep the
            // single row whenever it fits; otherwise the pill gets a
            // full-width row of its own under the tag and bookmark.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    tag

                    Spacer(minLength: 8)

                    // `.fixedSize()` because `KnotButton` stretches to fill the
                    // row by default; here it has to hug its label beside the tag.
                    markDoneButton(onMarkDone)
                        .fixedSize()

                    removeButton
                }

                VStack(spacing: 12) {
                    HStack {
                        tag
                        Spacer(minLength: 8)
                        removeButton
                    }

                    markDoneButton(onMarkDone)
                }
            }
        } else {
            HStack {
                tag
                Spacer(minLength: 8)
                removeButton
            }
        }
    }

    private var tag: some View {
        let badge = Self.badge(for: style)
        return KnotBadge(badge.text, variant: badge.variant, size: .sm)
    }

    private func markDoneButton(_ action: @escaping @MainActor () -> Void) -> some View {
        KnotButton(
            "We did this",
            variant: .outline,
            size: .sm,
            shape: .pill,
            leadingIcon: Lucide.check,
            action: action
        )
        .accessibilityLabel("Mark \(saved.title) as done")
        // Voice Control matches what is on screen, so the visible text has to
        // stay a name the button answers to (WCAG 2.5.3, label in name).
        .accessibilityInputLabels([Text("We did this"), Text("Mark \(saved.title) as done")])
    }

    private var removeButton: some View {
        Button(action: onRemove) {
            Image(uiImage: Lucide.bookmarkCheck)
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 20, height: 20)
                .foregroundStyle(Theme.accent)
                .frame(width: 34, height: 34)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Self.removeAccessibilityLabel(title: saved.title, style: style))
    }
}

// MARK: - Pure Helpers

extension SavedIdeaCard {

    /// The footer tag for a card style. Pure and `static` so the mapping is
    /// testable without rendering.
    static func badge(for style: Style) -> (text: String, variant: KnotBadge<Text>.Variant) {
        switch style {
        case .saved: return ("SAVED", .accent)
        case .moment: return ("DONE", .success)
        }
    }

    /// VoiceOver label for the bookmark that removes the item. It names the
    /// section the card sits in, so a completed date is not called a saved idea.
    static func removeAccessibilityLabel(title: String, style: Style) -> String {
        switch style {
        case .saved: return "Remove \(title) from saved ideas"
        case .moment: return "Remove \(title) from moments"
        }
    }
}
