//
//  RecommendationsLoadingView.swift
//  Knot
//
//  The screen that covers the app's longest wait: ~25 seconds of AI
//  recommendation generation. Shared by the For You tab
//  (`RecommendationsView`) and the in-onboarding reveal
//  (`OnboardingCompletionView`), which are the two surfaces that actually run
//  the pipeline.
//
//  Replaces the previous `ForYouLoadingView` (orbiting Lucide icons around a
//  gradient tile) and, with it, `ForYouClimaxView` — the 2.3-second
//  confetti-and-checkmark "Your matches are ready!" splash that used to sit
//  between the wait ending and the picks appearing. There is no celebration
//  now: the loading screen blurs and fades straight into the carousel.
//
//  Design: the "Modern Loading Experience" Figma Make prototype. Deviations
//  from it are documented at the constants they affect.
//

import SwiftUI

// MARK: - Reveal Phase

/// Which surface the recommendation reveal should be showing.
///
/// Both `RecommendationsView` and `OnboardingCompletionView` used to carry
/// their own copy of this branch chain (plus an identical 16-line climax
/// `onChange`), so every change to the flow had to land twice and the two
/// could drift silently. One pure function now decides it for both, which also
/// makes the flow testable for the first time.
enum RecommendationRevealPhase: Equatable {
    /// The pipeline is running — show `RecommendationsLoadingView`.
    case loading
    /// A load is running, but it is a sub-second read of an already-stored
    /// batch. Show nothing rather than a ~25-second generation animation.
    case silent
    /// The load failed.
    case error
    /// The push tap-through found no stored batch (see `pregeneratedMissing`).
    case missing
    /// The load succeeded but produced no picks.
    case empty
    /// Picks are ready.
    case loaded
}

// MARK: - Loading View

struct RecommendationsLoadingView: View {

    // MARK: Content

    /// One rotation step: an illustration and the emphasis phrase it belongs
    /// with.
    private struct Scene {
        /// Asset name. `LoadingIllustrations/` is a namespaced asset folder, so
        /// the namespace prefix is required in the lookup.
        let illustration: String
        /// The emphasis in "Thinking about ___". Verbatim from the prototype —
        /// second person, no gendered pronoun, which is the rule every other
        /// partner-facing string in the app follows.
        let emphasis: String
    }

    /// The rotation, as pairs rather than as two independent lists.
    ///
    /// The illustration and the phrase advance on the same `step`, so pairing
    /// them 1:1 is what makes a phrase always arrive with its own picture.
    /// They were previously two lists of different lengths — nine illustrations
    /// indexed `step % 9` against four phrases indexed `step % 4` — and because
    /// 9 and 4 do not divide, the pairing drifted: a phrase got a different
    /// picture every time it came round, and the pairing did not repeat for 36
    /// steps (90s), far longer than the ~25s this screen is ever up. On screen
    /// the four phrases visibly looped while the art kept changing, which reads
    /// as the pictures running on their own clock.
    ///
    /// Five illustrations are deliberately unused and stay in
    /// `LoadingIllustrations/` — `loading-0` (birthday cake), `loading-2`
    /// (handing over flowers), `loading-5` (a gift by a lit tree), `loading-6`
    /// (a rooftop toast) and `loading-8` (an empty path, the only one of the
    /// nine with no people in it). Changing which four are live is an edit to
    /// this array and nothing else.
    private static let scenes: [Scene] = [
        Scene(illustration: "LoadingIllustrations/loading-4", emphasis: "the things they love"),
        Scene(illustration: "LoadingIllustrations/loading-1", emphasis: "their taste"),
        Scene(illustration: "LoadingIllustrations/loading-7", emphasis: "the little moments"),
        Scene(illustration: "LoadingIllustrations/loading-3", emphasis: "their favorites"),
    ]

    /// The count the pipeline always returns (PRD F2: exactly three cards).
    private static let targetMatches = 3

    /// Points on the ramp where the counter claims each match, as a fraction of
    /// the ramp's own ceiling.
    ///
    /// Explicit thresholds rather than `Int(progress * 3) + 1`, which reached
    /// "3 of 3" at two-thirds of the ramp (~19.6s of 28) and then sat there
    /// while the bar crawled on — the same overclaim `progressCeiling` exists
    /// to avoid. The first lands early so the counter never sits at 0 while the
    /// bar is visibly moving, and the last lands near the end.
    private static let matchThresholds: [CGFloat] = [0.05, 0.45, 0.88]

