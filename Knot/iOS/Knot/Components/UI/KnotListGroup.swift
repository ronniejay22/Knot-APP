//
//  KnotListGroup.swift
//  Knot
//
//  Groups `KnotListRow`s into one rounded card with inset dividers — the
//  iOS-Settings-style grouped list — instead of a stack of separately
//  bordered rows.
//

import SwiftUI

/// A titled card holding a run of `KnotListRow`s.
///
/// The group draws the surface and border once (via `KnotCard`) and switches
/// every row inside it to the `.grouped` style. Place a `KnotListDivider()`
/// between rows — iOS 17 has no public API for a container to interleave its
/// children, so dividers are explicit.
///
/// Attach sheets, alerts, and covers outside the group: a presentation
/// attached inside inherits the `.grouped` row style.
struct KnotListGroup<Content: View>: View {

    let title: String?
    @ViewBuilder var content: () -> Content

    init(_ title: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            if let title {
                KnotSectionHeader<EmptyView>(title, style: .caption)
                    .accessibilityAddTraits(.isHeader)
            }

            KnotCard(padding: .none) {
                VStack(spacing: 0) {
                    content()
                }
            }
            .knotListRowStyle(.grouped)
        }
    }
}

/// The hairline between two rows of a `KnotListGroup`, inset so it starts
/// under the row titles rather than under the icon tiles.
struct KnotListDivider: View {
    var body: some View {
        Divider()
            .overlay(Theme.surfaceBorder)
            .padding(.leading, KnotListRowMetrics.dividerLeadingInset)
    }
}

// MARK: - Preview

#if DEBUG
#Preview("KnotListGroup") {
    ZStack {
        Theme.backgroundGradient.ignoresSafeArea()
        VStack(spacing: 24) {
            KnotListGroup("Partner") {
                KnotListRow.chevron(icon: .favoriteBorder, title: "Partner profile", action: {})
                KnotListDivider()
                KnotListRow.chevron(icon: .eventOutlined, title: "Milestones", action: {})
            }
            KnotListGroup("Account") {
                KnotListRow.info(icon: .mailOutlined, title: "Email", value: "you@example.com")
            }
        }
        .padding()
    }
}
#endif
