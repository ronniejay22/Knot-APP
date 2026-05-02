//
//  KnotBadge.swift
//  Knot
//
//  Badge + selectable Chip primitives. Replaces vibe pills, type badges,
//  countdown chips, and the private `MatchingFactorChip` pattern.
//

import SwiftUI

/// A small pill-shaped label with semantic color variants.
struct KnotBadge<Label: View>: View {

    enum Variant: CaseIterable {
        case `default`     // muted surface fill
        case secondary     // elevated surface fill
        case outline       // transparent with border
        case accent        // tinted accent (10% pink)
        case destructive   // tinted red
        case success       // tinted green
    }

    enum Size: CaseIterable {
        case sm
        case md

        var verticalPadding: CGFloat {
            switch self {
            case .sm: return 3
            case .md: return 5
            }
        }

        var horizontalPadding: CGFloat {
            switch self {
            case .sm: return 8
            case .md: return 10
            }
        }

        var font: Font {
            switch self {
            case .sm: return .caption2.weight(.semibold)
            case .md: return .caption.weight(.semibold)
            }
        }

        var iconSize: CGFloat {
            switch self {
            case .sm: return 11
            case .md: return 13
            }
        }
    }

    let variant: Variant
    let size: Size
    let leadingIcon: UIImage?
    @ViewBuilder var label: () -> Label

    init(
        variant: Variant = .default,
        size: Size = .sm,
        leadingIcon: UIImage? = nil,
        @ViewBuilder label: @escaping () -> Label
    ) {
        self.variant = variant
        self.size = size
        self.leadingIcon = leadingIcon
        self.label = label
    }

    var body: some View {
        HStack(spacing: 4) {
            if let leadingIcon {
                Image(uiImage: leadingIcon)
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size.iconSize, height: size.iconSize)
                    .foregroundStyle(foregroundColor)
            }
            label()
                .font(size.font)
                .foregroundStyle(foregroundColor)
        }
        .padding(.horizontal, size.horizontalPadding)
        .padding(.vertical, size.verticalPadding)
        .background(Capsule().fill(backgroundColor))
        .overlay(
            Capsule().stroke(borderColor, lineWidth: variant == .outline ? 1 : 0)
        )
    }

    private var backgroundColor: Color {
        switch variant {
        case .default: return Theme.surface
        case .secondary: return Theme.surfaceElevated
        case .outline: return .clear
        case .accent: return Theme.accent.opacity(0.12)
        case .destructive: return Color.red.opacity(0.12)
        case .success: return Color.green.opacity(0.12)
        }
    }

    private var foregroundColor: Color {
        switch variant {
        case .default, .secondary, .outline: return Theme.textSecondary
        case .accent: return Theme.accent
        case .destructive: return .red
        case .success: return .green
        }
    }

    private var borderColor: Color {
        Theme.surfaceBorder
    }
}

// MARK: - Convenience text initializer

extension KnotBadge where Label == Text {
    init(
        _ text: String,
        variant: Variant = .default,
        size: Size = .sm,
        leadingIcon: UIImage? = nil
    ) {
        self.init(
            variant: variant,
            size: size,
            leadingIcon: leadingIcon,
            label: { Text(text) }
        )
    }
}

// MARK: - Selectable Chip

/// A tappable, optionally-selected chip used for multi-select pickers and
/// filter pills. Composes the same pill chrome as `KnotBadge` but adds
/// pressed and selected states.
struct KnotChip: View {

    let title: String
    let icon: UIImage?
    let isSelected: Bool
    let action: @MainActor () -> Void

    init(
        title: String,
        icon: UIImage? = nil,
        isSelected: Bool,
        action: @escaping @MainActor () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.isSelected = isSelected
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon {
                    Image(uiImage: icon)
                        .renderingMode(.template)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 13, height: 13)
                        .foregroundStyle(foregroundColor)
                }
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(foregroundColor)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Capsule().fill(backgroundColor))
            .overlay(Capsule().stroke(borderColor, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var backgroundColor: Color {
        isSelected ? Theme.accent.opacity(0.14) : Theme.surface
    }

    private var foregroundColor: Color {
        isSelected ? Theme.accent : Theme.textPrimary
    }

    private var borderColor: Color {
        isSelected ? Theme.accent.opacity(0.4) : Theme.surfaceBorder
    }
}

// MARK: - Preview

#if DEBUG
import LucideIcons

#Preview("KnotBadge") {
    ZStack {
        Theme.backgroundGradient.ignoresSafeArea()
        VStack(spacing: 16) {
            ForEach(Array(KnotBadge<Text>.Variant.allCases.enumerated()), id: \.offset) { _, v in
                KnotBadge(String(describing: v).capitalized, variant: v, size: .md, leadingIcon: Lucide.sparkles)
            }
        }
    }
}

#Preview("KnotChip") {
    ZStack {
        Theme.backgroundGradient.ignoresSafeArea()
        HStack(spacing: 10) {
            KnotChip(title: "Selected", isSelected: true, action: {})
            KnotChip(title: "Unselected", isSelected: false, action: {})
        }
    }
}
#endif