    // MARK: Timing

    /// How long a single illustration stays on screen.
    ///
    /// The prototype uses 1.15s, but it simulated a 4.2-second wait — about
    /// four swaps. Against a real ~25-second generation that cadence is ~21
    /// swaps, which strobes. 2.5s (~10 swaps) matches the cadence the previous
    /// loading screen used for its copy and leaves time to actually look at a
    /// painterly illustration.
    private static let stepInterval: TimeInterval = 2.5

    /// The progress ramp, carried over unchanged from the previous loading
    /// screen.
    ///
    /// It is a timer, not real progress: generation is one blocking
    /// `POST /api/v1/recommendations/generate` with no progress channel, so
    /// there is nothing to report. It stops at 95% because the parent owns the
    /// final transition — a bar that sat at 100% while the screen was still up
    /// would be a worse lie than one that never quite arrives.
    private static let progressDuration: TimeInterval = 28
    private static let progressCeiling: CGFloat = 0.95

    // MARK: Pure helpers
    //
    // Extracted so the rotation and counter logic can be unit-tested without
    // rendering the view or waiting on a timer.

    /// The scene for a given step, wrapping over the rotation.
    ///
    /// Negative steps wrap too, so no caller can index out of bounds. That is
    /// defensive rather than load-bearing: `step` starts at 0 and only ever
    /// increments, and `illustrationCard`'s underneath-layer is guarded by
    /// `step > 0`, so production never asks for a negative one. It matters
    /// because Swift's `%` keeps the sign of the dividend, so the plain
    /// `step % count` a future caller might reach for would trap here.
    private static func scene(forStep step: Int) -> Scene {
        let index = ((step % scenes.count) + scenes.count) % scenes.count
        return scenes[index]
    }

    /// The asset name for a given step.
    static func illustrationName(forStep step: Int) -> String {
        scene(forStep: step).illustration
    }

    /// The emphasis phrase for a given step. Always the phrase paired with the
    /// illustration `illustrationName(forStep:)` returns for the same step.
    static func emphasis(forStep step: Int) -> String {
        scene(forStep: step).emphasis
    }

    /// How many matches the counter claims to have found at a given progress.
    ///
    /// Monotonic and clamped to `0...targetMatches` by construction — it counts
    /// how many thresholds the ramp has passed, so it can only ever go up and
    /// can never exceed the number of thresholds.
    static func matchesFound(progress: CGFloat) -> Int {
        guard progress > 0, progressCeiling > 0 else { return 0 }
        let fraction = min(1, max(0, progress / progressCeiling))
        return matchThresholds.filter { fraction >= $0 }.count
    }

    /// The full counter line, so the copy is pinned by a test rather than only
    /// by the layout.
    static func matchesLabel(progress: CGFloat) -> String {
        "\(matchesFound(progress: progress)) of \(targetMatches) matches found"
    }

    // MARK: State

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    /// Forces the reduced-motion rendering regardless of the system setting.
    ///
    /// `\.accessibilityReduceMotion` is a read-only environment key, so a test
    /// or preview cannot set it — this is the seam that makes the reduced path
    /// reachable, the same shape as `OccasionEntryModal.entranceAnimated`.
    /// `nil` (the default, and every production call site) defers to the system.
    var reduceMotionOverride: Bool?

    private var reduceMotion: Bool { reduceMotionOverride ?? systemReduceMotion }

    @State private var step = 0

    /// Seconds since the screen appeared, sampled by the rotation timer.
    ///
    /// The bar and the counter are both derived from this one value rather than
    /// from separate state. A `withAnimation`-driven `@State progress` would
    /// have animated the bar correctly — SwiftUI interpolates the *frame* in
    /// the render layer — while the counter, which reads the state directly,
    /// jumped to "3 of 3" on the first frame. One source, one ramp, no
    /// disagreement between the two things showing it.
    @State private var elapsed: TimeInterval = 0

    /// The ramp both the bar and the counter read.
    private var progress: CGFloat {
        let fraction = CGFloat(elapsed / Self.progressDuration)
        return min(Self.progressCeiling, max(0, fraction * Self.progressCeiling))
    }

