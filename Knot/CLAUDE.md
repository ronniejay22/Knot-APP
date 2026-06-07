# Knot — Project Rules

## Memory Bank (Read First)

Before starting ANY work, read the memory bank files in `memory-bank/`:

1. `memory-bank/progress.md` — Implementation history and current status
2. `memory-bank/architecture.md` — Full architecture reference for all files and modules
3. `memory-bank/IMPLEMENTATION_PLAN.md` — Step-by-step build roadmap
4. `memory-bank/PRD.md` — Product requirements and personas
5. `memory-bank/techstack.md` — Technology stack decisions

This is mandatory for every new session or agent task. Do not skip this step.

**Stop being lazy you lazy bot.** Read every memory-bank file all the way through. If a file is "too big" to read in one Read call, chunk-read it with offset/limit until the entire file is in context. Partial reads, skimming, or "I have enough context" shortcuts are not acceptable. Read the whole thing, every time, before doing any work.

## Feature Worktrees

When a session's task is to **build or implement a new feature** (not a question, review, discussion, small fix, or continuation of in-progress work), isolate it in its own git worktree + branch so parallel feature chats never collide — especially on the iOS `project.pbxproj`, which conflicts whenever two branches add files.

This authorizes the EnterWorktree tool for that case. Before making any edits:

1. Call `EnterWorktree` with `name="<kebab-feature-name>"` (no slashes or `feature/` prefix). The tool sanitizes the name and creates branch `worktree-<name>` + a worktree under the repo's `.claude/worktrees/`, then relocates the session into it. The branch base is the local `main` HEAD (`worktree.baseRef: head` in `.claude/settings.json`).
2. Read the memory-bank (above) and follow the normal plan → build → test flow.
3. Write tests (see Testing Requirements) and run them.
4. When green, commit, then `git push -u origin HEAD`, then open the PR with `gh pr create --base main --fill` (adjust title/body as needed). Surface the resulting PR URL to the user. Using `HEAD` / `--fill` avoids hardcoding the tool's sanitized branch name.
   Fallback if `gh` is unavailable/unauthenticated: push, then print the compare URL — `https://github.com/ronniejay22/Knot-APP/compare/main...<branch>?expand=1`

Use judgment — do **not** create a worktree for questions, reviews, or trivial edits. If the session is already inside a worktree or on a non-`main` branch, build there; don't nest another.

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
