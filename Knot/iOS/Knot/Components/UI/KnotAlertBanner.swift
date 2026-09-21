//
//  KnotAlertBanner.swift
//  Knot
//
//  An in-content alert: an accent-tinted card with an icon, a title, an
//  optional dismiss control, a one- or two-line message, and a single
//  full-width primary action. It is the loud sibling of the "Knot's Take"
//  briefing card — same anatomy (icon · title · ✕ / body), but tinted and
//  carrying a CTA — for the moments where the screen has to tell the user
//  something *before* they look at the content, and give them one obvious
//  thing to do about it.
//
//  Not a system `.alert`: those are reserved for errors and destructive
//  confirmations, and they interrupt. This sits in the scroll and can be
//  dismissed or ignored.
//

import SwiftUI
import LucideIcons

/// Accent-tinted alert card with one primary action.
///
/// Used by `RecommendationsView` above the feed when a stored batch was
/// resumed ("Picking up where you left off" → "Find new picks"). Compose it
/// for any other "here's the situation, here's the one thing to do" notice
/// rather than rebuilding the tint and layout inline.
struct KnotAlertBanner: View {

    let icon: UIImage
    let title: String
    let message: String
    let actionTitle: String
    let action: @MainActor () -> Void
    /// When set, a ✕ is shown in the header and calls this on tap. `nil`
    /// hides the control for a notice the user must act on.
    let onDismiss: (@MainActor () -> Void)?

    init(
        icon: UIImage,
        title: String,
        message: String,
        actionTitle: String,
        action: @escaping @MainActor () -> Void,
        onDismiss: (@MainActor () -> Void)? = nil
    ) {
        self.icon = icon
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
        self.onDismiss = onDismiss
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(spacing: 10) {
                Image(uiImage: icon)
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 18, height: 18)
                    .foregroundStyle(Theme.accent)

                Text(title)
                    .knotFont(Theme.Typography.cta)
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)

                if let onDismiss {
                    Button {
                        onDismiss()
                    } label: {
                        Image(uiImage: Lucide.x)
                            .renderingMode(.template)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 14, height: 14)
                            .foregroundStyle(Theme.textTertiary)
                            // A 14pt glyph is too small a target on its own.
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Dismiss")
                }
            }

            Text(message)
                .knotFont(Theme.Typography.body)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            KnotButton(actionTitle, variant: .primary, size: .md, action: action)
        }
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Tint over the surface, not over the page gradient, so the card reads
        // the same wherever it sits — the `EditMilestonesSheet` selected-chip
        // recipe (`accent.opacity(0.12)` on `surface`).
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.lg)
                .fill(Theme.accent.opacity(0.12))
        )
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.lg)
                .fill(Theme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.lg)
                .stroke(Theme.accent.opacity(0.4), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg))
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Preview

#if DEBUG
#Preview("KnotAlertBanner") {
    ZStack {
        Theme.backgroundGradient.ignoresSafeArea()
        VStack(spacing: 16) {
            KnotAlertBanner(
                icon: Lucide.history,
                title: "Picking up where you left off",
                message: "These are the picks we found for Jas 2 days ago. Want a fresh set?",
                actionTitle: "Find new picks",
                action: {},
                onDismiss: {}
            )
            KnotAlertBanner(
                icon: Lucide.history,
                title: "No dismiss control",
                message: "A notice the user has to act on.",
                actionTitle: "Continue",
                action: {}
            )
        }
        .padding()
    }
}
#endif
