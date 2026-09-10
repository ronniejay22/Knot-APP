//
//  RecommendationsLoadingViewTests.swift
//  KnotTests
//
//  Step 19.50: Covers the new recommendation loading screen and the shared
//  reveal-phase resolver that replaced the branch chain duplicated across
//  `RecommendationsView` and `OnboardingCompletionView`.
//
//  The rotation and counter logic is deliberately pure and static so it can be
//  tested without rendering the view or waiting on its 2.5-second timer — the
//  previous `ForYouLoadingView` and `ForYouClimaxView` had no tests at all
//  because every decision was buried in `@State` and `DispatchQueue.asyncAfter`.
//

import SwiftUI
import XCTest
@testable import Knot

@MainActor
final class RecommendationsLoadingHelperTests: XCTestCase {

    // MARK: - Illustration rotation

    /// Each of the nine illustrations is reached, in order, inside one cycle.
    func testIllustrationNamesCoverTheWholeSetInOrder() {
        let names = (0..<9).map { RecommendationsLoadingView.illustrationName(forStep: $0) }
        XCTAssertEqual(names, (0..<9).map { "LoadingIllustrations/loading-\($0)" })
        XCTAssertEqual(Set(names).count, 9, "Every step in a cycle must map to a distinct asset")
    }

    /// A real generation runs long enough to wrap the set several times, so
    /// step 9 must land back on the first illustration rather than off the end.
    func testIllustrationNameWrapsPastTheEndOfTheSet() {
        XCTAssertEqual(
            RecommendationsLoadingView.illustrationName(forStep: 9),
            RecommendationsLoadingView.illustrationName(forStep: 0)
        )
        XCTAssertEqual(
            RecommendationsLoadingView.illustrationName(forStep: 22),
            RecommendationsLoadingView.illustrationName(forStep: 4)
        )
    }

    /// The crossfade renders `step - 1` underneath the current image, so step 0
    /// asks for step -1. Swift's `%` keeps the sign of the dividend, so a naive
    /// modulo would index out of bounds here.
    func testIllustrationNameHandlesNegativeSteps() {
        XCTAssertEqual(
            RecommendationsLoadingView.illustrationName(forStep: -1),
            "LoadingIllustrations/loading-8"
        )
    }

    // MARK: - Emphasis rotation

    func testEmphasisCoversEveryPhraseInOrder() {
        let phrases = (0..<4).map { RecommendationsLoadingView.emphasis(forStep: $0) }
        XCTAssertEqual(
            phrases,
            ["the things they love", "their taste", "the little moments", "their favorites"]
        )
    }

    func testEmphasisWrapsAndHandlesNegativeSteps() {
        XCTAssertEqual(
            RecommendationsLoadingView.emphasis(forStep: 4),
            RecommendationsLoadingView.emphasis(forStep: 0)
        )
        XCTAssertEqual(
            RecommendationsLoadingView.emphasis(forStep: -1),
            "their favorites"
        )
    }

    /// The copy is second person with no gendered pronoun — the rule every
    /// other partner-facing string in the app follows, since the vault never
    /// collects a gender.
    ///
    /// Matched on **word boundaries**, not substrings. A plain `contains` finds
    /// "he" inside "t*he* things" and "her" inside "ot*her*" — the same trap
    /// `occasion_category`'s name matcher had to be `\b`-anchored for when
    /// "eid" matched inside "Deidre's Birthday" (Step 19.25).
    func testEmphasisCopyUsesNoGenderedPronoun() {
        let pronouns = try! NSRegularExpression(
            pattern: #"\b(he|him|his|she|her|hers)\b"#,
            options: .caseInsensitive
        )

        for step in 0..<4 {
            let phrase = RecommendationsLoadingView.emphasis(forStep: step)
            let range = NSRange(phrase.startIndex..., in: phrase)
            XCTAssertNil(
                pronouns.firstMatch(in: phrase, range: range),
                "\"\(phrase)\" leaks a gendered pronoun; the app never collects a gender"
            )
        }
    }

    /// Guards the guard: the matcher above must actually catch a real pronoun,
    /// or it would pass on any copy at all.
    func testGenderedPronounMatcherCatchesARealPronoun() {
        let pronouns = try! NSRegularExpression(
            pattern: #"\b(he|him|his|she|her|hers)\b"#,
            options: .caseInsensitive
        )
        let leaky = "her wishlist and past gifts"
        let range = NSRange(leaky.startIndex..., in: leaky)
        XCTAssertNotNil(pronouns.firstMatch(in: leaky, range: range))
    }

