//
//  KnotListRow.swift
//  Knot
//
//  Row primitive used in Settings, Notifications, Edit Vault, etc. Folds in
//  the three private helpers (`settingsRow`, `settingsInfoRow`,
//  `settingsToggleRow`) that screens previously rebuilt by hand.
//

import SwiftUI
import LucideIcons

/// A row with a leading icon, title, optional subtitle, and a configurable
/// trailing accessory (chevron, value, toggle, custom view).
///
/// Renders the same surface chrome as `KnotCard(.default)` (matching fill,
/// border, and `Theme.Radius.md` corner) inline so the row remains a single
/// hit target for the optional `action`. Use the `chevron` / `info` /
/// `toggle` / `action` static factories for the common shapes.
struct KnotListRow<Trailing: View>: View {

    let icon: UIImage
    let title: String
    let subtitle: String?
    let action: (@MainActor () -> Void)?
    @ViewBuilder var trailing: () -> Trailing

    init(
        icon: UIImage,
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
        } else {
            rowContent
        }
    }

    private var rowContent: some View {
        HStack(spacing: 14) {
            Image(uiImage: icon)
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 20, height: 20)
                .foregroundStyle(Theme.accent)

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

            Spacer()

            trailing()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md)
                .stroke(Theme.surfaceBorder, lineWidth: 1)
        )
    }
}

// MARK: - Convenience Factories

extension KnotListRow where Trailing == _ChevronAccessory {
    /// A tappable row with a chevron on the right.
    static func chevron(
        icon: UIImage,
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
        icon: UIImage,
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
        icon: UIImage,
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
        icon: UIImage,
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
        Image(uiImage: Lucide.chevronRight)
            .renderingMode(.template)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 16, height: 16)
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
                icon: Lucide.userPen,
                title: "Edit Profile",
                subtitle: "Update partner details and preferences",
                action: {}
            )
            KnotListRow.info(
                icon: Lucide.mail,
                title: "Email",
                value: "user@example.com"
            )
            KnotListRow.toggle(
                icon: Lucide.bellRing,
                title: "Enable Notifications",
                isOn: .constant(true)
            )
            KnotListRow.action(
                icon: Lucide.logOut,
                title: "Sign Out",
                action: {}
            )
        }
        .padding()
    }
}
#endif
