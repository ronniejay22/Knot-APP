---
description: Boot the Knot backend dev server (FastAPI/uvicorn on :8420) so the iOS app can reach it. Use whenever the app shows "Unable to connect to the server" (e.g. the DEV Reset Onboarding button) or before running the app against a local backend. Wraps backend/scripts/dev.sh — cold-starts the venv if missing, launches in the background, and confirms /health before reporting URLs.
argument-hint: [restart — force a clean restart if the server is wedged]
---

# /start-server

The iOS app talks to a local FastAPI/uvicorn backend on port **8420**. When that server isn't
running, every API call fails and the app shows *"Unable to connect to the server"* (the DEV
**Reset Onboarding** button is the usual place this bites). This skill boots the backend reliably:
it reuses the existing launcher [`backend/scripts/dev.sh`](../../../backend/scripts/dev.sh) (LAN-IP
detection + `uvicorn app.main:app --host 0.0.0.0 --port 8420 --reload`), launches it in the
background so uvicorn survives across turns, and confirms `/health` before returning.

Run from the `Knot/` directory of the **main checkout** — not a git worktree, which has no venv.
The optional `restart` argument kills any process already bound to :8420 first.

## Phase 1 — Skip if already up (idempotent)

1. `curl -s -m 2 http://127.0.0.1:8420/health`. If it returns `{"status":"ok"}`:
   - **No `restart` argument:** the server is already running — print the URLs (Phase 4) and stop.
     Never launch a second uvicorn on the same port.
   - **`restart` argument given:** the user wants a clean restart — `kill $(lsof -i :8420 -t)`,
     wait for the port to free, then continue to Phase 2.
2. If `/health` doesn't answer, the server is down (the expected case) — continue.

## Phase 2 — Ensure prerequisites

1. **`.env`.** If `backend/.env` is missing, copy the template: `cp backend/.env.example backend/.env`.
   Then tell the user it needs the three vars required to serve authed endpoints —
   `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY` — before real requests will work.
   (`/health` responds even with an empty `.env`; every other provider is optional and self-disables.)
2. **Dev-reset flag.** Ensure `backend/.env` contains `KNOT_DEV_RESET_ENABLED=true` so the DEV
   **Reset Onboarding** button (`POST /api/v1/users/me/dev-reset`) actually works once the server is
   up. If the key is absent, append it; if present but not `true`, leave the user's value alone and
   note it. **Guard:** only ever touch the local `backend/.env`. This flag must stay UNSET in
   production (Vercel) — it gates a vault-wiping endpoint — so never write it anywhere but the local
   dev file.
3. **venv.** No action needed here — `dev.sh` bootstraps a missing `backend/venv/` (creates it and
   `pip install -r requirements.txt`) on first run. This is why the skill must run from the main
   checkout: a worktree deliberately has no venv.

## Phase 3 — Launch in the background

Start the launcher as a background process so uvicorn keeps running while you continue working, and
capture its output to a log for diagnosis:

```bash
./backend/scripts/dev.sh > backend/.dev-server.log 2>&1
```

Run this with the Bash tool's `run_in_background: true`. `backend/.dev-server.log` is already
gitignored by the `*.log` rule. `--reload` (baked into `dev.sh`) auto-restarts uvicorn on code
changes, so you rarely need to restart by hand.

## Phase 4 — Verify health and report

1. Poll readiness with `curl`'s own retry so you don't need a shell `sleep` loop (the Bash tool
   blocks a foreground `sleep`). A warm start answers in a few seconds:
   ```bash
   curl -s --retry 20 --retry-delay 1 --retry-connrefused --retry-all-errors -m 3 \
     http://127.0.0.1:8420/health
   ```
   **Cold start (venv was missing):** `dev.sh` runs a one-time `pip install` first, which takes
   minutes — far longer than the 20s retry budget above. When you launched a cold start, first
   wait for `dev.sh` to finish bootstrapping — watch `backend/.dev-server.log` for the
   `✓ Dependencies installed.` line (poll the log's tail rather than health) — then run the health
   curl above. Don't report failure just because health is slow while deps are still installing.
2. **On `{"status":"ok"}`** — report the reachable URLs:
   - Simulator / Mac: `http://127.0.0.1:8420`
   - Physical device (same Wi-Fi): `http://<Mac-LAN-IP>:8420` — the LAN IP `dev.sh` printed to the log.
3. **On failure** — surface the cause: show the tail of `backend/.dev-server.log`. Common causes:
   - **Port already in use:** `lsof -i :8420` shows a stale uvicorn — re-run with the `restart`
     argument, or `kill $(lsof -i :8420 -t)`.
   - **Missing dependency / import error:** the log names the module; the venv bootstrap may have
     failed (check `python3.13` is installed).

## Phase 5 — Stopping

To stop the background server: `kill $(lsof -i :8420 -t)`. To confirm it's down:
`curl -s -m 2 http://127.0.0.1:8420/health` should fail to connect.
