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
}
