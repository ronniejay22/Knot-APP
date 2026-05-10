//
//  Theme.swift
//  Knot
//
//  Created on February 7, 2026.
//  Step 3.3: App-wide design system — adaptive light/dark theme.
//

import SwiftUI
import UIKit

/// Knot's centralized design system. All colors, gradients, and visual constants
/// live here so every screen shares the same aesthetic.
///
/// Colors are backed by `UIColor { traitCollection in ... }` so they automatically
/// resolve to the correct light/dark variant when `.preferredColorScheme()` changes
/// at the app root. No `@Environment(\.colorScheme)` injection is needed in views.
///
/// Use `Theme` colors for backgrounds, surfaces, and text. The accent color (pink)
/// works well in both modes.
enum Theme {

    // MARK: - Background Gradient

    /// Top color of the app-wide background gradient.
    static let backgroundTop = Color(UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor(red: 0.10, green: 0.05, blue: 0.16, alpha: 1.0)
            : UIColor(red: 0.97, green: 0.97, blue: 0.98, alpha: 1.0)
    })

    /// Bottom color of the app-wide background gradient.
    static let backgroundBottom = Color(UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor(red: 0.05, green: 0.02, blue: 0.10, alpha: 1.0)
            : UIColor(red: 0.94, green: 0.93, blue: 0.96, alpha: 1.0)
    })

    /// The standard full-screen background gradient. Apply to major container
    /// views with `.ignoresSafeArea()`.
    static var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: [backgroundTop, backgroundBottom],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    // MARK: - Surfaces

    /// Default surface for cards, input fields, and elevated content.
    static let surface = Color(UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.08)
            : UIColor.white
    })

    /// Slightly brighter surface for hovered/pressed states or elevated cards.
    static let surfaceElevated = Color(UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.12)
            : UIColor(red: 0.96, green: 0.96, blue: 0.97, alpha: 1.0)
    })

    /// Border color for input fields, cards, and containers.
    static let surfaceBorder = Color(UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.12)
            : UIColor.black.withAlphaComponent(0.08)
    })

    // MARK: - Accent

    /// Primary accent color used for buttons, selected states, progress indicators.
    static let accent = Color.pink

    // MARK: - Text

    /// Primary text color — adapts to light/dark mode.
    static let textPrimary = Color(UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor.white
            : UIColor(red: 0.12, green: 0.10, blue: 0.16, alpha: 1.0)
    })

    /// Secondary text — reduced emphasis.
    static let textSecondary = Color(UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.6)
            : UIColor.black.withAlphaComponent(0.55)
    })

    /// Tertiary text — placeholders and fine print.
    static let textTertiary = Color(UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.35)
            : UIColor.black.withAlphaComponent(0.3)
    })

    // MARK: - Progress Bar

    /// Progress bar track (unfilled portion).
    static let progressTrack = Color(UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.10)
            : UIColor.black.withAlphaComponent(0.08)
    })

    /// Progress bar fill.
    static let progressFill = Color.pink

    // MARK: - Overlay

    /// Semi-transparent overlay for loading states and modals.
    static let overlayDim = Color(UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor.black.withAlphaComponent(0.4)
            : UIColor.black.withAlphaComponent(0.3)
    })

    // MARK: - Sign-In Screen

    /// Warm cream background for the photo grid section of the sign-in screen.
    static let signInCream = Color(red: 1.0, green: 0.94, blue: 0.88)

    /// Coral-pink fill for the primary "Get Started" CTA button.
    static let signInButtonPrimary = Color(red: 0.96, green: 0.26, blue: 0.40)

    /// Fill for the secondary "I already have an account" button.
    static let signInButtonSecondary = Color(UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.10)
            : UIColor.black.withAlphaComponent(0.05)
    })

    /// Border for the secondary sign-in button.
    static let signInButtonSecondaryBorder = Color(UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.20)
            : UIColor.black.withAlphaComponent(0.12)
    })

    // MARK: - Status

    /// Error / destructive — danger CTAs, destructive badges, error borders.
    static let statusError = Color(UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor(red: 1.00, green: 0.42, blue: 0.45, alpha: 1.0)
            : UIColor(red: 0.86, green: 0.20, blue: 0.27, alpha: 1.0)
    })

    /// 12% tint of `statusError` for filled badge / banner backgrounds.
    static let statusErrorTint = Color(UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor(red: 1.00, green: 0.42, blue: 0.45, alpha: 0.12)
            : UIColor(red: 0.86, green: 0.20, blue: 0.27, alpha: 0.12)
    })

    /// Success — confirmation states, success borders.
    static let statusSuccess = Color(UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor(red: 0.45, green: 0.85, blue: 0.55, alpha: 1.0)
            : UIColor(red: 0.16, green: 0.62, blue: 0.32, alpha: 1.0)
    })

    /// 12% tint of `statusSuccess`.
    static let statusSuccessTint = Color(UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor(red: 0.45, green: 0.85, blue: 0.55, alpha: 0.12)
            : UIColor(red: 0.16, green: 0.62, blue: 0.32, alpha: 0.12)
    })

    /// Warning — caution states, "Pro Tips" surfaces.
    static let statusWarning = Color(UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor(red: 1.00, green: 0.78, blue: 0.30, alpha: 1.0)
            : UIColor(red: 0.85, green: 0.55, blue: 0.10, alpha: 1.0)
    })

    /// 12% tint of `statusWarning`.
    static let statusWarningTint = Color(UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor(red: 1.00, green: 0.78, blue: 0.30, alpha: 0.12)
            : UIColor(red: 0.85, green: 0.55, blue: 0.10, alpha: 0.12)
    })

    /// Info — neutral informational surfaces.
    static let statusInfo = Color(UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor(red: 0.40, green: 0.70, blue: 1.00, alpha: 1.0)
            : UIColor(red: 0.10, green: 0.45, blue: 0.85, alpha: 1.0)
    })

    /// 12% tint of `statusInfo`.
    static let statusInfoTint = Color(UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor(red: 0.40, green: 0.70, blue: 1.00, alpha: 0.12)
            : UIColor(red: 0.10, green: 0.45, blue: 0.85, alpha: 0.12)
    })
}

