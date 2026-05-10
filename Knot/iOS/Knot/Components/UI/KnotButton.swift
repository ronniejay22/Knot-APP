//
//  KnotButton.swift
//  Knot
//
//  shadcn-style primary button primitive. Replaces hand-rolled
//  `Capsule().fill(Theme.accent)` CTAs throughout the app.
//

import SwiftUI

/// A styled button with shadcn-flavored variants and sizes.
///
/// The visual treatment is owned by `KnotButton` — callers do not pass colors,
/// borders, or shapes. They pick a `Variant` and `Size` and provide a label.
struct KnotButton<Label: View>: View {

    enum Variant: CaseIterable {
        case primary       // pink fill, white text — main CTAs
        case secondary     // muted surface fill, primary text
        case outline       // transparent fill, accent text, accent border
        case ghost         // transparent, no border, accent text
        case destructive   // red fill, white text
    }

    enum Size: CaseIterable {
        case sm
        case md
        case lg

        var height: CGFloat {
            switch self {
            case .sm: return 32
            case .md: return 40
            case .lg: return 54
            }
        }

        var horizontalPadding: CGFloat {
            switch self {
            case .sm: return 12
            case .md: return 16
            case .lg: return 20
            }
        }

        var font: Font {
            switch self {
            case .sm: return .caption.weight(.semibold)
            case .md: return .subheadline.weight(.semibold)
            case .lg: return .body.weight(.semibold)
            }
        }

        var iconSize: CGFloat {
            switch self {
            case .sm: return 14
            case .md: return 16
            case .lg: return 18
            }
        }
    }

    enum Shape {
        case rounded
        case pill
    }

    let variant: Variant
    let size: Size
    let shape: Shape
    let isLoading: Bool
    let leadingIcon: UIImage?
    let trailingIcon: UIImage?
    let action: @MainActor () -> Void
    @ViewBuilder var label: () -> Label

    init(
        _ variant: Variant = .primary,
        size: Size = .md,
        shape: Shape = .rounded,
        isLoading: Bool = false,
        leadingIcon: UIImage? = nil,
        trailingIcon: UIImage? = nil,
        action: @escaping @MainActor () -> Void,
        @ViewBuilder label: @escaping () -> Label
    ) {
        self.variant = variant
        self.size = size
        self.shape = shape
        self.isLoading = isLoading
        self.leadingIcon = leadingIcon
        self.trailingIcon = trailingIcon
        self.action = action
        self.label = label
    }

    var body: some View {
        Button(action: action) {
            content
                .frame(maxWidth: .infinity)
                .frame(height: size.height)
                .padding(.horizontal, size.horizontalPadding)
                .background(background)
                .overlay(borderOverlay)
                .clipShape(clipShape)
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            ProgressView()
                .tint(foregroundColor)
        } else {
            HStack(spacing: 6) {
                if let leadingIcon {
                    icon(leadingIcon)
                }
                label()
                    .font(size.font)
                    .foregroundStyle(foregroundColor)
                    .lineLimit(1)
                if let trailingIcon {
                    icon(trailingIcon)
                }
            }
        }
    }

    private func icon(_ image: UIImage) -> some View {
        Image(uiImage: image)
            .renderingMode(.template)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: size.iconSize, height: size.iconSize)
            .foregroundStyle(foregroundColor)
    }

    @ViewBuilder
    private var background: some View {
        switch shape {
        case .rounded:
            RoundedRectangle(cornerRadius: Theme.Radius.md).fill(backgroundColor)
        case .pill:
            Capsule().fill(backgroundColor)
        }
    }

    @ViewBuilder
    private var borderOverlay: some View {
        if variant == .outline {
            switch shape {
            case .rounded:
                RoundedRectangle(cornerRadius: Theme.Radius.md)
                    .stroke(Theme.accent, lineWidth: 1)
            case .pill:
                Capsule().stroke(Theme.accent, lineWidth: 1)
            }
        }
    }

    private var clipShape: AnyShape {
        switch shape {
        case .rounded:
            return AnyShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
        case .pill:
            return AnyShape(Capsule())
        }
    }

    // MARK: - Variant Colors

    private var backgroundColor: Color {
        switch variant {
        case .primary: return Theme.accent
        case .secondary: return Theme.surfaceElevated
        case .outline, .ghost: return .clear
        case .destructive: return Theme.statusError
        }
    }

    private var foregroundColor: Color {
        switch variant {
        case .primary, .destructive: return .white
        case .secondary: return Theme.textPrimary
        case .outline, .ghost: return Theme.accent
        }
    }
}

// MARK: - Convenience initializer for plain text buttons

extension KnotButton where Label == Text {
    init(
        _ title: String,
        variant: Variant = .primary,
        size: Size = .md,
        shape: Shape = .rounded,
        isLoading: Bool = false,
        leadingIcon: UIImage? = nil,
        trailingIcon: UIImage? = nil,
        action: @escaping @MainActor () -> Void
    ) {
        self.init(
            variant,
            size: size,
            shape: shape,
            isLoading: isLoading,
            leadingIcon: leadingIcon,
            trailingIcon: trailingIcon,
            action: action,
            label: { Text(title) }
        )
    }
}

// MARK: - Preview

#if DEBUG
import LucideIcons

#Preview("KnotButton variants") {
    ZStack {
        Theme.backgroundGradient.ignoresSafeArea()
        ScrollView {
            VStack(spacing: 16) {
                ForEach(Array(KnotButton<Text>.Variant.allCases.enumerated()), id: \.offset) { _, variant in
                    KnotButton("\(String(describing: variant).capitalized) action",
                               variant: variant,
                               leadingIcon: Lucide.sparkles,
                               action: {})
                }

                KnotButton("Loading", isLoading: true, action: {})

                KnotButton("Pill shape", shape: .pill, action: {})
            }
            .padding()
        }
    }
}
#endif
