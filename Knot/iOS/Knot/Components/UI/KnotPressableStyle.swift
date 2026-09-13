//
//  KnotPressableStyle.swift
//  Knot
//
//  Press feedback for a tappable *surface* — a card, a row, a tile — as
//  opposed to a button's chrome. Wrap the surface in a `Button` and apply
//  this style; the surface itself is the label, and it presses like a
//  physical thing.
//

import SwiftUI

/// A `ButtonStyle` that adds press feedback to a whole surface without
/// styling it: the label scales down and dims slightly while pressed, and
/// springs back on release.
///
/// ```swift
/// Button(action: open) {
///     KnotCard { … }
/// }
/// .buttonStyle(KnotPressableStyle())
/// ```
///
/// Why a `Button` + style rather than `.onTapGesture` + a hand-rolled pressed
/// flag: `Button` already owns the hard parts — it tracks the touch, it waits
/// for the enclosing `ScrollView` to rule out a scroll before highlighting, and
/// it *cancels* the pressed state when the finger drags away or a scroll takes
/// over. A `DragGesture(minimumDistance: 0)` reporting `isPressed` gets none of
/// that for free and famously sticks "pressed" when the scroll view cancels it
/// without calling `onEnded`.
///
/// Inner buttons keep working: SwiftUI resolves a touch to the *deepest*
/// button, so a `KnotButton` or icon `Button` inside the label fires its own
/// action and does not light up the surface. Those inner buttons must set
/// their own `.buttonStyle(...)` (they all do), or this style would propagate
/// down to them through the environment.
///
/// Reduce Motion: the scale is dropped and only the dim remains, on the
/// standard quick curve — the press still reads, it just doesn't move.
struct KnotPressableStyle: ButtonStyle {

    /// How far the surface shrinks while pressed. Subtle on purpose — this is
    /// a card settling under a finger, not a game button.
    static let pressedScale: CGFloat = 0.97

    /// How much the surface dims while pressed. On the app's light ground a
    /// white card at this opacity blends toward the page, which reads as
    /// "pushed in" rather than "faded out".
    static let pressedOpacity: Double = 0.92

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        return configuration.label
            .scaleEffect(reduceMotion || !pressed ? 1 : Self.pressedScale)
            .opacity(pressed ? Self.pressedOpacity : 1)
            .animation(Self.animation(pressed: pressed, reduceMotion: reduceMotion), value: pressed)
    }

    /// Which curve to run for a transition *into* the given state.
    ///
    /// Pure and `static` so the asymmetry (fast ease-out down, springy release)
    /// and the Reduce Motion fallback are testable without rendering a button.
    static func animation(pressed: Bool, reduceMotion: Bool) -> SwiftUI.Animation {
        if reduceMotion { return Theme.Motion.quick }
        return pressed ? Theme.Motion.pressDown : Theme.Motion.pressRelease
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Pressable Card") {
    VStack(spacing: 20) {
        Button(action: {}) {
            KnotCard(padding: .lg, radius: Theme.Radius.xl) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Press and hold me")
                        .knotFont(Theme.Typography.cardTitleSemibold)
                        .foregroundStyle(Theme.textPrimary)
                    Text("The whole surface settles under your finger and springs back on release.")
                        .knotFont(Theme.Typography.label)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .buttonStyle(KnotPressableStyle())
    }
    .padding(20)
    .background(Theme.backgroundGradient.ignoresSafeArea())
}
#endif