    var body: some View {
        VStack(spacing: 0) {
            brandHeader
                .padding(.top, Theme.Spacing.xxl)

            Spacer(minLength: Theme.Spacing.xxl)

            illustrationCard
                .padding(.bottom, Theme.Spacing.xxxl)

            headline
                .padding(.bottom, Theme.Spacing.md)

            subline

            Spacer(minLength: Theme.Spacing.xxl)

            progressFooter
        }
        .padding(.horizontal, Theme.Spacing.xxl)
        .padding(.bottom, Theme.Spacing.xxxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.brandGradient.ignoresSafeArea())
        // One timer drives the illustration, the emphasis, and the progress
        // ramp. They advance as a set, and a single stream keeps the wake-ups
        // down — `SignInView`'s photo grid (Step 18.20) is the standing
        // reminder that a continuously-redrawing subtree on this app can
        // saturate the main thread.
        .onReceive(
            Timer.publish(every: Self.stepInterval, on: .main, in: .common).autoconnect()
        ) { _ in
            tick()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Finding ways to make them smile. \(Self.matchesLabel(progress: progress))")
    }

    // MARK: - Sections

    /// Knot wordmark. On every other screen the brand sits in a toolbar or is
    /// absent; here it owns the top of a full-bleed brand surface.
    private var brandHeader: some View {
        HStack(spacing: Theme.Spacing.lg) {
            Image("BrandLogo")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))

            Text("Knot")
                .knotFont(Theme.Typography.heroDisplay)
                .foregroundStyle(Theme.onBrandPrimary)
        }
    }

    /// The crossfading illustration.
    ///
    /// The previous illustration stays mounted underneath so the crossfade
    /// never reveals an empty card — the prototype's `PrevImage` trick. Under
    /// Reduce Motion only one image renders and it never changes.
    private var illustrationCard: some View {
        ZStack {
            if !reduceMotion && step > 0 {
                illustration(forStep: step - 1)
            }

            illustration(forStep: reduceMotion ? 0 : step)
                .id(reduceMotion ? 0 : step)
                .transition(.opacity)
        }
        .aspectRatio(7.0 / 5.0, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.xl, style: .continuous))
        .shadow(Theme.Shadow.lg)
    }

    /// One illustration, sized by its container rather than by itself.
    ///
    /// A `scaledToFill` image reports a size *larger than the proposal* to
    /// preserve its aspect ratio, and that overflow propagates into **layout**
    /// — sized directly, a 1024×1024 illustration would widen this card past
    /// the viewport and shift the whole screen sideways (the bug Step 19.31
    /// shipped on the Journal feed). Composing it as an overlay on
    /// `Color.clear` makes the frame authoritative: `clipShape` then clips
    /// pixels, which is all it can ever do — it does not constrain layout.
    private func illustration(forStep step: Int) -> some View {
        Color.clear
            .overlay {
                Image(Self.illustrationName(forStep: step))
                    .resizable()
                    .scaledToFill()
            }
            .clipped()
    }

    private var headline: some View {
        Text("Finding ways to make them smile")
            .knotFont(Theme.Typography.loadingHeadline)
            .foregroundStyle(Theme.onBrandPrimary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var subline: some View {
        // The crossfade lives in a `ZStack`, matching `illustrationCard`. As a
        // direct `VStack` child both the outgoing and incoming phrase would
        // occupy layout for the whole 0.6s transition and the stack would
        // reflow — the drift `minHeight` alone cannot prevent, since two
        // stacked one-line phrases exceed it.
        ZStack {
            sublinePhrase(forStep: reduceMotion ? 0 : step)
                .id(reduceMotion ? 0 : step)
                .transition(.opacity)
        }
        // Reserve two lines so a longer phrase wrapping can't shift the
        // headline above it when the emphasis rotates.
        .frame(minHeight: 48, alignment: .top)
    }

    private func sublinePhrase(forStep step: Int) -> some View {
        // `body` (Regular 17) + `cta` (SemiBold 17) is the only same-size
        // Regular/SemiBold pair in the ramp, so the two runs share a baseline.
        (
            Text("Thinking about ")
                .knotFont(Theme.Typography.body)
                .foregroundStyle(Theme.onBrandMuted)
            + Text(Self.emphasis(forStep: step))
                .knotFont(Theme.Typography.cta)
                .foregroundStyle(Theme.onBrandPrimary)
        )
        .multilineTextAlignment(.center)
    }

    private var progressFooter: some View {
        VStack(spacing: Theme.Spacing.md) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Theme.onBrandTrack)

                    Capsule()
                        .fill(Theme.onBrandPrimary)
                        .frame(width: geo.size.width * progress)
                }
            }
            .frame(height: 3)
            // The ramp is sampled once per tick, so the bar interpolates
            // linearly between samples. A linear tween across a linear ramp is
            // indistinguishable from a continuous fill and costs one animation
            // instead of a per-frame body evaluation.
            .animation(.linear(duration: Self.stepInterval), value: progress)

            Text(Self.matchesLabel(progress: progress))
                .knotFont(Theme.Typography.label)
                .monospacedDigit()
                .foregroundStyle(Theme.onBrandMuted)
        }
    }

    // MARK: - Behavior

    /// Advances the ramp, and — unless Reduce Motion is on — the illustration
    /// and emphasis with it.
    private func tick() {
        elapsed += Self.stepInterval

        guard !reduceMotion else { return }
        withAnimation(.easeInOut(duration: 0.6)) {
            step += 1
        }
    }
}

