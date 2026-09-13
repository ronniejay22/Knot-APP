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
/// styling it: the label scales down and dims while pressed, and springs back
/// on release.
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
/// The pressed look is held for at least `Theme.Motion.pressHold`, however
/// short the touch was. Driven purely by `isPressed`, a quick tap presses and
/// releases within a frame or two — the settle never gets drawn, and the
/// surface looks inert. The style mirrors `isPressed` into its own state and
/// defers the release until the hold has elapsed, so a tap reads as a press
/// and the spring-back actually plays. A press that outlasts the hold releases
/// the moment the finger lifts. A surface whose tap *presents* something
/// should defer that presentation by the same hold — see
/// `MilestoneCard.cardTapped(delay:)` — or the cover lands on top of the
/// spring-back and hides it.
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
    /// a card settling under a finger, not a game button — but far enough to
    /// register in the ~150 ms a tap gives it.
    static let pressedScale: CGFloat = 0.96

    /// How much the surface dims while pressed. On the app's light ground a
    /// white card at this opacity blends toward the page, which reads as
    /// "pushed in" rather than "faded out".
    static let pressedOpacity: Double = 0.90

    func makeBody(configuration: Configuration) -> some View {
        PressableLabel(configuration: configuration)
    }

    /// Which curve to run for a transition *into* the given state.
    ///
    /// Pure and `static` so the asymmetry (fast ease-out down, springy release)
    /// and the Reduce Motion fallback are testable without rendering a button.
    static func animation(pressed: Bool, reduceMotion: Bool) -> SwiftUI.Animation {
        if reduceMotion { return Theme.Motion.quick }
        return pressed ? Theme.Motion.pressDown : Theme.Motion.pressRelease
    }

    /// How much longer the pressed look must stay up once the finger lifts, so
    /// it has been shown for at least `hold` in total. Zero once the press has
    /// already outlasted the hold — a long press releases on lift, not later.
    ///
    /// Pure and `static` for the same reason as `animation(pressed:reduceMotion:)`.
    static func releaseDelay(
        pressedFor elapsed: Duration,
        hold: Duration = Theme.Motion.pressHold
    ) -> Duration {
        max(.zero, hold - elapsed)
    }
}

// MARK: - Label

/// The style's body, split out because holding the press needs state — and a
/// `ButtonStyle` is a value with no `@State` of its own.
///
/// `shownPressed` is what the label actually renders. It follows
/// `configuration.isPressed` up immediately and down only after the minimum
/// hold; a press that arrives while a release is still pending cancels that
/// release and starts a fresh hold.
private struct PressableLabel: View {

    let configuration: ButtonStyleConfiguration

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var shownPressed = false
    @State private var pressedAt: ContinuousClock.Instant?
    @State private var pendingRelease: Task<Void, Never>?

    var body: some View {
        configuration.label
            .scaleEffect(reduceMotion || !shownPressed ? 1 : KnotPressableStyle.pressedScale)
            .opacity(shownPressed ? KnotPressableStyle.pressedOpacity : 1)
            .animation(
                KnotPressableStyle.animation(pressed: shownPressed, reduceMotion: reduceMotion),
                value: shownPressed
            )
            .onChange(of: configuration.isPressed) { _, isPressed in
                if isPressed {
                    press()
                } else {
                    release()
                }
            }
            .onDisappear {
                // Leaving mid-hold (tab switch, list recycle) must not bring
                // the surface back still pressed with nothing left to release it.
                pendingRelease?.cancel()
                pendingRelease = nil
                pressedAt = nil
                shownPressed = false
            }
    }

    private func press() {
        pendingRelease?.cancel()
        pendingRelease = nil
        pressedAt = .now
        shownPressed = true
    }

    private func release() {
        let elapsed = pressedAt.map { ContinuousClock.now - $0 } ?? .zero
        pressedAt = nil
        let delay = KnotPressableStyle.releaseDelay(pressedFor: elapsed)
        guard delay > .zero else {
            shownPressed = false
            return
        }
        pendingRelease = Task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            shownPressed = false
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Pressable Card") {
    VStack(spacing: 20) {
        Button(action: {}) {
            KnotCard(padding: .lg, radius: Theme.Radius.xl) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Tap or press me")
                        .knotFont(Theme.Typography.cardTitleSemibold)
                        .foregroundStyle(Theme.textPrimary)
                    Text("The whole surface settles under your finger — even on a quick tap — and springs back on release.")
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
