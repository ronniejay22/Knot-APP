#!/usr/bin/env bash
#
# Knot iOS — reset the Simulator's local StoreKit state for the app.
#
# WHY THIS EXISTS
# ---------------
# StoreKit test purchases persist in the Simulator across app launches AND across
# app reinstalls — they live in a shared app-group container, not the app's own
# sandbox. Once you complete the 7-day trial once (or a test run does it for you:
# KnotTests' `testPurchaseUnlocksPremium` buys a subscription), every later visit to
# the onboarding paywall sees an active entitlement, so the CTA reads "Continue"
# instead of "Start Free Trial" and tapping it goes straight into the app with no
# Apple purchase sheet. That reads exactly like "I pick a trial and there are no
# payment options" — see memory-bank/progress.md Step 19.14.
#
# The app cannot fix this itself: StoreKit has no API for an app to revoke its own
# entitlement, and `SKTestSession` (which does have `clearTransactions()`) aborts with
# SIGABRT outside an XCTest process — it requires the XCTest runtime. So clearing has
# to happen from outside the app, which is what this script does.
#
# WHAT IT DOES
#   Deletes the Simulator's persisted StoreKit test store for com.ronniejay.knot
#   ("Octane" is Apple's internal name for it). This clears both the purchase history
#   and the registered .storekit configuration, so the next Xcode run re-registers a
#   clean catalog and the paywall offers the trial again.
#
# USAGE
#   iOS/scripts/reset-storekit.sh              # booted simulator
#   iOS/scripts/reset-storekit.sh <device-id>  # a specific simulator
#
# AFTERWARDS
#   Run the app once from Xcode's **Knot** scheme (it carries
#   `storeKitConfiguration: Knot/Knot.storekit`) so the catalog is registered again.
#   The registration then persists, so later launches — including tapping the app icon
#   on the Simulator home screen — will see the products too.
set -euo pipefail

BUNDLE_ID="com.ronniejay.knot"
DEVICE="${1:-booted}"

fail() { echo "reset-storekit: $*" >&2; exit 1; }

# --- Resolve the device UDID ---
if [ "${DEVICE}" = "booted" ]; then
    UDID="$(xcrun simctl list devices booted -j 2>/dev/null \
        | grep -o '"udid" : "[^"]*"' | sed 's/.*: "//;s/"//' | head -1)"
    [ -n "${UDID}" ] || fail "no booted simulator. Boot one, or pass a device UDID."
else
    UDID="${DEVICE}"
fi

DEVICE_ROOT="${HOME}/Library/Developer/CoreSimulator/Devices/${UDID}"
[ -d "${DEVICE_ROOT}" ] || fail "no simulator with UDID ${UDID}"

echo "reset-storekit: device ${UDID}"

# --- Find every persisted StoreKit test store for this app ---
# Path shape: data/Containers/Shared/AppGroup/<uuid>/Documents/Persistence/Octane/<bundle-id>
# NOTE: a while-read loop, not `mapfile` — macOS ships bash 3.2, which has no mapfile.
FOUND=0
# Terminate first so storekitd isn't holding the store open mid-delete.
xcrun simctl terminate "${UDID}" "${BUNDLE_ID}" >/dev/null 2>&1 || true
while IFS= read -r store; do
    [ -n "${store}" ] || continue
    rm -rf "${store}"
    echo "reset-storekit: cleared ${store}"
    FOUND=$((FOUND + 1))
done < <(
    find "${DEVICE_ROOT}/data/Containers/Shared/AppGroup" \
        -maxdepth 5 -type d -path "*/Persistence/Octane/${BUNDLE_ID}" 2>/dev/null || true
)

if [ "${FOUND}" -eq 0 ]; then
    echo "reset-storekit: nothing to clear — no StoreKit test state for ${BUNDLE_ID}"
fi

echo
echo "Done. Next: run the app from Xcode's 'Knot' scheme once to re-register the"
echo "local catalog (Knot.storekit), then the paywall will offer the 7-day trial again."
