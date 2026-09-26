//
//  KnotTabBar.swift
//  Knot
//
//  Airbnb-style custom bottom tab bar. Replaces SwiftUI's `TabView` so the
//  visuals (outlined → filled MUI icons on the active tab, brand-pink active
//  color, notification dots, top hairline divider) are owned end-to-end.
//

import SwiftUI

/// Airbnb-style bottom navigation bar.
///
/// Generic over the selection ID so callers can use any `Hashable` tag type
/// (e.g. `MainTabView.AppTab`). Compose with `.safeAreaInset(edge: .bottom)`
/// on the parent so destination views' safe-area insets shrink correctly,
/// matching `TabView`'s default behavior.
struct KnotTabBar<ID: Hashable>: View {

    /// Single tab definition. `icon` is drawn while the tab is unselected
    /// (the Outlined MUI glyph) and `selectedIcon` while it is selected (the
    /// Filled one) — MUI has no automatic fill variant, so the pair is explicit.
    struct Item: Identifiable {
        let id: ID
        let title: String
        let icon: KnotIcon
        let selectedIcon: KnotIcon
        let hasNotification: Bool

        init(
            id: ID,
            title: String,
            icon: KnotIcon,
            selectedIcon: KnotIcon,
            hasNotification: Bool = false
        ) {
            self.id = id
            self.title = title
            self.icon = icon
            self.selectedIcon = selectedIcon
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
                    KnotIconView(isSelected ? item.selectedIcon : item.icon, size: 24)

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
                .init(id: 0, title: "Home", icon: .homeOutlined, selectedIcon: .home),
                .init(id: 1, title: "Saved", icon: .bookmarkBorder, selectedIcon: .bookmark),
                .init(id: 2, title: "Profile", icon: .accountCircleOutlined, selectedIcon: .accountCircle),
            ]
        )
    }
}
#endif