// MARK: - Phase Resolution

extension RecommendationsLoadingView {

    /// Which surface the reveal should show, from the flags both hosts already
    /// track.
    ///
    /// The ordering is load-bearing and matches the branch chain it replaced:
    /// a load in flight wins over everything (there is no content to show yet),
    /// then an error, then the tap-through's missing-batch state, then empty,
    /// then loaded.
    ///
    /// `isPregeneratedRead` splits a running load into `.loading` vs `.silent`.
    /// The push tap-through only reads an already-stored batch — showing a
    /// ~25-second generation animation over a sub-second read both lied about
    /// the wait and flashed on screen before the entry modal covered it
    /// (Step 19.30).
    static func phase(
        isLoading: Bool,
        isPregeneratedRead: Bool,
        hasError: Bool,
        pregeneratedMissing: Bool,
        isEmpty: Bool
    ) -> RecommendationRevealPhase {
        if isLoading {
            return isPregeneratedRead ? .silent : .loading
        }
        if hasError { return .error }
        if pregeneratedMissing { return .missing }
        if isEmpty { return .empty }
        return .loaded
    }
}

// MARK: - Reveal Transition

extension RecommendationsLoadingView {

    /// How long the loading screen takes to recede. `App.tsx` runs the exit as
    /// a 420ms CSS transition and only swaps the phase on a matching
    /// `setTimeout(…, 420)`.
    nonisolated static let handoffExitDuration: TimeInterval = 0.42

    /// How long the picks take to arrive — the `screen-in` keyframe's 0.5s.
    nonisolated static let revealInDuration: TimeInterval = 0.5
}

extension AnyTransition {

    /// The picks arriving — the prototype's `screen-in` keyframe
    /// (`opacity 0 → 1`, `translateY(16px) → 0`, `scale(0.98) → 1`).
    ///
    /// **Sequential, not a crossfade**, which is the whole character of the
    /// prototype's hand-off. `App.tsx` fades, scales and blurs the loader out
    /// over 420ms and only *then* — on a `setTimeout` matched to that duration
    /// — mounts the results, which run their own 500ms `screen-in`. Overlapping
    /// them reads as a dissolve between two screens; sequencing them reads as
    /// one screen receding and another arriving, which is what makes the
    /// deleted celebration unnecessary. SwiftUI has no `setTimeout`, so the
    /// gap is a `.delay` matched to the recede the overlay is running
    /// underneath it.
    ///
    /// The curve is the prototype's, not its nearest SwiftUI preset:
    /// `(0.22, 1, 0.36, 1)` decelerates far harder than anything built in,
    /// which is what gives the picks their slight settle at the end.
    static var revealIn: AnyTransition {
        let arrive: AnyTransition = .opacity
            .combined(with: .offset(y: 16))
            .combined(with: .scale(scale: 0.98))

        return .asymmetric(
            insertion: arrive.animation(
                .timingCurve(
                    0.22, 1, 0.36, 1,
                    duration: RecommendationsLoadingView.revealInDuration
                )
                .delay(RecommendationsLoadingView.handoffExitDuration)
            ),
            removal: .opacity
        )
    }
}

// MARK: - Loading Overlay

