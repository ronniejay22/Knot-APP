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

    /// Each of the four illustrations is reached, in order, inside one cycle.
    func testIllustrationNamesCoverTheWholeSetInOrder() {
        let names = (0..<4).map { RecommendationsLoadingView.illustrationName(forStep: $0) }
        XCTAssertEqual(
            names,
            [
                "LoadingIllustrations/loading-4",
                "LoadingIllustrations/loading-1",
                "LoadingIllustrations/loading-7",
                "LoadingIllustrations/loading-3",
            ]
        )
        XCTAssertEqual(Set(names).count, 4, "Every step in a cycle must map to a distinct asset")
    }

    /// A real generation runs long enough to wrap the set several times, so
    /// step 4 must land back on the first illustration rather than off the end.
    func testIllustrationNameWrapsPastTheEndOfTheSet() {
        XCTAssertEqual(
            RecommendationsLoadingView.illustrationName(forStep: 4),
            RecommendationsLoadingView.illustrationName(forStep: 0)
        )
        XCTAssertEqual(
            RecommendationsLoadingView.illustrationName(forStep: 22),
            RecommendationsLoadingView.illustrationName(forStep: 2)
        )
    }

    /// Swift's `%` keeps the sign of the dividend, so a naive modulo would
    /// index out of bounds on a negative step.
    ///
    /// Production never passes one — `step` starts at 0 and only increments,
    /// and the crossfade's underneath-layer (`step - 1`) is guarded by
    /// `step > 0`. This pins the helper as total anyway, so a future caller
    /// that does reach behind 0 gets a wrap rather than a crash.
    func testIllustrationNameHandlesNegativeSteps() {
        XCTAssertEqual(
            RecommendationsLoadingView.illustrationName(forStep: -1),
            "LoadingIllustrations/loading-3"
        )
    }

    // MARK: - Illustration ↔ phrase pairing

    /// The whole point of the rotation table: a phrase always arrives with its
    /// own picture.
    ///
    /// The illustration and the phrase advance on the same `step`, so this only
    /// holds while they are paired 1:1. They were previously two lists of
    /// different lengths (nine illustrations against four phrases), and because
    /// 9 and 4 do not divide, the pairing drifted — "their taste" got a
    /// different picture every time it came round. Re-splitting them into
    /// independent lists is what this test exists to catch.
    func testEachPhraseAlwaysArrivesWithTheSameIllustration() {
        var seen: [String: String] = [:]

        // Several cycles, and negative steps too, since the crossfade reaches
        // behind step 0.
        for step in -8...20 {
            let phrase = RecommendationsLoadingView.emphasis(forStep: step)
            let illustration = RecommendationsLoadingView.illustrationName(forStep: step)

            if let expected = seen[phrase] {
                XCTAssertEqual(
                    illustration,
                    expected,
                    "\"\(phrase)\" arrived with \(illustration) at step \(step) but \(expected) earlier — the pairing has drifted"
                )
            } else {
                seen[phrase] = illustration
            }
        }

        XCTAssertEqual(seen.count, 4, "Every phrase should have been reached")
        XCTAssertEqual(Set(seen.values).count, 4, "Two phrases must not share an illustration")
    }

    /// Both halves wrap on the same period, which is what keeps them in step.
    func testIllustrationAndPhraseShareOneCycleLength() {
        for step in -4...12 {
            XCTAssertEqual(
                RecommendationsLoadingView.illustrationName(forStep: step),
                RecommendationsLoadingView.illustrationName(forStep: step + 4),
                "Illustration cycle is not 4 steps long at step \(step)"
            )
            XCTAssertEqual(
                RecommendationsLoadingView.emphasis(forStep: step),
                RecommendationsLoadingView.emphasis(forStep: step + 4),
                "Phrase cycle is not 4 steps long at step \(step)"
            )
        }
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
        for step in 0..<4 {
            let name = RecommendationsLoadingView.illustrationName(forStep: step)
            XCTAssertNotNil(UIImage(named: name), "Missing asset: \(name)")
        }
    }

    /// The brand header's logo is a real asset, not a silently-empty `Image`.
    func testBrandLogoIsBundled() {
        XCTAssertNotNil(UIImage(named: "BrandLogo"))
    }
}

// MARK: - Chrome

