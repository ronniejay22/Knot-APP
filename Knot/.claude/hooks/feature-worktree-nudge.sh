#!/usr/bin/env bash
# SessionStart hook: nudges the agent to create an isolated git worktree +
# branch when a session is about to BUILD a new feature, so parallel feature
# chats never collide (notably on iOS project.pbxproj).
# See CLAUDE.md → "Feature Worktrees". Pairs with memory-bank-reminder.sh.

# --- Detect whether this session is already isolated ----------------------
# In a linked worktree, the absolute git-dir lives under .git/worktrees/<name>
# while the common git-dir is the shared .git — so they differ. In the main
# checkout they resolve to the same path.
git_dir="$(git rev-parse --absolute-git-dir 2>/dev/null)"
common_dir="$(cd "$(git rev-parse --git-common-dir 2>/dev/null)" 2>/dev/null && pwd)"
branch="$(git branch --show-current 2>/dev/null)"

in_worktree=false
if [ -n "$git_dir" ] && [ -n "$common_dir" ] && [ "$git_dir" != "$common_dir" ]; then
  in_worktree=true
fi

if [ "$in_worktree" = true ] || { [ -n "$branch" ] && [ "$branch" != "main" ]; }; then
  read -r -d '' MSG <<EOF
🌿 Feature worktree — this session is already isolated on branch "${branch:-(detached)}".
No new worktree needed. Build here, then commit, push, and open a PR when done.
EOF
else
  read -r -d '' MSG <<'EOF'
🌿 Feature worktree — Knot project rule (CLAUDE.md → "Feature Worktrees").

If the user's request is to BUILD / IMPLEMENT a new feature (NOT a question,
review, discussion, small fix, or continuation of existing work), then BEFORE
making any edits:
  1. Call EnterWorktree with name="<kebab-feature-name>" (no slashes/prefix) —
     this creates an isolated branch (the tool names it worktree-<name>) +
     worktree and relocates this session into it.
  2. Then read the memory-bank and follow the normal plan → build → test flow.
  3. Write tests (CLAUDE.md requires them) and run xcodebuild test.
  4. Finish: commit, then `git push -u origin HEAD`, then open the PR with
     `gh pr create --base main --fill` and surface the PR URL. (Using HEAD /
     --fill avoids hardcoding the tool's sanitized branch name.) If gh is
     unavailable, fall back to printing the compare URL:
     https://github.com/ronniejay22/Knot-APP/compare/main...<branch>?expand=1

Use judgment — do NOT create a worktree for questions, reviews, or trivial edits.
EOF
fi

if command -v jq >/dev/null 2>&1; then
  jq -n --arg ctx "$MSG" \
    '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $ctx}}'
else
  # Fallback: SessionStart adds raw stdout to context if JSON tooling is absent.
  printf '%s\n' "$MSG"
fi