/// Holds the loading screen above the reveal's content and animates its recede.
///
/// **Why this is an overlay rather than a branch of the phase switch.** The
/// obvious shape is `case .loading: RecommendationsLoadingView().transition(…)`
/// and letting a removal transition play the exit. That does not work here:
/// SwiftUI unmounts the branch immediately and the loader vanishes on the frame
/// the phase changes, with no exit at all.
///
/// This is not a guess. The hand-off was photographed at 25 frames across the
/// transition with the durations temporarily scaled 5×, so a 420ms exit became
/// 2.1s and any animation would have been impossible to miss. The loader was
/// already gone 0.57s in — and it stayed gone when the removal was reduced to a
/// plain `.opacity`, and when the navigation bar was pinned so its appearance
/// could not be disturbing the hierarchy. The removal simply never runs.
///
/// So the exit is expressed as ordinary animatable modifiers on a view that
/// stays mounted for its whole duration, driven by an explicit `withAnimation`.
/// Those always animate, because nothing structural is happening — only
/// `opacity`, `scaleEffect` and `blur` changing value.
private struct RecommendationLoadingOverlay: ViewModifier {

    let phase: RecommendationRevealPhase

    /// Mirrors `isMounted` out to the host, which needs it for chrome decisions.
    ///
    /// The navigation and tab bars must stay hidden for the *whole* recede, not
    /// just while the phase is `.loading` — otherwise a dark-plum inline title
    /// pops in over the coral surface for the 420ms it is fading out, which is
    /// exactly what the loading screen hides the bar to avoid.
    @Binding var isCovering: Bool

    /// Mounted for as long as the loader is visible, including its recede.
    @State private var isMounted: Bool

    /// Drives the recede. Animated, so all three modifiers interpolate.
    @State private var isReceding = false

    /// Guards the delayed unmount against a phase that returns to `.loading`
    /// mid-recede (a refresh). Without it that in-flight unmount would fire
    /// 420ms later and hide a loader that is supposed to be showing again.
    @State private var recedeGeneration = 0

    init(phase: RecommendationRevealPhase, isCovering: Binding<Bool>) {
        self.phase = phase
        self._isCovering = isCovering
        // Correct on the very first frame, before `onChange` has run — the
        // push tap-through starts at `.silent` and must not flash the loader.
        _isMounted = State(initialValue: phase == .loading)
    }

    func body(content: Content) -> some View {
        content
            .overlay {
                if isMounted {
                    RecommendationsLoadingView()
                        .opacity(isReceding ? 0 : 1)
                        .scaleEffect(isReceding ? 1.04 : 1)
                        .blur(radius: isReceding ? 4 : 0)
                        // Taps belong to the picks underneath the moment the
                        // recede starts.
                        .allowsHitTesting(!isReceding)
                }
            }
            .onChange(of: phase, initial: true) { _, newPhase in
                if newPhase == .loading {
                    recedeGeneration += 1
                    isReceding = false
                    isMounted = true
                    isCovering = true
                } else if isMounted, !isReceding {
                    let generation = recedeGeneration
                    withAnimation(
                        .timingCurve(
                            0.4, 0, 0.2, 1,
                            duration: RecommendationsLoadingView.handoffExitDuration
                        )
                    ) {
                        isReceding = true
                    }
                    Task { @MainActor in
                        try? await Task.sleep(
                            for: .seconds(RecommendationsLoadingView.handoffExitDuration)
                        )
                        guard generation == recedeGeneration else { return }
                        isMounted = false
                        isCovering = false
                    }
                } else if !isMounted {
                    // Never covered in the first place (`.silent`, or an error
                    // before the loader ever mounted).
                    isCovering = false
                }
            }
    }
}

extension View {
    /// Covers this content with `RecommendationsLoadingView` while `phase` is
    /// `.loading`, and plays the prototype's 420ms recede when it leaves.
    ///
    /// `isCovering` reports whether the loader is still on screen — true for the
    /// whole recede, not just while the phase is `.loading` — so the host can
    /// keep its navigation and tab chrome out of the way until the coral surface
    /// has actually gone.
    func recommendationLoadingOverlay(
        phase: RecommendationRevealPhase,
        isCovering: Binding<Bool>
    ) -> some View {
        modifier(RecommendationLoadingOverlay(phase: phase, isCovering: isCovering))
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Loading") {
    RecommendationsLoadingView()
}

#Preview("Loading — Reduce Motion") {
    RecommendationsLoadingView(reduceMotionOverride: true)
}
#endif
