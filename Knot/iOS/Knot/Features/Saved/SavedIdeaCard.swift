//
//  SavedIdeaCard.swift
//  Knot
//
//  Created on September 6, 2026 (inside MilestoneDetailView.swift).
//  Moved here so the Saved tab and a Home event's detail screen render a
//  saved idea with the same card.
//

import SwiftUI

/// One saved idea, mirroring the comp's `Gift Card Item`: photo, title + price,
/// note, then a "SAVED" tag opposite a control that removes it.
///
/// Used by `MilestoneDetailView` (an event's saved ideas) and `SavedView` (the
/// whole library).
struct SavedIdeaCard: View {

    let saved: SavedRecommendation
    /// The list the card sits in, as VoiceOver names it in the remove
    /// control's label. The default matches the event detail screen's
    /// "Saved ideas" header; the Saved tab passes its own.
    var listName: String = "saved ideas"
    let onOpen: @MainActor () -> Void
    let onRemove: @MainActor () -> Void

    private static let imageHeight: CGFloat = 110

    var body: some View {
        KnotCard(padding: .md, radius: Theme.Radius.xl) {
            VStack(alignment: .leading, spacing: 12) {
                image
                titleRow
                notes

                Divider()
                    .overlay(Theme.surfaceBorder)

                actionsRow
            }
        }
        // `.onTapGesture` rather than a wrapping `Button` so the remove control
        // inside keeps hit-testing (the Step 19.9 pattern from `SavedView`).
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

    private var actionsRow: some View {
        HStack {
            KnotBadge("SAVED", variant: .accent, size: .sm)

            Spacer(minLength: 8)

            Button(action: onRemove) {
                KnotIconView(.bookmark, size: 20)
                    .foregroundStyle(Theme.accent)
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Self.removeAccessibilityLabel(title: saved.title, listName: listName))
        }
    }
}

// MARK: - Pure Helpers

extension SavedIdeaCard {

    /// VoiceOver label for the bookmark that removes the item: "Remove
    /// {title} from {list}". Pure and `static` so the wording is testable
    /// without rendering.
    static func removeAccessibilityLabel(title: String, listName: String) -> String {
        "Remove \(title) from \(listName)"
    }
}
