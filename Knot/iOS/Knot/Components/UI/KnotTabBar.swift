//
//  KnotTabBar.swift
//  Knot
//
//  Airbnb-style custom bottom tab bar. Replaces SwiftUI's `TabView` so the
//  visuals (filled-on-active SF Symbol icons, brand-pink active color,
//  notification dots, top hairline divider) are owned end-to-end.
//

import SwiftUI

/// Airbnb-style bottom navigation bar.
///
/// Generic over the selection ID so callers can use any `Hashable` tag type
/// (e.g. `MainTabView.AppTab`). Compose with `.safeAreaInset(edge: .bottom)`
/// on the parent so destination views' safe-area insets shrink correctly,
/// matching `TabView`'s default behavior.
struct KnotTabBar<ID: Hashable>: View {

    /// Single tab definition. `systemImage` is an SF Symbol name; the `.fill`
    /// variant is applied automatically when the tab is selected.
    struct Item: Identifiable {
        let id: ID
        let title: String
        let systemImage: String
        let hasNotification: Bool

        init(
            id: ID,
            title: String,
            systemImage: String,
            hasNotification: Bool = false
        ) {
            self.id = id
            self.title = title
            self.systemImage = systemImage
            self.hasNotification = hasNotification
        }
    }

    @Binding var selection: ID
    let items: [Item]

    init(selection: Binding<ID>, items: [Item]) {
        self._selection = selection
        self.items = items
    }

    var body: some View {
        VStack(spacing: 0) {
            Divider()
                .overlay(Theme.surfaceBorder)

            HStack(alignment: .center, spacing: 0) {
                ForEach(items) { item in
                    tabButton(for: item)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.top, Theme.Spacing.lg)
            .padding(.horizontal, Theme.Spacing.xs)
        }
        .frame(height: Theme.Spacing.xxxl)
        .background(Theme.backgroundBottom)
        .sensoryFeedback(.selection, trigger: selection)
    }

    @ViewBuilder
    private func tabButton(for item: Item) -> some View {
        let isSelected = item.id == selection

        Button {
            selection = item.id
        } label: {
            VStack(spacing: 2) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: item.systemImage)
                        .symbolVariant(isSelected ? .fill : .none)
                        .font(.system(size: 22, weight: .regular))
                        .frame(width: 24, height: 24)

                    if item.hasNotification {
                        Circle()
                            .fill(.red)
                            .frame(width: 8, height: 8)
                            .offset(x: 2, y: -2)
                    }
                }

                Text(item.title)
                    .knotFont(Theme.Typography.label)
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? Theme.accent : Theme.textTertiary)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .padding(.vertical, Theme.Spacing.xxs)
            .animation(Theme.Motion.quick, value: isSelected)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Preview

#if DEBUG
#Preview("KnotTabBar") {
    @Previewable @State var sel: Int = 0
    return ZStack(alignment: .bottom) {
        Theme.backgroundGradient.ignoresSafeArea()
        KnotTabBar(
            selection: $sel,
            items: [
                .init(id: 0, title: "For You", systemImage: "sparkles"),
                .init(id: 1, title: "Saved", systemImage: "bookmark"),
                .init(id: 2, title: "Profile", systemImage: "person.crop.circle"),
            ]
        )
    }
}
#endif