    // MARK: - Match counter

    /// Nothing has been claimed before the bar moves.
    func testNoMatchesClaimedBeforeAnyProgress() {
        XCTAssertEqual(RecommendationsLoadingView.matchesFound(progress: 0), 0)
    }

    /// The counter never exceeds the three cards the pipeline actually returns
    /// (PRD F2), including at and beyond a full bar.
    func testMatchesClampToTheThreeCardsThePipelineReturns() {
        XCTAssertEqual(RecommendationsLoadingView.matchesFound(progress: 0.95), 3)
        XCTAssertEqual(RecommendationsLoadingView.matchesFound(progress: 1.0), 3)
        XCTAssertEqual(RecommendationsLoadingView.matchesFound(progress: 2.0), 3)
    }

    /// The third match is claimed near the *end* of the ramp, not two-thirds
    /// through it.
    ///
    /// The first implementation was `Int(progress * 3) + 1`, which reached
    /// "3 of 3 matches found" at progress 2/3 — about 19.6s of a 28s ramp — and
    /// then sat there while the bar visibly crawled on. A counter that claims
    /// everything is found while the wait continues is a worse overclaim than
    /// the bar it sits under.
    func testAllThreeAreNotClaimedUntilNearTheEndOfTheRamp() {
        let ceiling: CGFloat = 0.95
        // Two-thirds through the ramp — the point the old formula claimed all
        // three.
        XCTAssertLessThan(
            RecommendationsLoadingView.matchesFound(progress: ceiling * 0.67),
            3,
            "All three claimed two-thirds through the wait"
        )
        // Still not all claimed at four-fifths.
        XCTAssertLessThan(RecommendationsLoadingView.matchesFound(progress: ceiling * 0.80), 3)
        // Claimed by the time the bar is essentially full.
        XCTAssertEqual(RecommendationsLoadingView.matchesFound(progress: ceiling * 0.95), 3)
    }

    /// The counter never sits at 0 while the bar is visibly moving — the first
    /// match lands early in the ramp.
    func testFirstMatchIsClaimedEarly() {
        XCTAssertEqual(RecommendationsLoadingView.matchesFound(progress: 0.95 * 0.10), 1)
    }

    /// The count only ever goes up. A counter that ticked backwards mid-wait
    /// would read as the app losing results it had already claimed to find.
    func testMatchesAreMonotonicAcrossTheWholeRamp() {
        var previous = 0
        for tick in 0...100 {
            let found = RecommendationsLoadingView.matchesFound(progress: CGFloat(tick) / 100)
            XCTAssertGreaterThanOrEqual(found, previous, "Counter went backwards at \(tick)%")
            XCTAssertLessThanOrEqual(found, 3)
            previous = found
        }
        XCTAssertEqual(previous, 3, "The bar must finish claiming all three")
    }

    /// Pins the copy so the layout is not the only thing holding it.
    func testMatchesLabelReadsAsAFractionOfThree() {
        XCTAssertEqual(RecommendationsLoadingView.matchesLabel(progress: 0), "0 of 3 matches found")
        XCTAssertEqual(RecommendationsLoadingView.matchesLabel(progress: 1.0), "3 of 3 matches found")
    }
}

// MARK: - Phase resolution

@MainActor
final class RecommendationRevealPhaseTests: XCTestCase {

    private func phase(
        isLoading: Bool = false,
        isPregeneratedRead: Bool = false,
        hasError: Bool = false,
        pregeneratedMissing: Bool = false,
        isEmpty: Bool = false
    ) -> RecommendationRevealPhase {
        RecommendationsLoadingView.phase(
            isLoading: isLoading,
            isPregeneratedRead: isPregeneratedRead,
            hasError: hasError,
            pregeneratedMissing: pregeneratedMissing,
            isEmpty: isEmpty
        )
    }

    func testGenerationShowsTheLoadingScreen() {
        XCTAssertEqual(phase(isLoading: true, isEmpty: true), .loading)
    }

