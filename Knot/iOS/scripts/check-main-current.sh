#!/bin/bash
#
# Warns at build time when the checkout being compiled is behind origin/main —
# i.e. you are about to install a binary that a merged PR has already superseded.
#
# Why this exists: all agent work happens in git worktrees and PRs are merged on
# GitHub, so merging changes neither this checkout nor the binary on the device.
# The failure that motivated this was silent: a change was merged, the app was
# rebuilt from Xcode, and the device still showed the old behaviour because the
# checkout had never been pulled. Nothing in the build said so. This does.
#
# Behaviour:
#   - Warns only. Never pulls, never touches the working tree. A guard that
#     rewrote your source mid-build would cost more than the staleness it saves.
#   - Never fails the build (default). Being offline, or deliberately building an
#     older commit, must not block you.
#   - Only fires on `main`. A feature branch or worktree is behind origin/main by
#     design, and warning there would train you to ignore the warning.
#   - Says so when it CANNOT check. A guard that goes quiet on a broken fetch is
#     indistinguishable from a clean checkout, which is worse than no guard —
#     it reassures you at the exact moment it has stopped working.
#
# Configuration — `KNOT_BUILD_GUARD`:
#   off      silence entirely
#   strict   fail the build instead of warning
# Xcode run-script phases do NOT inherit your login shell's environment, so
# exporting this in .zshrc has no effect on a GUI build. Set it as a
# user-defined BUILD SETTING (Xcode: target > Build Settings > + > Add User-Defined
# Setting, or a `settings:` entry in project.yml) — Xcode exports every build
# setting into the script environment. `launchctl setenv KNOT_BUILD_GUARD off`
# also works, and a plain env var works for command-line `xcodebuild`.
#
# Emits `warning:` / `error:` on stdout, which Xcode surfaces in the Issue
# navigator and the build log.

set -uo pipefail

GUARD_MODE="${KNOT_BUILD_GUARD:-on}"
[ "$GUARD_MODE" = "off" ] && exit 0

# Emit a diagnostic at the configured severity. `strict` turns every finding —
# including "could not check" — into a build failure, which is the point of
# asking for strict.
report() {
    if [ "$GUARD_MODE" = "strict" ]; then
        echo "error: $1"
        [ -n "${2:-}" ] && echo "error: $2"
        exit 1
    fi
    echo "warning: $1"
    [ -n "${2:-}" ] && echo "warning: $2"
}

# Not a git checkout, or git unavailable: nothing meaningful to say. This is the
# one silent exit — it is a statement about the environment, not about freshness.
git -C "${SRCROOT}" rev-parse --git-dir >/dev/null 2>&1 || exit 0

BRANCH=$(git -C "${SRCROOT}" rev-parse --abbrev-ref HEAD 2>/dev/null) || exit 0
[ "$BRANCH" = "main" ] || exit 0

# Fetch on every build, deliberately. An earlier version throttled this to once
# every few minutes, which blinded the guard during "merge the PR, rebuild
# immediately" — the single most likely moment for the staleness to bite, and the
# whole reason the guard exists. A fetch of one branch costs a fraction of a
# second against a build measured in seconds, and this only runs on `main`, so
# agent worktree builds never pay it.
#
# The low-speed bounds stop a captive portal or dead network from hanging the
# build: abort if throughput stays under 1 KB/s for 5s.
#
# The explicit refspec is load-bearing. The comparison below reads
# refs/remotes/origin/main, and a fetch that only populated FETCH_HEAD would
# leave it comparing against a stale tracking ref — silently never warning,
# which is precisely the failure being guarded against.
if ! git -C "${SRCROOT}" \
        -c http.lowSpeedLimit=1000 -c http.lowSpeedTime=5 \
        fetch --quiet origin "+main:refs/remotes/origin/main" 2>/dev/null; then
    report "Could not reach origin to check whether this checkout is current — freshness is UNKNOWN, not confirmed." \
           "If you have just merged a PR, run 'git pull --ff-only' before trusting this build."
    exit 0
fi

# --left-right gives "<ahead>\t<behind>" so a diverged main can be described
# accurately. Plain HEAD..origin/main counts only the behind side, which would
# have prescribed 'git pull --ff-only' for a divergence, where it aborts.
COUNTS=$(git -C "${SRCROOT}" rev-list --left-right --count "HEAD...origin/main" 2>/dev/null) || exit 0
AHEAD=$(printf '%s' "$COUNTS" | awk '{print $1}')
BEHIND=$(printf '%s' "$COUNTS" | awk '{print $2}')
case "${AHEAD:-x}${BEHIND:-x}" in *[!0-9]*) exit 0 ;; esac

[ "$BEHIND" -gt 0 ] || exit 0

if [ "$BEHIND" = "1" ]; then
    SUMMARY="This checkout is 1 commit behind origin/main — you are building stale source."
else
    SUMMARY="This checkout is ${BEHIND} commits behind origin/main — you are building stale source."
fi

if [ "$AHEAD" -gt 0 ]; then
    report "${SUMMARY} It has also diverged (${AHEAD} local commit(s) not on origin/main)." \
           "Reconcile with 'git pull --rebase' — a fast-forward pull will refuse this."
else
    report "${SUMMARY}" \
           "Run 'git pull --ff-only' in the repo root and rebuild, or a merged change will not appear on the device."
fi

exit 0
