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

    /// The nine illustrations, cycled in order and wrapped.
    /// `LoadingIllustrations/` is a namespaced asset folder, so the namespace
    /// prefix is required in the lookup.
    private static let illustrationCount = 9

    /// The rotating emphasis in "Thinking about ___". Verbatim from the
    /// prototype — second person, no gendered pronoun, which is the rule every
    /// other partner-facing string in the app follows.
    private static let emphases = [
        "the things they love",
        "their taste",
        "the little moments",
        "their favorites",
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

    /// The asset name for a given step, wrapping over the illustration set.
    /// Negative steps wrap too, so a caller can never index out of bounds.
    static func illustrationName(forStep step: Int) -> String {
        let index = ((step % illustrationCount) + illustrationCount) % illustrationCount
        return "LoadingIllustrations/loading-\(index)"
    }

    /// The emphasis phrase for a given step, wrapping over the phrase set.
    static func emphasis(forStep step: Int) -> String {
        let index = ((step % emphases.count) + emphases.count) % emphases.count
        return emphases[index]
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

extension AnyTransition {

    /// How the loading screen leaves and the picks arrive, replacing the
    /// celebration that used to sit between them.
    ///
    /// Ported from the prototype's `App.tsx`: the loader scales up slightly and
    /// blurs as it fades, and the results rise into place. The blur is what
    /// sells it as a hand-off rather than a cut — the brand surface recedes
    /// instead of disappearing.
    static var loadingHandoff: AnyTransition {
        .asymmetric(
            insertion: .opacity,
            removal: .opacity.combined(with: .scale(scale: 1.04)).combined(with: .blurOut)
        )
    }

    /// The picks arriving.
    static var revealIn: AnyTransition {
        .opacity.combined(with: .offset(y: 16)).combined(with: .scale(scale: 0.98))
    }

    private static var blurOut: AnyTransition {
        .modifier(active: BlurModifier(radius: 4), identity: BlurModifier(radius: 0))
    }
}

private struct BlurModifier: ViewModifier {
    let radius: CGFloat

    func body(content: Content) -> some View {
        content.blur(radius: radius)
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
