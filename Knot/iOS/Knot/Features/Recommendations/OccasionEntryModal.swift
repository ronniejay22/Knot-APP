//
//  OccasionEntryModal.swift
//  Knot
//
//  The card shown between tapping a milestone push notification and seeing the
//  recommendations. Gives the moment its own beat: an illustration, copy written
//  for that specific occasion, and a single CTA through to the picks.
//
//  Design: Figma "Entry Modals" (node 608:4358). Layout mechanics follow the
//  established centered-dialog pattern from `RelationshipLengthModal` and
//  `MilestoneDateModal` — fullScreenCover with a cleared presentation
//  background so the card can draw its own dimmed backdrop and run its own
//  scale/fade instead of the cover's bottom-slide.
//

import SwiftUI
import LucideIcons

struct OccasionEntryModal: View {
    let copy: OccasionCopy
    let onContinue: @MainActor () -> Void
    let onClose: @MainActor () -> Void

    @State private var appeared = false

    // Matched to `RelationshipLengthModal` so every centered dialog in the app
    // enters and leaves the same way.
    private let appearAnimation: Animation = .spring(response: 0.4, dampingFraction: 0.86)
    private let dismissAnimation: Animation = .easeIn(duration: 0.2)
    private let dismissDuration: Duration = .seconds(0.2)

    /// 350x160 in the comp — exactly 35:16.
    private let illustrationAspectRatio: CGFloat = 350.0 / 160.0

    /// How much of the blurred layer to show. `.ultraThinMaterial` is already
    /// the least opaque material SwiftUI offers, and materials expose no blur
    /// radius, so softening the backdrop means blending the blurred layer with
    /// the sharp one rather than reaching for a thinner material.
    ///
    /// The dim is applied separately at full strength — it is what keeps the
    /// card legible, and dropping it along with the blur would leave the white
    /// card floating on bright content.
    private let backdropBlurOpacity: Double = 0.5

    var body: some View {
        ZStack {
            backdrop
                .ignoresSafeArea()
                .opacity(appeared ? 1 : 0)
                .onTapGesture { animateOut(then: onClose) }

            card
                .frame(maxWidth: 390)
                .padding(.horizontal, 24)
                .shadow(Theme.Shadow.lg)
                .scaleEffect(appeared ? 1 : 0.94)
                .opacity(appeared ? 1 : 0)
        }
        .onAppear {
            // Deferred a runloop tick so the animation runs from the collapsed
            // state instead of being coalesced into first render.
            Task { @MainActor in
                await Task.yield()
                withAnimation(appearAnimation) { appeared = true }
            }
        }
    }

    // MARK: - Backdrop

    /// Softened blur plus a full-strength dim. The two are separate layers so
    /// the blur can be dialled back without also lightening the dim.
    private var backdrop: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(backdropBlurOpacity)
            Theme.overlayDim
        }
    }

    // MARK: - Card

    private var card: some View {
        KnotCard(
            variant: .elevated,
            padding: .xl,
            radius: Theme.Radius.md
        ) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxl) {
                header

                if let illustrationName = copy.illustrationName {
                    illustration(illustrationName)
                }

                bottomSection
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            Text(copy.title)
                .knotFont(Theme.Typography.modalTitle)
                .foregroundStyle(Theme.colorTertiary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            // A plain Button rather than `KnotIconButton(.ghost)`: that variant
            // paints `Theme.accent`, and the comp specifies a muted glyph
            // (`action/active`). A pink X reads as an action; this one dismisses.
            // Matches the toolbar X in `MilestoneRecommendationsCoverView`.
            Button {
                animateOut(then: onClose)
            } label: {
                Image(uiImage: Lucide.x)
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 20, height: 20)
                    .foregroundStyle(Theme.textSecondary)
                    // Keeps the tap target at 44pt without widening the layout.
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
    }

    private func illustration(_ name: String) -> some View {
        Color.clear
            .aspectRatio(illustrationAspectRatio, contentMode: .fit)
            .overlay {
                Image(name)
                    .resizable()
                    .scaledToFill()
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
            .accessibilityHidden(true)
    }

    private var bottomSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            Text(copy.body)
                .knotFont(Theme.Typography.bodySmall)
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            KnotButton(
                copy.ctaLabel,
                variant: .primary,
                size: .md
            ) {
                animateOut(then: onContinue)
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Dismissal

    /// Animates the card and backdrop out, then hands back to the parent, which
    /// tears down the cover without animation.
    private func animateOut(then action: @escaping @MainActor () -> Void) {
        withAnimation(dismissAnimation) { appeared = false }
        Task { @MainActor in
            try? await Task.sleep(for: dismissDuration)
            action()
        }
    }
}

#if DEBUG
#Preview("Birthday") {
    OccasionEntryModal(
        copy: OccasionCopy.resolve(
            category: "birthday",
            partnerName: "Jerry",
            daysUntil: 3,
            milestoneName: "Jerry's Birthday"
        ),
        onContinue: {},
        onClose: {}
    )
}

#Preview("Rough patch — softer voice") {
    OccasionEntryModal(
        copy: OccasionCopy.resolve(
            category: "thinking_of_you",
            partnerName: "Alex",
            daysUntil: nil,
            milestoneName: nil
        ),
        onContinue: {},
        onClose: {}
    )
}

#Preview("Fallback — no illustration") {
    OccasionEntryModal(
        copy: OccasionCopy.resolve(
            category: "default",
            partnerName: "Sam",
            daysUntil: 7,
            milestoneName: "First Date"
        ),
        onContinue: {},
        onClose: {}
    )
}
#endif
