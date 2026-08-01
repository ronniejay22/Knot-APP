#!/usr/bin/env bash
#
# Knot backend — local dev launcher.
#
# Binds uvicorn to 0.0.0.0 so a physical iPhone on the same Wi-Fi can reach the
# Mac (not just the simulator). Prints the LAN URL the iOS app auto-detects and
# uses in DEBUG builds — keep this detection logic in sync with
# iOS/scripts/inject-dev-host.sh.
#
# Usage:  ./backend/scripts/dev.sh
#
set -euo pipefail

# Resolve repo paths relative to this script so it works from any CWD.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKEND_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

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

echo "──────────────────────────────────────────────────────────"
if [ -n "${LAN_IP}" ]; then
    echo "  Backend dev server"
    echo "  Simulator / Mac : http://127.0.0.1:8420"
    echo "  Physical device : http://${LAN_IP}:8420   (same Wi-Fi)"
    echo "  Health check    : http://${LAN_IP}:8420/health"
else
    echo "  Backend dev server (no LAN IP detected — offline?)"
    echo "  Simulator / Mac : http://127.0.0.1:8420"
fi
echo "──────────────────────────────────────────────────────────"
echo "  If the device can't connect, allow Python/uvicorn through"
echo "  the macOS firewall (System Settings → Network → Firewall)."
echo "──────────────────────────────────────────────────────────"

cd "${BACKEND_DIR}"

# Bootstrap the virtualenv on a cold checkout. venv/ is gitignored, so a fresh
# clone (or a git worktree) has none and `uvicorn` isn't on PATH. Create it and
# install deps once; subsequent runs just activate the existing venv.
if [ ! -f "venv/bin/activate" ]; then
    echo "  No virtualenv found — bootstrapping dependencies (one-time)…"
    PYTHON="$(command -v python3.13 || command -v python3 || true)"
    if [ -z "${PYTHON}" ]; then
        echo "  ✗ No python3 found on PATH — install Python 3.13 and retry." >&2
        exit 1
    fi
    echo "  Using $("${PYTHON}" --version 2>&1) at ${PYTHON}"
    case "$("${PYTHON}" --version 2>&1)" in
        *" 3.13."*) : ;;
        *) echo "  ⚠ Expected Python 3.13 — deps may not install cleanly on this version." >&2 ;;
    esac
    "${PYTHON}" -m venv venv
    # shellcheck disable=SC1091
    source venv/bin/activate
    python -m pip install --quiet --upgrade pip
    python -m pip install --quiet -r requirements.txt
    echo "  ✓ Dependencies installed."
else
    # shellcheck disable=SC1091
    source venv/bin/activate
fi

exec uvicorn app.main:app --host 0.0.0.0 --port 8420 --reload
