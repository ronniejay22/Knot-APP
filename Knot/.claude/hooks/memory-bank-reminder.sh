#!/usr/bin/env bash
# SessionStart hook: enforces the CLAUDE.md memory-bank reading rule by
# injecting a mandatory directive into context at the start of every session.
# See CLAUDE.md → "Memory Bank (Read First)".

read -r -d '' MSG <<'EOF'
🛑 MANDATORY — Knot project rule (CLAUDE.md → "Memory Bank (Read First)").

Before doing ANY work this session (exploring code, planning, editing, or
answering substantive questions), you MUST read ALL FIVE memory-bank files IN
FULL:
  1. memory-bank/progress.md
  2. memory-bank/architecture.md
  3. memory-bank/IMPLEMENTATION_PLAN.md
  4. memory-bank/PRD.md
  5. memory-bank/techstack.md

progress.md (6000+ lines) and architecture.md (very long lines — a few hundred
lines can exceed the read token limit) MUST be chunk-read with offset/limit
until the ENTIRE file is in context. No skimming. No partial 100-line reads. No
"I have enough context" shortcuts. Read every file all the way through FIRST.
EOF

if command -v jq >/dev/null 2>&1; then
  jq -n --arg ctx "$MSG" \
    '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $ctx}}'
else
  # Fallback: SessionStart adds raw stdout to context if JSON tooling is absent.
  printf '%s\n' "$MSG"
fi
