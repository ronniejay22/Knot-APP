//
//  KnotIconButton.swift
//  Knot
//
//  Circular icon-only button for toolbars and inline controls.
//

import SwiftUI

/// A circular icon-only button. Use for toolbar buttons, inline controls,
/// and other compact actions where a label would be redundant.
struct KnotIconButton: View {

    enum Variant: CaseIterable {
        case primary    // pink fill, white icon — strong CTA
        case surface    // surface fill, accent icon — toolbar-style
        case ghost      // transparent, accent icon — minimal
    }

    enum Size: CaseIterable {
        case sm
        case md
        case lg

        var diameter: CGFloat {
            switch self {
            case .sm: return 32
            case .md: return 40
            case .lg: return 48
            }
        }

        var iconSize: CGFloat {
            switch self {
            case .sm: return 16
            case .md: return 20
            case .lg: return 24
            }
        }
    }

    let icon: KnotIcon
    let variant: Variant
    let size: Size
    let action: @MainActor () -> Void

    init(
        icon: KnotIcon,
        variant: Variant = .surface,
        size: Size = .md,
        action: @escaping @MainActor () -> Void
    ) {
        self.icon = icon
        self.variant = variant
        self.size = size
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            KnotIconView(icon, size: size.iconSize)
                .foregroundStyle(foregroundColor)
                .frame(width: size.diameter, height: size.diameter)
                .background(Circle().fill(backgroundColor))
                .overlay(
                    Circle().stroke(borderColor, lineWidth: variant == .surface ? 1 : 0)
                )
        }
        .buttonStyle(.plain)
    }

    private var backgroundColor: Color {
        switch variant {
        case .primary: return Theme.accent
        case .surface: return Theme.surface
        case .ghost: return .clear
        }
    }

    private var foregroundColor: Color {
        switch variant {
        case .primary: return .white
        case .surface, .ghost: return Theme.accent
        }
    }

    private var borderColor: Color {
        variant == .surface ? Theme.surfaceBorder : .clear
    }
}

// MARK: - Preview

#if DEBUG
#Preview("KnotIconButton variants") {
    ZStack {
        Theme.backgroundGradient.ignoresSafeArea()
        VStack(spacing: 24) {
            ForEach(Array(KnotIconButton.Variant.allCases.enumerated()), id: \.offset) { _, variant in
                HStack(spacing: 16) {
                    ForEach(Array(KnotIconButton.Size.allCases.enumerated()), id: \.offset) { _, size in
                        KnotIconButton(icon: .closeOutlined, variant: variant, size: size, action: {})
                    }
                }
            }
        }
    }
}
#endif
