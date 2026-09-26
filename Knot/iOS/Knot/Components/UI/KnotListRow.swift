//
//  KnotListRow.swift
//  Knot
//
//  Row primitive used in Settings, Notifications, Edit Vault, etc. Folds in
//  the three private helpers (`settingsRow`, `settingsInfoRow`,
//  `settingsToggleRow`) that screens previously rebuilt by hand.
//

import SwiftUI

/// How a `KnotListRow` draws its own chrome. Read from the environment, so a
/// container (`KnotListGroup`) can restyle every row inside it at once.
enum KnotListRowStyle {
    /// A self-contained bordered card per row — the default.
    case standalone
    /// A bare row inside a `KnotListGroup`, which owns the surface, border,
    /// and dividers. The icon sits in a tinted tile.
    case grouped
}

/// Row measurements shared with `KnotListDivider`, so a divider's inset lines
/// up with a grouped row's title.
enum KnotListRowMetrics {
    static let horizontalPadding: CGFloat = 16
    static let standaloneVerticalPadding: CGFloat = 14
    static let groupedVerticalPadding: CGFloat = 12
    static let iconSpacing: CGFloat = 14
    static let iconSize: CGFloat = 20
    /// Side of the grouped style's tinted icon tile.
    static let tileSize: CGFloat = 32
    /// Where a grouped row's title begins, so dividers start under the text
    /// rather than under the icon tile.
    static let dividerLeadingInset: CGFloat = horizontalPadding + tileSize + iconSpacing
}

private struct KnotListRowStyleKey: EnvironmentKey {
    static let defaultValue: KnotListRowStyle = .standalone
}

extension EnvironmentValues {
    var knotListRowStyle: KnotListRowStyle {
        get { self[KnotListRowStyleKey.self] }
        set { self[KnotListRowStyleKey.self] = newValue }
    }
}

extension View {
    /// Sets the chrome style for every `KnotListRow` in this view.
    func knotListRowStyle(_ style: KnotListRowStyle) -> some View {
        environment(\.knotListRowStyle, style)
    }
}

/// A row with a leading icon, title, optional subtitle, and a configurable
/// trailing accessory (chevron, value, toggle, custom view).
///
/// In the default `.standalone` style it renders the same surface chrome as
/// `KnotCard(.default)` (matching fill, border, and `Theme.Radius.md` corner)
/// inline so the row remains a single hit target for the optional `action`.
/// Inside a `KnotListGroup` it switches to `.grouped`: no chrome of its own,
/// and the icon sits in a tinted tile. Use the `chevron` / `info` /
/// `toggle` / `action` static factories for the common shapes.
struct KnotListRow<Trailing: View>: View {

    let icon: KnotIcon
    let title: String
    let subtitle: String?
    let action: (@MainActor () -> Void)?
    @ViewBuilder var trailing: () -> Trailing

    @Environment(\.knotListRowStyle) private var style

    init(
        icon: KnotIcon,
        title: String,
        subtitle: String? = nil,
        action: (@MainActor () -> Void)? = nil,
        @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }
    ) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.action = action
        self.trailing = trailing
    }

    var body: some View {
        if let action {
            Button(action: action) { rowContent }
                .buttonStyle(.plain)
        } else if style == .grouped {
            // A grouped row with no action (info, toggle) reads as one element
            // — "Email, you@example.com" — rather than a label and a stray value.
            rowContent
                .accessibilityElement(children: .combine)
        } else {
            rowContent
        }
    }

    @ViewBuilder
    private var rowContent: some View {
        switch style {
        case .standalone: standaloneContent
        case .grouped: groupedContent
        }
    }

    private var standaloneContent: some View {
        HStack(spacing: KnotListRowMetrics.iconSpacing) {
            KnotIconView(icon, size: KnotListRowMetrics.iconSize)
                .foregroundStyle(Theme.accent)

            titleStack

            Spacer()

            trailing()
        }
        .padding(.horizontal, KnotListRowMetrics.horizontalPadding)
        .padding(.vertical, KnotListRowMetrics.standaloneVerticalPadding)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md)
                .stroke(Theme.surfaceBorder, lineWidth: 1)
        )
    }

    private var groupedContent: some View {
        HStack(spacing: KnotListRowMetrics.iconSpacing) {
            KnotIconView(icon, size: KnotListRowMetrics.iconSize)
                .foregroundStyle(Theme.accent)
                .frame(width: KnotListRowMetrics.tileSize, height: KnotListRowMetrics.tileSize)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.sm)
                        .fill(Theme.accentTint)
                )

            // The title keeps its width ahead of a long trailing value (an
            // email address), which truncates instead.
            titleStack
                .layoutPriority(1)

            Spacer(minLength: 0)

            trailing()
        }
        .padding(.horizontal, KnotListRowMetrics.horizontalPadding)
        .padding(.vertical, KnotListRowMetrics.groupedVerticalPadding)
        // The whole row is the hit target, not just its text and icon.
        .contentShape(Rectangle())
    }

    private var titleStack: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .knotFont(Theme.Typography.cta)
                .foregroundStyle(Theme.textPrimary)
            if let subtitle {
                Text(subtitle)
                    .knotFont(Theme.Typography.label)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
        }
    }
}

