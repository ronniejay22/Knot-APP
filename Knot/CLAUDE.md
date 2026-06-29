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
   - **Offline mode (skip live-service integration tests):** `.worktreeinclude` copies the real
     `backend/.env`, so a plain `pytest` runs the credential-gated integration tests against live
     Supabase / Claude / Firecrawl / QStash and can hang on network calls. To run only the fast,
     network-free unit tests, pass `--offline` (or export `KNOT_OFFLINE_TESTS=1`):
     ```bash
     "$MAIN/Knot/backend/venv/bin/python" -m pytest --offline
     ```
     This blanks the external credentials (see `backend/conftest.py`) so every `requires_*`
     guard skips its integration tests. Prefer this for quick iteration; run the full live suite
     before shipping when your change touches an integration path.
3. **Ship automatically.** When the change works, invoke the **`/ship-pr`** skill *without being
   asked*. It runs the test suite, runs `/code-review` and auto-fixes safe findings, commits with
   the project's message conventions, pushes the branch, and opens a PR.
4. **Report the PR URL** and stop. **Never merge** — the user is the final reviewer/merger.

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

- **Backend (Python/FastAPI):** Write tests in `backend/tests/` and run `cd backend && python -m pytest`
- **iOS (Swift/SwiftUI):** Write tests in `iOS/KnotTests/` and run via `xcodebuild test` or Xcode

A feature is not done until all new and existing tests pass.

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
