---
description: Produce the PR screenshot for an iOS UI change — reuse or scaffold a `UITestScreenshotHarness` key + standalone harness view, point the `PRScreenshotTests` navigation slot at it, and run capture-ui-screenshot.sh. Use when a change touches iOS view code and needs the CLAUDE.md-mandated screenshot. Handles the multi-file harness edits that /ship-pr's capture step does not.
argument-hint: [screen name or harness key]
---

# /screenshot-screen

Knot's Autonomous Feature Workflow requires a screenshot for any change that touches rendering
iOS view code under `iOS/Knot/**` (CLAUDE.md → "Screenshot any UI change"). `/ship-pr` *runs*
the capture and embeds the PNG, but the fiddly part it doesn't do is getting the app to the
changed screen: most screens sit behind a real authenticated Supabase session, so a cold UI
test can't reach them. This skill does that setup, then captures.

Skip entirely for backend-only or non-visual changes (test files, `project.yml`, scripts,
Info.plists). Run from the `Knot/` directory.

## How the seam works (read once)

- `iOS/Knot/App/UITestScreenshotHarness.swift` — a `#if DEBUG` enum. `rootView(for:)` is a
  `switch` on a string key; each `case "<key>"` returns a private `*ScreenshotHarnessView` that
  renders one screen standalone with seeded state. `ContentView` checks
  `UITestScreenshotHarness.activeScreen` first and renders the harness when the app is launched
  with `-uiTestScreenshot <key>`. Release builds compile a stub, so it never ships.
- `iOS/KnotUITests/PRScreenshotTests.swift` — one UI test. The `// >>> NAVIGATE TO THE CHANGED
  SCREEN HERE <<<` slot sets the launch argument and waits for a screen-specific element. The
  captured `XCTAttachment` MUST stay named `"PR Screenshot"` — the capture script looks it up by
  that exact name.
- `iOS/scripts/capture-ui-screenshot.sh` — regenerates the project, runs the test under
  `-testPlan Full` (the default Unit plan omits `KnotUITests`), extracts the attachment, and
  writes `docs/pr-screenshots/<branch>.png`.

## Phase 1 — Reuse an existing key if one fits

`grep -n 'case "' iOS/Knot/App/UITestScreenshotHarness.swift` to list existing keys (e.g.
`interests`, `recDetail`, `savedMoments`, `settings`, `onboardingPaywall`, `forYouTimeline`,
`spotlightFallback`). If one already renders the screen your change affects, reuse it — jump to
Phase 3.

## Phase 2 — Scaffold a new harness key

Add both pieces inside the `#if DEBUG` block of `UITestScreenshotHarness.swift`:

1. A new `case "<key>":` in the `rootView(for:)` switch (keep `default: EmptyView()` last),
   returning a new private view.
2. A private `struct <Name>ScreenshotHarnessView: View` that renders the changed screen with
   representative state, bypassing auth/onboarding gating. Match the existing harness views:
   - Onboarding/interests-style screens: build an `OnboardingViewModel`, set fields
     (`vm.partnerName = "Alex"`, preselected arrays), inject via `.environment(viewModel)`, and
     `.background(Theme.backgroundGradient.ignoresSafeArea())`.
   - SwiftData-backed screens (Saved, etc.): create an isolated in-memory
     `ModelContainer(for: <Model>.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))`,
     insert sample rows, and `.modelContainer(container)`.
   - Subscription/paywall states: `SubscriptionManager(debugSubscribed: true)` (the DEBUG-only
     init) to force an entitlement without a live StoreKit transaction.
   - Recommendation surfaces: seed with `PreviewRecommendations.decode(...)` /
     `PreviewRecommendations.bookablePurchasable`.
   Annotate the view `@MainActor` if it constructs a `@MainActor` view-model or a
   `ModelContainer`. Mark the view `#if DEBUG`-only (the whole enum already is).

Choose a short camelCase `<key>` that names the screen/state (e.g. `onboardingPaywallSubscribed`).

## Phase 3 — Point the test at the key

Edit the navigation slot in `iOS/KnotUITests/PRScreenshotTests.swift`:

```swift
// >>> NAVIGATE TO THE CHANGED SCREEN HERE <<<
app.launchArguments += ["-uiTestScreenshot", "<key>"]
app.launch()

_ = app.wait(for: .runningForeground, timeout: 10)
dismissSystemAlerts()
// Wait for something only the changed screen shows, so the shot is fully rendered:
_ = app.staticTexts["<a label unique to this screen>"].waitForExistence(timeout: 10)
```

Leave the attachment named `"PR Screenshot"` and `.lifetime = .keepAlways`. Update the slot's
comment to say which screen/state it now captures.

## Phase 4 — Capture

From the `Knot/` directory:

```bash
iOS/scripts/capture-ui-screenshot.sh
```

It regenerates the Xcode project (so the new/edited test + harness compile in), runs the test on
a picked simulator under the Full plan, and writes `docs/pr-screenshots/<branch>.png`. The PNG is
part of the change — `/ship-pr` commits it and embeds it in the PR body.

## Phase 5 — Verify / degrade gracefully

- Confirm `docs/pr-screenshots/<branch>.png` exists and actually shows the changed screen (open
  it / Read it).
- If capture genuinely fails after the script's `simctl` fallback (flaky simulator), note the
  one-line reason — `/ship-pr` records a "no screenshot" note in the PR instead of an image.
  Don't block shipping on a flaky simulator.
- The harness view + test-slot edits are Swift under `iOS/Knot/**` and `iOS/KnotUITests/**`, but
  they're a DEBUG-only test seam — they don't themselves need a screenshot; the PNG is the
  artifact.
