//
//  MilestoneRecommendationSheet.swift
//  Knot
//
//  Created on September 8, 2026.
//  The bottom sheet raised by a Journal card's recommendation (sparkle) icon.
//
//  All three content slots come from `MilestoneRecommendationCopy`, which
//  resolves them from the milestone's `occasion_category`, its day count and the
//  partner's name — see that file for why the copy is framed rather than
//  hand-written per occasion.
//

import SwiftUI
import LucideIcons

/// Ideal height of the sheet's content, published up from the layout pass so
/// the detent can track it.
///
/// `static let`, not `static var` — a stored mutable static is a hard error
/// under Swift 6 strict concurrency, and a `let` satisfies `PreferenceKey`'s
/// get-only requirement.
private struct SheetContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Asks whether the user wants ideas for one upcoming event, and routes them
/// into that event's recommendations. Implements Figma node 259:554.
///
/// Presented as a stock `.sheet` from `ForYouView` — the house idiom for every
/// bottom sheet in the app (`PurchasePromptSheet`, `PurchaseRatingSheet`,
/// `MilestoneFormSheet`, …). That gives the scrim, the grab indicator and
/// drag-to-dismiss for free, and covers the `KnotTabBar` that `MainTabView`
/// mounts via `.safeAreaInset` — a UIKit modal presentation sits above the
/// presenting controller's *entire* view, which is exactly what a `ZStack`
/// layer inside `ForYouView` could not do.
///
/// The hand-rolled `fullScreenCover` + `presentationBackground(.clear)` +
/// `disablesAnimations` machinery in `RelationshipLengthModal` /
/// `MilestoneDateModal` / `OccasionEntryModal` exists to defeat the sheet's
/// bottom-slide so a card can float *centered*. This is a bottom sheet; using
/// that apparatus here would hand-roll what `.sheet` already does and add a
/// fourth copy of debt the memory bank already flags.
///
/// The view configures its own presentation so the height measurement stays
/// encapsulated — see `heightReader` and `adopt(_:)`.
struct MilestoneRecommendationSheet: View {

    let milestone: MilestoneItemResponse
    let partnerName: String

    /// Pre-formatted "MMM d", as `ForYouViewModel.formattedDate(_:)` produces
    /// it. Deliberately *not* `MilestoneCard.dateLabel(from:)`, which uppercases
    /// for the card's letterspaced meta row; the comp shows "Dec 25".
    let formattedDate: String

    let onGetRecommendations: @MainActor () -> Void
    let onDismiss: @MainActor () -> Void

    /// Drives `.presentationDetents`, so the sheet hugs its content rather than
    /// sitting at an arbitrary `.medium`. Seeded near the comp's height so the
    /// entrance animates to roughly the right size instead of landing and then
    /// visibly resizing.
    @State private var contentHeight: CGFloat = MilestoneRecommendationSheet.estimatedHeight
    @State private var hasMeasured = false

    /// Only used until the real measurement lands on the first layout pass, so
    /// it just has to be *close* — the point is that the sheet doesn't visibly
    /// resize on present. Measured at ~500pt on a 402pt-wide screen, where the
    /// headline wraps to two lines and the body to three; the exact value moves
    /// with the milestone name, the screen width and the text size, which is
    /// why it is measured rather than hardcoded.
    static let estimatedHeight: CGFloat = 500

    /// The comp's 24pt top corners. `Theme.Radius` tops out at 18, and a token
    /// with a single consumer would be worse than a documented constant.
    private static let cornerRadius: CGFloat = 24

    var body: some View {
        // The reader spans the whole card *including* the home-indicator strip,
        // so `safeAreaInsets.bottom` reports the clearance the detent has to pay
        // for on top of the content. Without that term the detent is the bare
        // content height, and "Not now" ends up under the home indicator with
        // the sheet scrollable at rest.
        GeometryReader { proxy in
            sheet(bottomInset: proxy.safeAreaInsets.bottom)
        }
        .ignoresSafeArea(.container, edges: .bottom)
        // One detent whose *value* tracks the measurement — never a changing
        // detent *set*, which UIKit would resolve by snapping. It clamps a
        // custom detent to the maximum the sheet can be, so an accessibility
        // text size resolves to a full-height sheet and the ScrollView takes
        // over rather than the content clipping.
        .presentationDetents([.height(max(contentHeight, 1))])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(Self.cornerRadius)
    }

