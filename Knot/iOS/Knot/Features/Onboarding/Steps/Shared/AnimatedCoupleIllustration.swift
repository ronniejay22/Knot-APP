//
//  AnimatedCoupleIllustration.swift
//  Knot
//
//  Idle animation for the onboarding Welcome illustration, ported from a
//  Figma Make (Framer Motion) prototype into native SwiftUI. Three concurrent,
//  infinitely-looping ambient effects layered over the existing `onboarding-0`
//  image:
//    1. The couple gently floats up/down and "breathes" (subtle scale).
//    2. A soft warm coral glow pulses beneath the couple.
//    3. Small hearts drift upward, fading in and out.
//
//  These are long-running *ambient* loops (4–5s cycles), so they intentionally
//  use their own durations rather than `Theme.Motion.standard/quick`, which are
//  0.15–0.25s micro-interaction tokens. Honors Reduce Motion by falling back to
//  the static illustration.
//

import SwiftUI

struct AnimatedCoupleIllustration: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Matches the height the Welcome screen previously gave the static image.
    private let illustrationHeight: CGFloat = 340

    /// Drives the couple float/breathe and glow pulse. A single trigger flipped
    /// in `onAppear`; each layer attaches its own duration via `.animation`.
    @State private var animate = false

    var body: some View {
        if reduceMotion {
            // Accessibility fallback: the static illustration, rendered exactly
            // as the Welcome screen did before the animation was added.
            illustrationImage
        } else {
            animatedBody
        }
    }

    private var illustrationImage: some View {
        Image("Onboarding/onboarding-0")
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(maxWidth: .infinity)
            .frame(height: illustrationHeight)
            .clipped()
    }

    private var animatedBody: some View {
        GeometryReader { geo in
            ZStack {
                // 1. Warm glow pulse beneath the couple.
                Ellipse()
                    .fill(
                        RadialGradient(
                            colors: [Theme.colorPrimary.opacity(0.18), .clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: 100
                        )
                    )
                    .frame(width: 200, height: 60)
                    .blur(radius: 8)
                    .scaleEffect(animate ? 1.03 : 0.97)
                    .opacity(animate ? 0.45 : 0.25)
                    .position(x: geo.size.width / 2, y: geo.size.height * 0.86)
                    .animation(
                        .easeInOut(duration: 2.5).repeatForever(autoreverses: true),
                        value: animate
                    )

                // 2. Couple illustration with gentle float + breathe.
                Image("Onboarding/onboarding-0")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                    .offset(y: animate ? -10 : 0)
                    .scaleEffect(animate ? 1.018 : 1.0)
                    .animation(
                        .easeInOut(duration: 2).repeatForever(autoreverses: true),
                        value: animate
                    )

                // 3. Floating hearts above the illustration.
                ForEach(Self.heartConfigs) { config in
                    FloatingHeart(config: config)
                        .position(
                            x: geo.size.width * config.left,
                            y: geo.size.height * (1 - config.bottom)
                        )
                }
            }
        }
        .frame(height: illustrationHeight)
        .onAppear { animate = true }
    }

    // MARK: - Heart configuration

    /// The six floating hearts, transcribed from the prototype's `HEARTS` array.
    /// `left`/`bottom` are fractions of the container (the prototype's CSS
    /// percentages); `driftX` is the horizontal drift in points. Exposed for tests.
    static let heartConfigs: [HeartConfig] = [
        HeartConfig(id: 0, left: 0.43, bottom: 0.58, delay: 0.0, duration: 3.6, size: 17, color: Self.rose1, driftX: -16),
        HeartConfig(id: 1, left: 0.54, bottom: 0.54, delay: 1.3, duration: 4.1, size: 12, color: Self.rose2, driftX: 13),
        HeartConfig(id: 2, left: 0.33, bottom: 0.60, delay: 2.2, duration: 3.3, size: 10, color: Self.rose3, driftX: -9),
        HeartConfig(id: 3, left: 0.62, bottom: 0.55, delay: 0.7, duration: 3.9, size: 14, color: Self.rose4, driftX: 20),
        HeartConfig(id: 4, left: 0.48, bottom: 0.62, delay: 1.8, duration: 3.5, size: 9, color: Self.rose5, driftX: -6),
        HeartConfig(id: 5, left: 0.38, bottom: 0.52, delay: 3.0, duration: 4.2, size: 11, color: Self.rose6, driftX: 10),
    ]

    // Rose palette derived from the brand coral (Theme.colorPrimary ≈ #F44266 /
    // prototype #e95170). Kept as local shades to give the hearts gradient variety.
    private static let rose1 = Color(red: 0.914, green: 0.318, blue: 0.439) // #e95170
    private static let rose2 = Color(red: 0.961, green: 0.627, blue: 0.710) // #f5a0b5
    private static let rose3 = Color(red: 1.000, green: 0.784, blue: 0.839) // #ffc8d6
    private static let rose4 = Color(red: 0.788, green: 0.251, blue: 0.376) // #c94060
    private static let rose5 = Color(red: 0.969, green: 0.722, blue: 0.773) // #f7b8c5
    private static let rose6 = Color(red: 0.878, green: 0.376, blue: 0.502) // #e06080
}

