---
description: Write the memory-bank documentation for a finished change — generate the correctly-formatted `### Step X.Y` entry in progress.md (picking a non-colliding number, inserted in the right place) and the matching architecture.md updates. Use after building a feature/fix, before /ship-pr commits. Encodes the CLAUDE.md "Documentation Updates" rules so the format and section order can't drift.
argument-hint: [step title]
---

# /log-step

Knot requires every change to be logged in `memory-bank/` in a fixed shape (CLAUDE.md →
"Documentation Updates"). Doing it by hand is the most repeated per-PR chore and the easiest
place to get the format, the step number, or the section order wrong. This skill produces both
doc edits from the change you just made.

It writes docs only — it does **not** stage or commit. `/ship` / `/ship-pr` own the commit
(the commit message must NOT contain step numbers, per the user's memory, even though
progress.md entries do).

Run from the `Knot/` directory (or a worktree's `Knot/` subdir).

## Phase 1 — Gather the change

1. Determine what changed: `git diff origin/main...HEAD` plus any staged/unstaged edits
   (`git status`, `git diff`, `git diff --cached`). If nothing changed, say so and stop.
2. Derive a concise Title (imperative, ~4–10 words). Use the `[step title]` argument verbatim
   if provided; otherwise infer it from the diff and the branch name.
3. Note which layer(s) changed (iOS view code / iOS non-view / backend / docs / tooling) — this
   drives the Tests line and whether a screenshot is relevant (see `/screenshot-screen`).

## Phase 2 — Pick a non-colliding step number

Step numbering in `progress.md` is **not** strictly sequential — parallel worktrees have
produced real collisions (multiple `### Step 19.1`, out-of-order 18.x, etc.). Do not blindly
"increment the last one."

1. List existing headers: `grep -nE '^### Step [0-9]+\.[0-9]+' memory-bank/progress.md`.
2. Choose the number:
   - Continuing an obvious active series → the next `.Y` in that series (e.g. after `19.15` →
     `19.16`).
   - Otherwise pick the natural next number for the phase the change belongs to.
3. **Verify it's free:** the exact string `### Step X.Y ` must NOT already appear in the file.
   If it does, bump until it's unique. A collision here is exactly the merge-time renumbering
   pain this skill exists to avoid — never introduce a duplicate.

## Phase 3 — Write the progress.md entry

Match the **recent** entry shape (see the latest Step 19.x entries as the canonical model),
not the older `### Step X.Y: Title ✅` / "What was done / Files created / Test results" shape.

Template:

```markdown
### Step X.Y ✅ <Title>
**Date:** <YYYY-MM-DD>          # today's date, from the environment's current date
**Status:** Complete

**Goal:** <one or two sentences: the problem this solved and the outcome.>

**What changed:**
- <per-area prose or per-file bullets — be specific about files, functions, and why. Mirror the
  density of nearby entries. For a root-cause fix, add a short **Root cause:** line.>

**Files created:**
- `<path>` — <what it is>          # omit this block if none

**Files modified:**
- `<path>` — <what changed>

**Files deleted:**
- `<path>`                          # omit this block if none

**Tests:** <exact result — e.g. "Full backend suite: 1340 passed, 622 skipped, 0 failures";
"iOS Full plan green (345 unit + 5 UI)". State plainly if a layer had nothing to test.>

**Notes:** <optional — non-obvious decisions, follow-ups, gotchas future devs need.>
```

Formatting rules that MUST hold (from CLAUDE.md):
- The entry goes under `## Completed Steps`, **inserted immediately before the `## Next Steps`
  header** — never appended to the end of the file. (`grep -n '^## Next Steps' memory-bank/progress.md`
  to find the insertion point.)
- Strict section order in the file stays: `## Completed Steps` → `## Next Steps` →
  `## Notes for Future Developers`. Do not reorder or duplicate these headers.
- Separate the entry from the next one with a `---` rule, matching the surrounding entries.
- Do NOT touch the `## Notes for Future Developers` numbered list unless the change genuinely
  adds a durable, cross-cutting gotcha — if it does, append the next number at the end of that
  list (it is append-only and its numbering is already imperfect; don't renumber it).

## Phase 4 — Update architecture.md

`memory-bank/architecture.md` documents every file in `| File | Purpose |` tables (grouped by
module) plus a numbered "architectural notes" section near the bottom.

1. For each **new** file: add a `| \`<name>\` | ... |` row to the correct module table, opening
   the Purpose with `**Step X.Y:**` or `**Active (Step X.Y).**` like the neighbours.
2. For each **modified** file whose behavior/role changed: append a `**Step X.Y:**` clause to
   that file's existing Purpose cell describing the change (don't rewrite the whole cell).
3. For each **deleted** file: remove its row.
4. Only add a numbered architectural note at the bottom if the change introduces a non-obvious,
   reusable pattern worth calling out — otherwise skip it.

Locate rows fast with `grep -n '\`<filename>\`' memory-bank/architecture.md`.

## Phase 5 — Verify

- `grep -c '^### Step X.Y ' memory-bank/progress.md` returns exactly `1` (unique).
- The new entry sits above `## Next Steps`, and the three top-level section headers appear once
  each in the correct order.
- `git diff memory-bank/architecture.md` shows the touched file rows updated.
- Leave the edits uncommitted — `/ship` / `/ship-pr` will review and commit them with the rest
  of the change (multi-paragraph message, no step numbers, no `Co-Authored-By`).
