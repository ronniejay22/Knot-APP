#!/usr/bin/env bash
# UserPromptSubmit hook: reinforces the autonomous feature workflow by injecting
# the worktree → build → /ship-pr directive into context on every prompt.
# See CLAUDE.md → "Autonomous Feature Workflow".

read -r -d '' MSG <<'EOF'
⚙️ Knot autonomous workflow (CLAUDE.md → "Autonomous Feature Workflow").

IF this request asks you to build or change code (a feature, fix, or refactor):
  1. BEFORE editing any files, if not already in a worktree, call the
     EnterWorktree tool to create + enter a fresh worktree on a new branch
     (slug from the request) branched from origin/main. All edits go there.
  2. Build the change and its tests.
  3. When it works, AUTOMATICALLY invoke the /ship-pr skill — do not wait to be
     asked. It tests, code-reviews + fixes, commits, pushes, and opens a PR.
  4. Report the PR URL. NEVER merge — the user is the final reviewer.

IF this is a read-only or question-only request (e.g. "how does X work?"),
IGNORE the above: no worktree, no commit, no PR. Just answer.
EOF

if command -v jq >/dev/null 2>&1; then
  jq -n --arg ctx "$MSG" \
    '{hookSpecificOutput: {hookEventName: "UserPromptSubmit", additionalContext: $ctx}}'
else
  # Fallback: UserPromptSubmit adds raw stdout to context if JSON tooling is absent.
  printf '%s\n' "$MSG"
fi
