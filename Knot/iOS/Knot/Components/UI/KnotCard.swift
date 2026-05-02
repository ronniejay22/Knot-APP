//
//  KnotCard.swift
//  Knot
//
//  shadcn-style card primitive — the rounded surface used as the base for
//  every elevated container in the app. Replaces the inline
//  `RoundedRectangle.fill(Theme.surface).overlay(stroke)` block that was
//  duplicated across most screens.
//

import SwiftUI

/// A surface container with adaptive fill, 1pt border, and rounded corners.
///
/// Used as the foundation for all elevated content: settings rows, recommendation
/// cards, timeline entries, etc. Higher-level domain cards (e.g.
/// `RecommendationCard`, `JustBecauseCard`) compose `KnotCard` rather than
/// rebuilding the chrome inline.
struct KnotCard<Content: View>: View {

    /// Visual variant. `default` is the standard surface; `elevated` uses a
    /// brighter fill to suggest a hovered/pressed state; `outlinedDashed`
    /// uses a dashed border for empty-state placeholders.
    enum Variant {
        case `default`
        case elevated
        case outlinedDashed
    }

    /// Internal padding token. `none` lets the caller manage padding for
    /// edge-to-edge content like hero images.
    enum Padding: CGFloat {
        case none = 0
        case sm = 8
        case md = 12
        case lg = 16
        case xl = 20
    }

    let variant: Variant
    let padding: Padding
    let radius: CGFloat
    @ViewBuilder var content: () -> Content

    init(
        variant: Variant = .default,
        padding: Padding = .lg,
        radius: CGFloat = Theme.Radius.lg,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.variant = variant
        self.padding = padding
        self.radius = radius
        self.content = content
    }

    var body: some View {
        content()
            .padding(padding.rawValue)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: radius)
                    .fill(fillColor)
            )
            .overlay(borderOverlay)
            .clipShape(RoundedRectangle(cornerRadius: radius))
    }

    private var fillColor: Color {
        switch variant {
        case .default, .outlinedDashed:
            return Theme.surface
        case .elevated:
            return Theme.surfaceElevated
        }
    }

    @ViewBuilder
    private var borderOverlay: some View {
        switch variant {
        case .default, .elevated:
            RoundedRectangle(cornerRadius: radius)
                .stroke(Theme.surfaceBorder, lineWidth: 1)
        case .outlinedDashed:
            RoundedRectangle(cornerRadius: radius)
                .strokeBorder(
                    Theme.surfaceBorder,
                    style: StrokeStyle(lineWidth: 1, dash: [4, 4])
                )
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("KnotCard variants") {
    ZStack {
        Theme.backgroundGradient.ignoresSafeArea()
        VStack(spacing: 16) {
            KnotCard {
                Text("Default card with default padding")
                    .foregroundStyle(Theme.textPrimary)
            }
            KnotCard(variant: .elevated) {
                Text("Elevated card")
                    .foregroundStyle(Theme.textPrimary)
            }
            KnotCard(variant: .outlinedDashed) {
                Text("Empty state placeholder")
                    .foregroundStyle(Theme.textSecondary)
            }
            KnotCard(padding: .none, radius: Theme.Radius.xl) {
                Color.pink.frame(height: 80)
            }
        }
        .padding()
    }
}
#endif
