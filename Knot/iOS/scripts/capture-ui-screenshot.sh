#!/usr/bin/env bash
#
# Knot iOS — capture a screenshot of the running app for a PR.
#
# Used by the Autonomous Feature Workflow (see Knot/CLAUDE.md): whenever a change
# touches iOS view code, this produces docs/pr-screenshots/<name>.png so /ship-pr
# can embed it inline in the PR body.
#
# How it works:
#   1. Regenerate the Xcode project (xcodegen) so KnotUITests/PRScreenshotTests is
#      included after edits.
#   2. Run the PRScreenshotTests UI test headless via `xcodebuild test`. The test
#      navigates to the changed screen and saves an XCTAttachment named
#      "PR Screenshot".
#   3. Extract that attachment from the .xcresult with `xcrun xcresulttool` and
#      copy it to docs/pr-screenshots/<name>.png.
#   4. Fallback: if the UI-test path fails, take a raw `simctl io booted screenshot`.
#
# Exits non-zero with a one-line reason on stderr if nothing could be captured, so
# the caller can record a "no screenshot" note instead of shipping without one.
#
# Usage: iOS/scripts/capture-ui-screenshot.sh [output-name]
#   output-name defaults to the current git branch (sanitized).
set -euo pipefail

# --- Resolve paths (script lives at <Knot>/iOS/scripts/) ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IOS_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
KNOT_DIR="$(cd "${IOS_DIR}/.." && pwd)"

SCHEME="Knot"
TEST_ID="KnotUITests/PRScreenshotTests"
DERIVED="/tmp/KnotDerivedData"
RESULT="/tmp/knot-shot.xcresult"
ATTACH_DIR="/tmp/knot-shot-attachments"
PREFERRED_SIMS=("iPhone 17 Pro" "iPhone 17 Pro Max" "iPhone 17" "iPhone Air" "iPhone 16 Pro" "iPhone 15")

# --- Output target ---
RAW_NAME="${1:-$(git -C "${KNOT_DIR}" rev-parse --abbrev-ref HEAD 2>/dev/null || echo screenshot)}"
NAME="$(printf '%s' "${RAW_NAME}" | tr '/ ' '--' | tr -cd '[:alnum:]._-')"
[ -n "${NAME}" ] || NAME="screenshot"
OUT_DIR="${KNOT_DIR}/docs/pr-screenshots"
OUT="${OUT_DIR}/${NAME}.png"
mkdir -p "${OUT_DIR}"

fail() { echo "capture-ui-screenshot: $*" >&2; exit 1; }

# --- Pick an available simulator ---
pick_sim() {
    local available name
    available="$(xcrun simctl list devices available 2>/dev/null || true)"
    for name in "${PREFERRED_SIMS[@]}"; do
        if printf '%s' "${available}" | grep -qF "${name} ("; then
            echo "${name}"; return 0
        fi
    done
    # Fall back to the first available iPhone simulator of any kind.
    printf '%s' "${available}" | sed -n 's/^[[:space:]]*\(iPhone[^(]*\) (.*/\1/p' \
        | sed 's/[[:space:]]*$//' | head -1
}

SIM_NAME="$(pick_sim || true)"

# --- Regenerate the project so new test files are included (best effort) ---
if command -v xcodegen >/dev/null 2>&1; then
    ( cd "${IOS_DIR}" && xcodegen generate >/dev/null 2>&1 ) || \
        echo "capture-ui-screenshot: xcodegen generate failed (continuing)" >&2
fi

# --- Primary path: run the screenshot UI test and extract the attachment ---
run_ui_test() {
    [ -n "${SIM_NAME}" ] || { echo "no iOS simulator available" >&2; return 1; }
    rm -rf "${RESULT}" "${ATTACH_DIR}"
    echo "capture-ui-screenshot: running ${TEST_ID} on '${SIM_NAME}'..." >&2
    ( cd "${IOS_DIR}" && xcodebuild test \
        -scheme "${SCHEME}" \
        -only-testing:"${TEST_ID}" \
        -destination "platform=iOS Simulator,name=${SIM_NAME}" \
        -derivedDataPath "${DERIVED}" \
        -resultBundlePath "${RESULT}" ) || { echo "xcodebuild test failed" >&2; return 1; }

    xcrun xcresulttool export attachments \
        --path "${RESULT}" --output-path "${ATTACH_DIR}" >/dev/null 2>&1 \
        || { echo "xcresulttool export failed" >&2; return 1; }

    # Find the exported PNG for the "PR Screenshot" attachment via the manifest;
    # fall back to the largest PNG in the export dir.
    local png
    png="$(python3 - "${ATTACH_DIR}" <<'PY' 2>/dev/null || true
import json, os, sys, glob
d = sys.argv[1]
mani = os.path.join(d, "manifest.json")
try:
    data = json.load(open(mani))
except Exception:
    data = []
def walk(o):
    if isinstance(o, dict):
        name = o.get("suggestedHumanReadableName") or o.get("name") or ""
        fn = o.get("exportedFileName") or o.get("fileName")
        if fn and "PR Screenshot" in name:
            yield fn
        for v in o.values():
            yield from walk(v)
    elif isinstance(o, list):
        for v in o:
            yield from walk(v)
for fn in walk(data):
    p = os.path.join(d, fn)
    if os.path.exists(p):
        print(p); sys.exit(0)
pngs = sorted(glob.glob(os.path.join(d, "**", "*.png"), recursive=True),
              key=lambda p: os.path.getsize(p), reverse=True)
if pngs:
    print(pngs[0])
PY
)"
    [ -n "${png}" ] && [ -f "${png}" ] || { echo "no screenshot attachment found" >&2; return 1; }
    cp "${png}" "${OUT}"
    return 0
}

# --- Fallback path: raw simulator screenshot of whatever is booted ---
run_simctl() {
    echo "capture-ui-screenshot: falling back to 'simctl io booted screenshot'..." >&2
    xcrun simctl io booted screenshot "${OUT}" >/dev/null 2>&1
}

if run_ui_test; then
    :
elif run_simctl; then
    :
else
    fail "could not capture a screenshot (UI test and simctl fallback both failed)"
fi

[ -s "${OUT}" ] || fail "screenshot file is empty: ${OUT}"
echo "capture-ui-screenshot: wrote ${OUT}"