// MARK: - Convenience Factories

extension KnotListRow where Trailing == _ChevronAccessory {
    /// A tappable row with a chevron on the right.
    static func chevron(
        icon: KnotIcon,
        title: String,
        subtitle: String? = nil,
        action: @escaping @MainActor () -> Void
    ) -> KnotListRow<_ChevronAccessory> {
        KnotListRow<_ChevronAccessory>(
            icon: icon,
            title: title,
            subtitle: subtitle,
            action: action,
            trailing: { _ChevronAccessory() }
        )
    }
}

extension KnotListRow where Trailing == _InfoValueAccessory {
    /// A non-tappable row with a trailing value (e.g. version, email).
    static func info(
        icon: KnotIcon,
        title: String,
        value: String
    ) -> KnotListRow<_InfoValueAccessory> {
        KnotListRow<_InfoValueAccessory>(
            icon: icon,
            title: title,
            subtitle: nil,
            action: nil,
            trailing: { _InfoValueAccessory(value: value) }
        )
    }
}

extension KnotListRow where Trailing == _ToggleAccessory {
    /// A non-tappable row with a trailing toggle.
    static func toggle(
        icon: KnotIcon,
        title: String,
        subtitle: String? = nil,
        isOn: Binding<Bool>
    ) -> KnotListRow<_ToggleAccessory> {
        KnotListRow<_ToggleAccessory>(
            icon: icon,
            title: title,
            subtitle: subtitle,
            action: nil,
            trailing: { _ToggleAccessory(isOn: isOn) }
        )
    }
}

extension KnotListRow where Trailing == _ActionLabelAccessory {
    /// A tappable row with no chevron — for terminal actions like Sign Out.
    static func action(
        icon: KnotIcon,
        title: String,
        subtitle: String? = nil,
        action: @escaping @MainActor () -> Void
    ) -> KnotListRow<_ActionLabelAccessory> {
        KnotListRow<_ActionLabelAccessory>(
            icon: icon,
            title: title,
            subtitle: subtitle,
            action: action,
            trailing: { _ActionLabelAccessory() }
        )
    }
}

// MARK: - Internal Accessory Views

struct _ChevronAccessory: View {
    var body: some View {
        KnotIconView(.chevronRightOutlined, size: 16)
            .foregroundStyle(Theme.textTertiary)
    }
}

struct _InfoValueAccessory: View {
    let value: String

    var body: some View {
        Text(value)
            .knotFont(Theme.Typography.body)
            .foregroundStyle(Theme.textSecondary)
            .lineLimit(1)
    }
}

struct _ToggleAccessory: View {
    @Binding var isOn: Bool

    var body: some View {
        Toggle("", isOn: $isOn)
            .tint(Theme.accent)
            .labelsHidden()
    }
}

struct _ActionLabelAccessory: View {
    var body: some View { EmptyView() }
}

// MARK: - Preview

#if DEBUG
#Preview("KnotListRow factories") {
    ZStack {
        Theme.backgroundGradient.ignoresSafeArea()
        VStack(spacing: 10) {
            KnotListRow.chevron(
                icon: .editOutlined,
                title: "Edit Profile",
                subtitle: "Update partner details and preferences",
                action: {}
            )
            KnotListRow.info(
                icon: .mailOutlined,
                title: "Email",
                value: "user@example.com"
            )
            KnotListRow.toggle(
                icon: .notificationsActiveOutlined,
                title: "Enable Notifications",
                isOn: .constant(true)
            )
            KnotListRow.action(
                icon: .logoutOutlined,
                title: "Sign Out",
                action: {}
            )
        }
        .padding()
    }
}
#endif
