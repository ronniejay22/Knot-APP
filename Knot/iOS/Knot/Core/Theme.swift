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
    ///
    /// `static let` (not `static var`) so we allocate the `LinearGradient`
    /// once at app load instead of on every view-body evaluation. Every
    /// major view applies this as its root background, so the savings
    /// compound across re-renders. `backgroundTop` / `backgroundBottom`
    /// are themselves adaptive `Color(UIColor { tc in ... })` tokens, so
    /// light/dark trait changes still resolve correctly through the
    /// gradient — the memoization is safe.
    static let backgroundGradient = LinearGradient(
        colors: [backgroundTop, backgroundBottom],
        startPoint: .top,
        endPoint: .bottom
    )

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

    // MARK: - Brand Palette

    /// Brand primary — the coral-pink that signals action and identity.
    /// Light values match `signInButtonPrimary`; dark keeps the same hue since
    /// it already reads as a brand mark on the deep-purple background.
    static let colorPrimary = Color(UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor(red: 0.96, green: 0.26, blue: 0.40, alpha: 1.0)
            : UIColor(red: 0.96, green: 0.26, blue: 0.40, alpha: 1.0)
    })

    /// Brand secondary — the warm cream supporting surface.
    /// Light values match `signInCream`; dark resolves to a warm-tinted dark
    /// so the "soft supporting surface" semantics survive the inversion
    /// instead of forcing a cream fill onto the deep-purple background.
    static let colorSecondary = Color(UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor(red: 0.18, green: 0.13, blue: 0.12, alpha: 1.0)
            : UIColor(red: 1.0, green: 0.94, blue: 0.88, alpha: 1.0)
    })

    /// Brand tertiary — the high-contrast ink color.
    /// Light values match the deep-plum used by `textPrimary`; dark flips to
    /// an off-white so the contrast role is preserved.
    static let colorTertiary = Color(UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor(red: 0.95, green: 0.93, blue: 0.95, alpha: 1.0)
            : UIColor(red: 0.12, green: 0.10, blue: 0.16, alpha: 1.0)
    })

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

    /// Font family / PostScript names for the bundled custom font faces.
    /// Fraunces is bundled as a single variable font — pick the weight axis
    /// at the token level via `.weight(...)`. DM Sans uses static per-weight
    /// cuts whose PostScript names match their filenames.
    /// Verify any change via `Theme.registerFonts()`'s debug print.
    private enum FontFamily {
        /// Fraunces variable font: family name resolved by SwiftUI's
        /// `Font.custom(...)`. Weight axis is selected per-token via
        /// `.weight(...)`. The italic axis lives in a separate variable font
        /// file we don't currently bundle, so italic-style tokens use the
        /// upright family with `.italic()` synthesis.
        static let fraunces = "Fraunces"
        enum DMSans {
            static let regular = "DMSans-Regular"
            static let medium = "DMSans-Medium"
            static let semibold = "DMSans-SemiBold"
            static let bold = "DMSans-Bold"
        }
    }

    /// Semantic typography tokens, backed by the bundled Fraunces (serif,
    /// display) and DM Sans (sans, body) families. Each token is built via
    /// `Font.custom(_:size:relativeTo:)` so it continues to scale with iOS
    /// Dynamic Type relative to the chosen system style.
    ///
    /// For Fraunces (variable font), weight is selected here via `.weight(...)`
    /// against the variable font's weight axis. For DM Sans (static cuts),
    /// weight is baked into the chosen face. Either way, callers get a single
    /// `Font` value and should apply it via `.knotFont(_:)` without further
    /// chaining.
    ///
    /// Apply via the `View.knotFont(_:)` extension at the bottom of this file.
    enum Typography {
        /// Fraunces (Light, 300) @ 42pt. Reserved for the sign-in wordmark
        /// and other hero-scale moments. Scales relative to `.largeTitle`.
        static let heroDisplay: Font = .custom(FontFamily.fraunces, size: 42, relativeTo: .largeTitle).weight(.light)

        /// Fraunces (Light, 300) @ 28pt. Page titles and prominent section
        /// headers. Scales relative to `.title`.
        static let sectionHeader: Font = .custom(FontFamily.fraunces, size: 28, relativeTo: .title).weight(.light)

        /// Fraunces (SemiBold, 600) @ 28pt. Onboarding page titles — same
        /// 28pt scale as `sectionHeader` but a heavier weight so the
        /// onboarding flow reads as a more deliberate brand moment.
        /// Scales relative to `.title`.
        static let onboardingHeader: Font = .custom(FontFamily.fraunces, size: 28, relativeTo: .title).weight(.semibold)

        /// Fraunces (SemiBold, 600) @ 20pt. Onboarding sub-headers — the
        /// page title on form-style onboarding screens (Birthday, Anniversary,
        /// PartnerName, Location, etc.) where a 20pt header reads better than
        /// the 28pt `onboardingHeader`. Sister to `cardTitle`: same family,
        /// size, and Dynamic Type relation, only the weight axis differs.
        /// Scales relative to `.title2`.
        static let onboardingSubHeader: Font = .custom(FontFamily.fraunces, size: 20, relativeTo: .title2).weight(.semibold)

        /// Fraunces (Regular, 400) @ 20pt. Card titles and secondary headings.
        /// Scales relative to `.title2`.
        static let cardTitle: Font = .custom(FontFamily.fraunces, size: 20, relativeTo: .title2)

        /// Fraunces (Light, 300) @ 17pt with synthesized italic — brand-moment
        /// quotes, sign-in tagline, recommendation attributions. Synthesized
        /// because the italic Fraunces variable font isn't currently bundled;
        /// to upgrade to a true italic cut, add the italic VF and switch the
        /// `.italic()` modifier for a dedicated PostScript name.
        static let italicQuote: Font = .custom(FontFamily.fraunces, size: 17, relativeTo: .body).weight(.light).italic()

        /// DMSans-Regular @ 17pt. Default body / descriptive copy.
        /// Scales relative to `.body`.
        static let body: Font = .custom(FontFamily.DMSans.regular, size: 17, relativeTo: .body)

        /// DMSans-Medium @ 13pt. Labels, captions, fine print.
        /// Scales relative to `.caption`.
        static let label: Font = .custom(FontFamily.DMSans.medium, size: 13, relativeTo: .caption)

        /// DMSans-SemiBold @ 17pt. Primary CTA buttons.
        /// Scales relative to `.body`.
        static let cta: Font = .custom(FontFamily.DMSans.semibold, size: 17, relativeTo: .body)

        /// DMSans-Bold @ 17pt. Numeric callouts (streak counts, totals).
        /// Scales relative to `.body`.
        static let numeric: Font = .custom(FontFamily.DMSans.bold, size: 17, relativeTo: .body)

        // MARK: - Deprecated legacy tokens (kept for backwards compatibility).
        // Map to the closest new token; new code should use the named tokens
        // above directly.

        @available(*, deprecated, renamed: "label", message: "Use Theme.Typography.label.")
        static let xs: Font = label

        @available(*, deprecated, renamed: "label", message: "Use Theme.Typography.label.")
        static let sm: Font = label

        @available(*, deprecated, renamed: "body", message: "Use Theme.Typography.body.")
        static let base: Font = body

        @available(*, deprecated, renamed: "cardTitle", message: "Use Theme.Typography.cardTitle.")
        static let lg: Font = cardTitle

        @available(*, deprecated, renamed: "cardTitle", message: "Use Theme.Typography.cardTitle.")
        static let xl: Font = cardTitle

        @available(*, deprecated, renamed: "cardTitle", message: "Use Theme.Typography.cardTitle.")
        static let xxl: Font = cardTitle

        @available(*, deprecated, renamed: "sectionHeader", message: "Use Theme.Typography.sectionHeader.")
        static let display: Font = sectionHeader
    }

    /// Standardized animation curves for primitive interactions.
    enum Motion {
        static let standard: SwiftUI.Animation = .easeInOut(duration: 0.25)
        static let quick: SwiftUI.Animation = .easeInOut(duration: 0.15)
    }

    /// Font-weight scale aliasing SwiftUI's `Font.Weight`.
    ///
    /// **Deprecated.** With custom fonts (Fraunces / DM Sans), weight is baked
    /// into the chosen face — chaining `.fontWeight(...)` after a
    /// `Theme.Typography.*` token can re-substitute the system font when the
    /// requested weight isn't in the active family. Pick the right
    /// `Theme.Typography.*` token instead.
    @available(*, deprecated, message: "Weight is baked into Theme.Typography tokens. Pick the matching token instead of chaining .fontWeight().")
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

    /// Apply a `Theme.Typography` token. Single migration entry point — keeps
    /// `Font.custom` calls out of view code and prevents callers from chaining
    /// `.fontWeight(...)` (weight is already baked into each token).
    func knotFont(_ token: Font) -> some View {
        font(token)
    }
}

