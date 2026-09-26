# Knot — Project Rules

## Autonomous Feature Workflow (worktree → build → ship as a PR)

When a chat asks you to **build or change code** (a feature, bug fix, or refactor), run this
workflow end-to-end on your own — the user should not have to type any slash command:

1. **Isolate first.** *Before creating or editing any files*, if you are not already inside a
   git worktree, call the **`EnterWorktree`** tool to create and move into a fresh worktree on a
   new branch named from the request (e.g. `feat-recs-spacing`), branched from `origin/main`.
   All of your edits for this task must land in that worktree, not the main checkout.
   - **Repo layout note:** this repository is rooted at the parent `Cursor Projects/` folder, so
     a worktree's root is that parent and the Knot project sits at `<worktree>/Knot/`. After
     entering the worktree, **`cd` into the `Knot/` subdirectory** before doing project work.
2. **Build and test** the change, honoring the Testing Requirements and Memory Bank rules below.
   - **Running tests inside a worktree:** a fresh worktree has no Python venv. `.worktreeinclude`
     copies `Knot/backend/.env`, but for dependencies run the **main checkout's** interpreter
     against the worktree's code. From `<worktree>/Knot/backend`:
     ```bash
     MAIN=$(git worktree list --porcelain | sed -n 's/^worktree //p' | grep -v '/.claude/worktrees/' | head -1)
     "$MAIN/Knot/backend/venv/bin/python" -m pytest
     ```
     (Verified: packages come from the main venv, tests/code from the worktree.) iOS tests run
     via `xcodebuild test` as usual.
3. **Screenshot any UI change.** If the change touches iOS view code (anything under
   `iOS/Knot/**` that renders UI — *not* test files, `project.yml`, scripts, or Info.plists,
   and *not* a backend-only change), you MUST produce a screenshot so the reviewer can see it:
   - Edit the navigation slot in `iOS/KnotUITests/PRScreenshotTests.swift` (the
     `// >>> NAVIGATE TO THE CHANGED SCREEN HERE <<<` block) to drive the app to the affected
     screen, then run **`iOS/scripts/capture-ui-screenshot.sh`** from the `Knot/` directory.
   - That writes `docs/pr-screenshots/<branch>.png` (and regenerates the Xcode project so the
     test is included). The PNG is part of the change — `/ship` commits it like any other file.
   - If capture genuinely fails after the script's fallback, note the reason; `/ship-pr` will
     record it in the PR instead of an image. Do not block shipping on a flaky simulator.
   - Backend-only or non-visual changes skip this step entirely.
4. **Ship automatically.** When the change works, invoke the **`/ship-pr`** skill *without being
   asked*. It runs `/code-review` and auto-fixes safe findings, commits with the project's
   message conventions, pushes the branch, embeds the screenshot in the PR body (for UI
   changes), and opens a PR.
   - **Testing inside `/ship-pr`:** its pre-review gate uses the targeted tests, which already
     passed while building. The **one** full-suite run happens after the review fixes, right
     before the commit (see Testing Requirements).
5. **Report the PR URL** and stop. **Never merge** — the user is the final reviewer/merger.

**Do NOT apply this workflow to read-only or question-only chats** (e.g. "how does X work?",
"explain this module"). Those need no worktree, no commit, and no PR — answer normally.

The mandatory Memory Bank read below still happens first, before any of the above.

## Memory Bank (Read First)

Before starting ANY work, read the memory bank files in `memory-bank/`:

1. `memory-bank/progress.md` — Implementation history and current status
2. `memory-bank/architecture.md` — Full architecture reference for all files and modules
3. `memory-bank/IMPLEMENTATION_PLAN.md` — Step-by-step build roadmap
4. `memory-bank/PRD.md` — Product requirements and personas
5. `memory-bank/techstack.md` — Technology stack decisions

This is mandatory for every new session or agent task. Do not skip this step.

**Stop being lazy you lazy bot.** Read every memory-bank file all the way through. If a file is "too big" to read in one Read call, chunk-read it with offset/limit until the entire file is in context. Partial reads, skimming, or "I have enough context" shortcuts are not acceptable. Read the whole thing, every time, before doing any work.

## Testing Requirements

Every new feature must include tests before it is considered complete:

- **Backend (Python/FastAPI):** Write tests in `backend/tests/`. The full suite is
  `cd backend && python -m pytest`.
- **iOS (Swift/SwiftUI):** Write tests in `iOS/KnotTests/`. iOS tests are split into two test
  plans: the **Unit** plan (`KnotTests` only) is the default, so a bare
  `xcodebuild test -scheme Knot` runs unit tests only. `-testPlan Full` runs unit **and** UI
  (`KnotUITests`).

**When to run what:**

- **While building:** run only the tests for the code being changed. That takes about a minute.
  - iOS: `xcodebuild test -scheme Knot -only-testing:KnotTests/<TestClass>`, with one
    `-only-testing:` per class. The screenshot script already runs only `PRScreenshotTests`.
  - Backend: `python -m pytest tests/<test_file>.py`
- **Once at the end:** run the full suite after all fixes, including `/ship-pr`'s review fixes,
  right before committing. Use `-testPlan Full` for iOS and the whole `pytest` run for the
  backend. That single run is the safety net, so don't re-run the full suite after each fix
  along the way.

A feature is not done until all new and existing tests pass.

## Icons (MUI only)

Every icon in the iOS app is an **MUI** (`@mui/icons-material`) glyph drawn through the
`KnotIcon` enum (`iOS/Knot/Components/UI/KnotIcon.swift`) — `KnotIconView(.homeOutlined, size: 20)`,
or `KnotIcon.x.image` where a raw `Image` is required (e.g. a `Label`'s icon).

- **Never use Lucide.** Never use SF Symbols either (`Image(systemName:)`, `systemImage:`,
  `.symbolVariant`). `IconPolicyTests` fails the suite if either comes back. The one allowlisted
  exception is Apple's `apple.logo` on "Continue with Apple" (marked
  `// icon-policy: apple-logo-exception`), kept for App Review.
- **Adding an icon:** add a case whose raw value is the exact MUI component name, run
  `node iOS/scripts/generate-mui-icons.mjs` (from `Knot/`), and commit the new
  `Assets.xcassets/MUI/<Name>.imageset`. `KnotIconTests` fails if a case has no asset.
- **Style:** Outlined by default; the Filled variant only for an "on" state (selected tab, saved
  bookmark, checked row/radio or a met selection count, chosen star, the "primary set" marker,
  Delivered/Failed status badge).
- **Naming trap:** MUI's `FavoriteOutlined` / `BookmarkOutlined` / `StarOutlined` are *solid*.
  The outlines are `FavoriteBorder` / `BookmarkBorder` / `StarBorder`.

## Documentation Updates

After completing a new feature, update the following documentation:

### progress.md
- Add a new `### Step X.Y` entry under `## Completed Steps`
- Insert it BEFORE `## Next Steps` (never append to end of file)
- Follow the existing format: Step title with checkmark, date, status, and detailed description
- Strict section order: `## Completed Steps` → `## Next Steps` → `## Notes for Future Developers`

### architecture.md
- Update relevant sections to reflect any new or modified files, modules, or patterns
- Follow the existing table/description format