// MARK: - Token Scales

extension Theme {

    /// 4pt-grid spacing scale used by primitives in `Components/UI`.
    enum Spacing {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 24
        static let xxxl: CGFloat = 32
    }

    /// Corner-radius scale. `lg` matches the most common radius across the codebase;
    /// `xl` matches `RecommendationCard`. `pill` is a sentinel for `Capsule`-shaped components.
    enum Radius {
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 14
        static let xl: CGFloat = 18
        static let pill: CGFloat = 999
    }

    /// Semantic typography tokens. Maps shadcn text scale onto SwiftUI's `Font` system.
    enum Typography {
        static let xs: Font = .caption2
        static let sm: Font = .caption
        static let base: Font = .subheadline
        static let body: Font = .body
        static let lg: Font = .headline
        static let xl: Font = .title3
        static let xxl: Font = .title2
        static let display: Font = .system(size: 28, weight: .bold)
    }

    /// Standardized animation curves for primitive interactions.
    enum Motion {
        static let standard: SwiftUI.Animation = .easeInOut(duration: 0.25)
        static let quick: SwiftUI.Animation = .easeInOut(duration: 0.15)
    }

    /// Font-weight scale aliasing SwiftUI's `Font.Weight`. Excludes the unused
    /// `.thin`, `.ultraLight`, and `.black` weights to keep the design surface tight.
    enum Weight {
        static let regular: Font.Weight = .regular
        static let medium: Font.Weight = .medium
        static let semibold: Font.Weight = .semibold
        static let bold: Font.Weight = .bold
        static let heavy: Font.Weight = .heavy
    }

    /// Token used by `Theme.Shadow` and the `View.shadow(_:)` extension.
    struct ShadowToken {
        let color: Color
        let radius: CGFloat
        let x: CGFloat
        let y: CGFloat
    }

    /// Three-tier elevation scale plus an accent-tinted glow, derived from
    /// existing card and chip shadow patterns in the codebase.
    enum Shadow {
        /// Tight shadow for interactive small elements (chips, pills).
        static let sm = ShadowToken(color: .black.opacity(0.4), radius: 2, x: 0, y: 1)
        /// Standard elevated card shadow.
        static let md = ShadowToken(color: .black.opacity(0.25), radius: 12, x: 0, y: 4)
        /// Prominent card shadow (hero, focused).
        static let lg = ShadowToken(color: .black.opacity(0.3), radius: 16, x: 0, y: 6)
        /// Accent-tinted glow that preserves the "pink halo" used on
        /// featured recommendation cards.
        static let accentGlow = ShadowToken(color: Color.pink.opacity(0.35), radius: 12, x: 0, y: 6)
    }
}

extension View {
    /// Apply a `Theme.ShadowToken` to a view in one call:
    /// `.shadow(Theme.Shadow.md)`.
    func shadow(_ token: Theme.ShadowToken) -> some View {
        shadow(color: token.color, radius: token.radius, x: token.x, y: token.y)
    }
}