/// The loading screen is a full-bleed brand surface, so both the navigation bar
/// above it and `MainTabView`'s `KnotTabBar` below it have to get out of the
/// way — and both have to come back once it is gone.
///
/// These shipped broken once. The navigation bar stayed visible because
/// `ForYouView` wrapped the pushed destination in an unconditional
/// `.toolbar(.visible, for: .navigationBar)` that outranked the declaration
/// `RecommendationsView` made four levels deeper inside a ZStack and a switch.
/// The tab bar stayed visible because nothing had ever asked it to leave —
/// which additionally hid the progress bar behind it, since `safeAreaInset`
/// does not propagate through a `navigationDestination` push.
///
/// Both gates key on **whether the loader is still covering the screen**, not on
/// the phase. The coral surface outlives `.loading` by the 420ms of its recede,
/// and restoring the chrome at the phase change pops a dark-plum inline title
/// over coral for that whole time.
@MainActor
final class RecommendationsChromeTests: XCTestCase {

    // MARK: Navigation bar

    func testNavigationBarIsHiddenWhileTheLoaderCovers() {
        XCTAssertEqual(
            RecommendationsView.navigationBarVisibility(isModal: false, isCoveredByLoader: true),
            .hidden
        )
    }

    func testNavigationBarReturnsOnceTheLoaderHasGone() {
        XCTAssertEqual(
            RecommendationsView.navigationBarVisibility(isModal: false, isCoveredByLoader: false),
            .visible
        )
    }

    /// Inside a full-screen cover the bar carries
    /// `MilestoneRecommendationsCoverView`'s X — the only way out of a
    /// ~25-second run. Hiding it there strands the user.
    func testNavigationBarStaysVisibleInAModalEvenWhileCovered() {
        for covered in [true, false] {
            XCTAssertEqual(
                RecommendationsView.navigationBarVisibility(isModal: true, isCoveredByLoader: covered),
                .visible,
                "The modal host must never hide its bar (covered: \(covered))"
            )
        }
    }

    // MARK: Tab bar

    func testTabBarIsHiddenWhileTheLoaderCovers() {
        XCTAssertTrue(
            RecommendationsView.shouldHideTabBar(isModal: false, isCoveredByLoader: true)
        )
    }

    /// A tab bar left hidden would strand the whole app with no navigation and
    /// no way to restore it, so "not covered" must always restore it.
    func testTabBarReturnsOnceTheLoaderHasGone() {
        XCTAssertFalse(
            RecommendationsView.shouldHideTabBar(isModal: false, isCoveredByLoader: false)
        )
    }

    /// A `fullScreenCover` inherits the presenting view's environment, so the
    /// modal host can reach `AppChrome` even though its tab bar is already
    /// covered. It must decline to, or the bar animates out behind the cover
    /// and back in on dismissal for no reason.
    func testModalHostNeverTouchesTheTabBar() {
        for covered in [true, false] {
            XCTAssertFalse(
                RecommendationsView.shouldHideTabBar(isModal: true, isCoveredByLoader: covered),
                "The modal host must not drive the tab bar (covered: \(covered))"
            )
        }
    }

    // MARK: AppChrome

    func testAppChromeStartsVisible() {
        XCTAssertFalse(AppChrome().isTabBarHidden)
    }

    func testAppChromeRoundTrips() {
        let chrome = AppChrome()
        chrome.isTabBarHidden = true
        XCTAssertTrue(chrome.isTabBarHidden)
        chrome.isTabBarHidden = false
        XCTAssertFalse(chrome.isTabBarHidden)
    }
}

// MARK: - Hand-off timing

/// The hand-off is a port of the prototype's `App.tsx` + `index.css`, and its
/// two halves are **sequential**: the loader recedes over 420ms, and only then
/// do the picks run their 500ms `screen-in`. Overlapping them reads as a
/// dissolve between two screens rather than one receding and another arriving.
@MainActor
final class RecommendationHandoffTimingTests: XCTestCase {

    /// `App.tsx` runs a 420ms CSS transition and swaps the phase on a matching
    /// `setTimeout(…, 420)`.
    func testExitDurationMatchesThePrototype() {
        XCTAssertEqual(RecommendationsLoadingView.handoffExitDuration, 0.42, accuracy: 0.0001)
    }

    /// The `screen-in` keyframe is `0.5s`.
    func testRevealDurationMatchesThePrototype() {
        XCTAssertEqual(RecommendationsLoadingView.revealInDuration, 0.5, accuracy: 0.0001)
    }

    /// The picks must not begin arriving before the loader has finished
    /// leaving. `.revealIn` delays its insertion by exactly the recede's
    /// duration, so changing one without the other either reopens the crossfade
    /// this replaced or leaves a blank screen between the two halves.
    func testTheRevealWaitsForTheFullRecede() {
        XCTAssertGreaterThan(RecommendationsLoadingView.handoffExitDuration, 0)
        XCTAssertGreaterThan(RecommendationsLoadingView.revealInDuration, 0)
        XCTAssertEqual(
            RecommendationsLoadingView.handoffExitDuration,
            0.42,
            accuracy: 0.0001,
            "`.revealIn` delays its insertion by this exact value — keep them in step."
        )
    }
}
