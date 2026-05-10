//
//  KnotSectionHeader.swift
//  Knot
//
//  Section header with optional icon and trailing action. Standardizes the
//  "icon + bold label" and "uppercase caption" header patterns repeated
//  across screens.
//

import SwiftUI

/// A section header with two visual styles:
/// - `.caption` — uppercase tertiary text (Settings-style)
/// - `.subhead` — semibold primary text with optional icon (Home/ForYou-style)
struct KnotSectionHeader<Trailing: View>: View {

    enum Style {
        case caption
        case subhead
    }

    let title: String
    let icon: UIImage?
    let style: Style
    @ViewBuilder var trailing: () -> Trailing

    init(
        _ title: String,
        icon: UIImage? = nil,
        style: Style = .subhead,
        @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }
    ) {
        self.title = title
        self.icon = icon
        self.style = style
        self.trailing = trailing
    }

    var body: some View {
        HStack(spacing: 8) {
            if let icon, style == .subhead {
                Image(uiImage: icon)
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 18, height: 18)
                    .foregroundStyle(Theme.accent)
            }

            Text(displayTitle)
                .font(font)
                .foregroundStyle(textColor)

            Spacer()

            trailing()
        }
        .padding(.horizontal, style == .caption ? 4 : 0)
    }

    private var displayTitle: String {
        style == .caption ? title.uppercased() : title
    }

    private var font: Font {
        switch style {
        case .caption: return Theme.Typography.label
        case .subhead: return Theme.Typography.cta
        }
    }

    private var textColor: Color {
        switch style {
        case .caption: return Theme.textTertiary
        case .subhead: return Theme.textPrimary
        }
    }
}

// MARK: - Preview

#if DEBUG
import LucideIcons

#Preview("KnotSectionHeader styles") {
    ZStack {
        Theme.backgroundGradient.ignoresSafeArea()
        VStack(alignment: .leading, spacing: 24) {
            KnotSectionHeader("Account", style: .caption)
            KnotSectionHeader("Recent Hints", icon: Lucide.lightbulb)
            KnotSectionHeader("Upcoming") {
                Text("View All")
                    .knotFont(Theme.Typography.label)
                    .foregroundStyle(Theme.accent)
            }
        }
        .padding()
    }
}
#endif
