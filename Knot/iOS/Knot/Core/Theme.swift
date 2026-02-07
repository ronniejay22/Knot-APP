//
//  Theme.swift
//  Knot
//
//  Created on February 7, 2026.
//  Step 3.3: App-wide design system — dark purple aesthetic.
//

import SwiftUI

/// Knot's centralized design system. All colors, gradients, and visual constants
/// live here so every screen shares the same aesthetic.
///
/// The app uses a dark purple gradient background inspired by the interests
/// selection screen reference. `.preferredColorScheme(.dark)` is set at the
/// app level (KnotApp.swift), so SwiftUI semantic colors (`.primary`,
/// `.secondary`, `.tertiary`) automatically resolve to light-on-dark values.
///
/// Use `Theme` colors for backgrounds and surfaces. Use semantic SwiftUI
/// styles (`.primary`, `.secondary`) for text when possible — they adapt
/// correctly in dark mode. Use `Theme.textSecondary` / `.textTertiary`
/// only when you need the exact opacity values from the reference design.
enum Theme {

    // MARK: - Background Gradient

    /// Top color of the app-wide background gradient.
    static let backgroundTop = Color(red: 0.10, green: 0.05, blue: 0.16)

    /// Bottom color of the app-wide background gradient.
    static let backgroundBottom = Color(red: 0.05, green: 0.02, blue: 0.10)

    /// The standard full-screen background gradient. Apply to major container
    /// views (SignInView, OnboardingContainerView, HomeView) with `.ignoresSafeArea()`.
    static var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: [backgroundTop, backgroundBottom],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    // MARK: - Surfaces

    /// Default surface for cards, input fields, and elevated content.
    /// Semi-transparent white on the dark gradient creates a frosted-glass effect.
    static let surface = Color.white.opacity(0.08)

    /// Slightly brighter surface for hovered/pressed states or elevated cards.
    static let surfaceElevated = Color.white.opacity(0.12)

    /// Border color for input fields, cards, and containers.
    static let surfaceBorder = Color.white.opacity(0.12)

    // MARK: - Accent

    /// Primary accent color used for buttons, selected states, progress indicators.
    static let accent = Color.pink

    // MARK: - Text (Explicit)

    /// Primary text color — use `.foregroundStyle(.white)` or `.primary` in dark mode.
    /// Provided here for cases where an explicit `Color` value is needed.
    static let textPrimary = Color.white

    /// Secondary text — 60% white. Matches the reference subtitle style.
    static let textSecondary = Color.white.opacity(0.6)

    /// Tertiary text — 35% white. Used for placeholders and fine print.
    static let textTertiary = Color.white.opacity(0.35)

    // MARK: - Progress Bar

    /// Progress bar track (unfilled portion).
    static let progressTrack = Color.white.opacity(0.10)

    /// Progress bar fill.
    static let progressFill = Color.pink
}