    private func sheet(bottomInset: CGFloat) -> some View {
        ScrollView {
            content
                // LOAD-BEARING. On the first pass the sheet is only the seed
                // height; without this the stack is laid out against that
                // proposal, the 26pt title truncates, and we measure the
                // *truncated* height — so the sheet would shrink instead of
                // growing. `.fixedSize(vertical:)` lays the stack out at its
                // ideal height whatever the proposal.
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Theme.Spacing.xxl)
                // Clears the system drag indicator, which draws inside the
                // sheet's top inset rather than above the content.
                .padding(.top, Theme.Spacing.xxl)
                .padding(.bottom, Theme.Spacing.lg + bottomInset)
                .background(heightReader)
        }
        // The ScrollView is only the overflow valve for accessibility text
        // sizes; at every normal size the content fits the detent exactly, and
        // `.basedOnSize` stops it rubber-banding when it does.
        .scrollBounceBehavior(.basedOnSize)
        .background(Theme.surface)
        .onPreferenceChange(SheetContentHeightKey.self, perform: adopt)
    }

    // MARK: - Content

    private var content: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            header
            actions
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Resolved once per body evaluation so the badge, title and body are
    /// guaranteed to describe the same occasion.
    private var copy: MilestoneRecommendationCopy {
        MilestoneRecommendationCopy.resolve(
            milestone: milestone,
            partnerName: partnerName,
            formattedDate: formattedDate
        )
    }

    private var header: some View {
        let copy = self.copy

        return HStack(alignment: .top, spacing: Theme.Spacing.lg) {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                KnotBadge(copy.badge, variant: .accent, size: .sm)

                Text(copy.title)
                    .knotFont(Theme.Typography.sheetTitle)
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                Text(copy.body)
                    .knotFont(Theme.Typography.bodySmall)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // A plain Button rather than `KnotIconButton(.ghost)`: that variant
            // paints `Theme.accent`, and a pink X reads as an action rather than
            // a dismiss. Same call `OccasionEntryModal` makes.
            Button(action: onDismiss) {
                Image(uiImage: Lucide.x)
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 20, height: 20)
                    .foregroundStyle(Theme.textSecondary)
                    // Keeps the tap target generous without widening the layout.
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
    }

    private var actions: some View {
        VStack(spacing: Theme.Spacing.md) {
            // `KnotButton` already applies `.frame(maxWidth: .infinity)`, so the
            // comp's full-width actions need nothing extra here.
            KnotButton(
                "Get recommendations",
                variant: .primary,
                size: .lg,
                action: onGetRecommendations
            )

            // `.outlineNeutral`, not `.outline`: the latter is accent-on-accent
            // and would read as a second call to action beside the pink CTA.
            KnotButton(
                "Not now",
                variant: .outlineNeutral,
                size: .lg,
                action: onDismiss
            )
        }
    }

    // MARK: - Height

    private var heightReader: some View {
        GeometryReader { proxy in
            Color.clear.preference(key: SheetContentHeightKey.self, value: proxy.size.height)
        }
    }

    /// Damped so sub-point layout churn can't start a resize loop, and
    /// un-animated on the first correction so the sheet doesn't visibly jump off
    /// its seed the moment it lands. Later changes (Dynamic Type) do animate.
    private func adopt(_ measured: CGFloat) {
        let rounded = measured.rounded(.up)
        guard rounded > 0, abs(rounded - contentHeight) > 0.5 else { return }

        guard hasMeasured else {
            hasMeasured = true
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { contentHeight = rounded }
            return
        }
        contentHeight = rounded
    }
}

// MARK: - Preview

#if DEBUG
/// One preview per framing, since the whole point of the copy framework is that
/// these read differently. Check the headline wrap and the body height here
/// before shipping copy changes — the sheet's detent tracks its content.
private func previewSheet(
    name: String,
    date: String,
    category: String,
    type: String = "holiday",
    daysUntil: Int? = 175
) -> some View {
    Theme.backgroundGradient
        .ignoresSafeArea()
        .sheet(isPresented: .constant(true)) {
            MilestoneRecommendationSheet(
                milestone: MilestoneItemResponse(
                    id: "preview-\(category)",
                    milestoneType: type,
                    milestoneName: name,
                    milestoneDate: "2000-12-25",
                    recurrence: "yearly",
                    budgetTier: "major_milestone",
                    daysUntil: daysUntil,
                    createdAt: "2026-07-04",
                    occasionCategory: category
                ),
                partnerName: "Jas",
                formattedDate: date,
                onGetRecommendations: {},
                onDismiss: {}
            )
        }
}

#Preview("Gift-forward — Christmas") {
    previewSheet(name: "Christmas", date: "Dec 25", category: "christmas")
}

#Preview("Shared occasion — Anniversary") {
    previewSheet(
        name: "Our Anniversary",
        date: "Jun 14",
        category: "anniversary",
        type: "anniversary",
        daysUntil: 7
    )
}

#Preview("Gesture — Big day") {
    previewSheet(
        name: "Jas's Big Presentation",
        date: "Mar 3",
        category: "big_day",
        type: "custom",
        daysUntil: 3
    )
}

#Preview("Spontaneous — Just because") {
    previewSheet(
        name: "Just Because",
        date: "",
        category: "just_because",
        type: "custom",
        daysUntil: nil
    )
}

#Preview("Unknown — legacy milestone") {
    previewSheet(
        name: "Our Christmas in July",
        date: "Jul 25",
        category: "default",
        type: "custom",
        daysUntil: nil
    )
}
#endif