    /// A sub-second read of an already-stored batch shows nothing — the guard
    /// that stopped the push tap-through flashing a ~25-second generation
    /// screen over an instant fetch (Step 19.30).
    func testPregeneratedReadIsSilent() {
        XCTAssertEqual(phase(isLoading: true, isPregeneratedRead: true, isEmpty: true), .silent)
    }

    /// A load in flight outranks every terminal signal — there is no content to
    /// show yet, so a stale error or an empty array must not win.
    func testLoadingOutranksTerminalSignals() {
        XCTAssertEqual(
            phase(isLoading: true, hasError: true, pregeneratedMissing: true, isEmpty: true),
            .loading
        )
    }

    func testErrorOutranksMissingAndEmpty() {
        XCTAssertEqual(phase(hasError: true, pregeneratedMissing: true, isEmpty: true), .error)
    }

    func testMissingOutranksEmpty() {
        XCTAssertEqual(phase(pregeneratedMissing: true, isEmpty: true), .missing)
    }

    func testEmptyWhenNothingCameBack() {
        XCTAssertEqual(phase(isEmpty: true), .empty)
    }

    func testLoadedWhenPicksArePresent() {
        XCTAssertEqual(phase(isEmpty: false), .loaded)
    }

    /// The frame before `.task` has run must not resolve to `.empty`.
    ///
    /// `RecommendationsView` feeds `awaitingFirstLoad` into `isLoading` for
    /// exactly this: with the phase change now animated, a one-frame `.empty`
    /// became a visible 0.42s crossfade of the "Ready to find a gift?" CTA
    /// ahead of the loader.
    func testAwaitingFirstLoadResolvesToLoadingNotEmpty() {
        XCTAssertEqual(phase(isLoading: true, isEmpty: true), .loading)
        XCTAssertNotEqual(phase(isLoading: true, isEmpty: true), .empty)
    }

    /// And the tap-through's first frame must be `.silent`, not a flash of the
    /// coral generation screen under the entry modal (Step 19.30). That is why
    /// `isPregeneratedRead` is seeded from `preferPregenerated` in `init`.
    func testAwaitingFirstLoadStaysSilentForAPregeneratedRead() {
        XCTAssertEqual(
            phase(isLoading: true, isPregeneratedRead: true, isEmpty: true),
            .silent
        )
    }

    /// The celebration is gone: a finished load resolves straight to `.loaded`,
    /// with no intermediate phase between the wait ending and the picks.
    func testNoPhaseSitsBetweenLoadingAndLoaded() {
        XCTAssertEqual(phase(isLoading: true, isEmpty: true), .loading)
        XCTAssertEqual(phase(isLoading: false, isEmpty: false), .loaded)
    }
}

// MARK: - Rendering

@MainActor
final class RecommendationsLoadingViewRenderingTests: XCTestCase {

    func testLoadingViewRenders() {
        let host = UIHostingController(rootView: RecommendationsLoadingView())
        host.loadViewIfNeeded()
        XCTAssertNotNil(host.view)
    }

    /// Reduce Motion pins the illustration and the emphasis to the first step
    /// and skips the crossfade, mirroring `AnimatedCoupleIllustration`.
    ///
    /// Reached through `reduceMotionOverride` because
    /// `\.accessibilityReduceMotion` is read-only and cannot be set on an
    /// environment from a test.
    func testLoadingViewRendersUnderReduceMotion() {
        let host = UIHostingController(
            rootView: RecommendationsLoadingView(reduceMotionOverride: true)
        )
        host.loadViewIfNeeded()
        XCTAssertNotNil(host.view)
    }

    /// Production call sites pass nothing and defer to the system setting.
    func testReduceMotionDefaultsToTheSystemSetting() {
        XCTAssertNil(RecommendationsLoadingView().reduceMotionOverride)
    }

    /// Every illustration the rotation can reach must actually be in the
    /// catalog. A missing asset renders as a blank card at runtime with no
    /// build error — exactly the silent failure `OccasionCopy.illustrationName`
    /// bundle-checks against.
    func testEveryIllustrationIsBundled() {
        for step in 0..<9 {
            let name = RecommendationsLoadingView.illustrationName(forStep: step)
            XCTAssertNotNil(UIImage(named: name), "Missing asset: \(name)")
        }
    }

    /// The brand header's logo is a real asset, not a silently-empty `Image`.
    func testBrandLogoIsBundled() {
        XCTAssertNotNil(UIImage(named: "BrandLogo"))
    }
}
