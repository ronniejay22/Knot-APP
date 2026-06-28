#!/usr/bin/env bash
#
# Knot iOS — write the Mac's current LAN IP into a DevServer.plist bundled into
# the DEBUG build. The app reads `DevAPIBaseURL` from it at runtime
# (Constants.API.resolveDebugBaseURL) so the simulator AND a physical iPhone on
# the same Wi-Fi both reach the local backend with zero manual edits and nothing
# network-specific committed to source.
#
# Runs as a postBuildScript (see project.yml); writes only its declared
# outputFile so it stays compatible with ENABLE_USER_SCRIPT_SANDBOXING.
# Detection logic is kept in sync with backend/scripts/dev.sh.
#
set -euo pipefail

# Only DEBUG builds talk to a local backend; Release uses the production URL.
if [ "${CONFIGURATION:-}" != "Debug" ]; then
    echo "inject-dev-host: skipping (CONFIGURATION=${CONFIGURATION:-unset})"
    exit 0
fi

# --- Detect the Mac's private LAN IP (first interface with a private address) ---
detect_lan_ip() {
    local ip
    for iface in en0 en1 en2 en3 en4 en5 en6 en7 en8; do
        ip="$(ipconfig getifaddr "$iface" 2>/dev/null || true)"
        case "$ip" in
            192.168.*|10.*|172.1[6-9].*|172.2[0-9].*|172.3[0-1].*)
                echo "$ip"
                return 0
                ;;
        esac
    done
    return 1
}

LAN_IP="$(detect_lan_ip || true)"
if [ -z "${LAN_IP}" ]; then
    LAN_IP="127.0.0.1"
    echo "inject-dev-host: no LAN IP found (offline?) — falling back to ${LAN_IP}"
fi

DEV_BASE_URL="http://${LAN_IP}:8000"
PLIST="${TARGET_BUILD_DIR}/${CONTENTS_FOLDER_PATH}/DevServer.plist"

cat > "${PLIST}" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>DevAPIBaseURL</key>
    <string>${DEV_BASE_URL}</string>
</dict>
</plist>
EOF

echo "inject-dev-host: DevAPIBaseURL = ${DEV_BASE_URL}"