/// Per-heart configuration for `FloatingHeart`.
struct HeartConfig: Identifiable {
    let id: Int
    let left: CGFloat
    let bottom: CGFloat
    let delay: Double
    let duration: Double
    let size: CGFloat
    let color: Color
    let driftX: CGFloat
}

// MARK: - Floating heart

/// A single heart that rises, drifts sideways, scales, and fades on an infinite
/// loop. Uses `keyframeAnimator` to reproduce the prototype's non-symmetric
/// multi-stop keyframe path. The per-heart `delay` is applied once (via a start
/// gate) so subsequent loops run seamlessly — matching Framer Motion semantics.
private struct FloatingHeart: View {
    let config: HeartConfig

    @State private var started = false

    var body: some View {
        Group {
            if started {
                HeartShape()
                    .fill(config.color)
                    .frame(width: config.size, height: config.size)
                    .keyframeAnimator(initialValue: HeartPhase.start, repeating: true) { content, phase in
                        content
                            .opacity(phase.opacity)
                            .scaleEffect(phase.scale)
                            .offset(x: phase.xOffset, y: phase.yOffset)
                    } keyframes: { _ in
                        // Segment durations from times [0, 0.1, 0.35, 0.7, 1].
                        let d = config.duration
                        let d1 = 0.10 * d, d2 = 0.25 * d, d3 = 0.35 * d, d4 = 0.30 * d
                        let drift = config.driftX

                        KeyframeTrack(\.opacity) {
                            LinearKeyframe(0, duration: d1)
                            LinearKeyframe(1, duration: d2)
                            LinearKeyframe(1, duration: d3)
                            LinearKeyframe(0, duration: d4)
                        }
                        KeyframeTrack(\.yOffset) {
                            CubicKeyframe(-10, duration: d1)
                            CubicKeyframe(-50, duration: d2)
                            CubicKeyframe(-90, duration: d3)
                            CubicKeyframe(-130, duration: d4)
                        }
                        KeyframeTrack(\.xOffset) {
                            CubicKeyframe(drift * 0.15, duration: d1)
                            CubicKeyframe(drift * 0.50, duration: d2)
                            CubicKeyframe(drift * 0.85, duration: d3)
                            CubicKeyframe(drift, duration: d4)
                        }
                        KeyframeTrack(\.scale) {
                            CubicKeyframe(0.7, duration: d1)
                            CubicKeyframe(1.0, duration: d2)
                            CubicKeyframe(0.9, duration: d3)
                            CubicKeyframe(0.6, duration: d4)
                        }
                    }
            } else {
                Color.clear.frame(width: config.size, height: config.size)
            }
        }
        .allowsHitTesting(false)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + config.delay) {
                started = true
            }
        }
    }
}

/// Animatable state for a floating heart.
private struct HeartPhase {
    var yOffset: CGFloat
    var xOffset: CGFloat
    var scale: CGFloat
    var opacity: Double

    static let start = HeartPhase(yOffset: 0, xOffset: 0, scale: 0.2, opacity: 0)
}

/// The prototype's heart glyph (SVG `viewBox 0 0 24 24`), transcribed to a
/// resolution-independent `Shape` drawn within the given rect.
private struct HeartShape: Shape {
    func path(in rect: CGRect) -> Path {
        // Control/anchor points normalized to 0...1 (original coords / 24),
        // mapped into `rect`.
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
        }

        var path = Path()
        path.move(to: p(0.5000, 0.8997))
        path.addCurve(to: p(0.0417, 0.2996), control1: p(0.2654, 0.6689), control2: p(0.0417, 0.4707))
        path.addCurve(to: p(0.2617, 0.0833), control1: p(0.0417, 0.1417), control2: p(0.1695, 0.0833))
        path.addCurve(to: p(0.5000, 0.2690), control1: p(0.3164, 0.0833), control2: p(0.4347, 0.1042))
        path.addCurve(to: p(0.7386, 0.0838), control1: p(0.5663, 0.1037), control2: p(0.6860, 0.0838))
        path.addCurve(to: p(0.9583, 0.2996), control1: p(0.8444, 0.0838), control2: p(0.9583, 0.1513))
        path.addCurve(to: p(0.5000, 0.8997), control1: p(0.9583, 0.4692), control2: p(0.7443, 0.6590))
        path.closeSubpath()
        return path
    }
}

#Preview {
    ZStack {
        Theme.backgroundGradient
        AnimatedCoupleIllustration()
    }
    .ignoresSafeArea()
}