extension Text {
    /// `Text`-only overload of `knotFont(_:)` for `Text + Text` concatenation
    /// cases (e.g., the two-tone "Knot" wordmark on the sign-in screen),
    /// where the modifier must be applied per-`Text` rather than to the
    /// resulting view.
    func knotFont(_ token: Font) -> Text {
        font(token)
    }
}

extension Theme {
    /// Debug helper that prints loaded font families and the per-family
    /// PostScript names we depend on. `Font.custom` silently falls back to
    /// the system font if a face isn't bundled or its PostScript name doesn't
    /// match — this print is the only reliable signal that registration
    /// succeeded. Call once from `KnotApp.init()` under `#if DEBUG`.
    static func registerFonts() {
        #if DEBUG
        let expectedFamilies = ["Fraunces", "DM Sans"]
        let allFamilies = Set(UIFont.familyNames)
        print("🔤 [Theme.registerFonts] expecting:", expectedFamilies)
        for family in expectedFamilies {
            if allFamilies.contains(family) {
                let names = UIFont.fontNames(forFamilyName: family)
                print("🔤   ✅ \(family) loaded — faces: \(names)")
            } else {
                print("🔤   ❌ \(family) NOT loaded — check Info.plist UIAppFonts and Copy Bundle Resources")
            }
        }
        #endif
    }
}
