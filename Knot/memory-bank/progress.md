# Progress Log: Project Knot

This document tracks implementation progress for future developers.

---

## Completed Steps

### Step 0.1: Create iOS Project Structure ✅
**Date:** February 3, 2026  
**Status:** Complete

**What was done:**
- Created Xcode project "Knot" using XcodeGen
- Configured for SwiftUI with SwiftData persistence
- Set minimum deployment target to iOS 17.0
- Enabled Swift 6 with strict concurrency checking (Complete mode)
- Bundle identifier: `com.ronniejay.knot`

**Files created:**
- `iOS/project.yml` — XcodeGen configuration
- `iOS/Knot/App/KnotApp.swift` — Main app entry point with SwiftData ModelContainer
- `iOS/Knot/App/ContentView.swift` — Initial placeholder view
- `iOS/Knot/Info.plist` — App configuration

**Test results:**
- ✅ Project builds with zero errors
- ✅ App launches on iOS Simulator
- ✅ SwiftData imports and compiles correctly
- ✅ Displays "Knot" title with heart icon

---

### Step 0.2: Set Up iOS Folder Architecture ✅
**Date:** February 3, 2026  
**Status:** Complete

**What was done:**
- Created folder structure following feature-based architecture
- Added placeholder files to ensure folders are tracked by Git
- Created Constants.swift with predefined interest categories, vibes, and love languages

**Folder structure:**
```
iOS/Knot/
├── App/           ✅ App entry point (KnotApp.swift, ContentView.swift)
├── Features/      ✅ Feature modules (empty, ready for Auth, Onboarding, etc.)
├── Core/          ✅ Shared utilities (Constants.swift)
├── Services/      ✅ API clients (empty)
├── Models/        ✅ SwiftData models (empty)
├── Components/    ✅ Reusable UI components (empty)
└── Resources/     ✅ Assets.xcassets (AppIcon, AccentColor)
```

**Test targets created:**
- `KnotTests/` — Unit tests
- `KnotUITests/` — UI tests

---

### Step 0.3: Install iOS Dependencies (Lucide Icons) ✅
**Date:** February 5, 2026  
**Status:** Complete

**What was done:**
- Added LucideIcons Swift Package (`lucide-icons-swift`) via SPM to `project.yml`
- Package resolved to version 0.563.1 from `https://github.com/JakubMazur/lucide-icons-swift.git`
- Updated `ContentView.swift` to import `LucideIcons` and render Lucide icons (Heart, Gift, Calendar, Sparkles)
- No shadcn/ui SwiftUI port was available; custom components will be built matching shadcn aesthetic (Components folder ready from Step 0.2)
- Regenerated Xcode project via `xcodegen generate`

**Files modified:**
- `iOS/project.yml` — Added `packages` section with LucideIcons SPM dependency; added `dependencies` to Knot target
- `iOS/Knot/App/ContentView.swift` — Replaced SF Symbol heart with Lucide `Heart` icon; added Gift, Calendar, Sparkles icons

**Test results:**
- ✅ SPM dependency resolved successfully (LucideIcons v0.563.1)
- ✅ Project builds with zero errors and zero warnings
- ✅ `import LucideIcons` compiles correctly
- ✅ Lucide icons render: Heart (hero), Gift, Calendar, Sparkles (secondary row)
- ✅ Build verified on iPhone 17 Pro Simulator (iOS 26.2)

**Notes:**
- `DEVELOPER_DIR` must be set to `/Applications/Xcode.app/Contents/Developer` if xcodebuild defaults to Command Line Tools
- Available simulators on this machine: iPhone 17, iPhone 17 Pro, iPhone 17 Pro Max, iPhone Air (iOS 26.2)

---

### Step 0.4: Create Backend Project Structure ✅
**Date:** February 5, 2026  
**Status:** Complete

**What was done:**
- Created `backend/` directory at the project root with full folder structure
- Initialized Python 3.13.12 virtual environment (installed via `brew install python@3.13`)
- Created `requirements.txt` with minimum dependencies for Step 0.4 (fastapi, uvicorn[standard])
- Created `app/main.py` with FastAPI app and `/health` endpoint returning `{"status": "ok"}`
- Created placeholder route modules with `APIRouter` instances for all four API domains (vault, hints, recommendations, users)
- Created `app/core/config.py` (app settings placeholder) and `app/core/security.py` (auth middleware placeholder)
- Created `__init__.py` files in all packages for proper Python module resolution
- Created `tests/` directory for the backend test suite
- Created `.env.example` with all environment variable placeholders from the implementation plan
- Created `.gitignore` to exclude `.env`, `__pycache__/`, `venv/`, and other artifacts

**Files created:**
- `backend/requirements.txt` — FastAPI + uvicorn[standard]
- `backend/app/__init__.py` — App package marker
- `backend/app/main.py` — FastAPI entry point with `/health` endpoint
- `backend/app/api/__init__.py` — API package marker
- `backend/app/api/vault.py` — Partner Vault route handler (placeholder APIRouter)
- `backend/app/api/hints.py` — Hints route handler (placeholder APIRouter)
- `backend/app/api/recommendations.py` — Recommendations route handler (placeholder APIRouter)
- `backend/app/api/users.py` — Users route handler (placeholder APIRouter)
- `backend/app/core/__init__.py` — Core package marker
- `backend/app/core/config.py` — App configuration constants (placeholder)
- `backend/app/core/security.py` — Auth middleware (placeholder for Step 2.5)
- `backend/app/models/__init__.py` — Pydantic models package marker
- `backend/app/services/__init__.py` — Services package marker
- `backend/app/services/integrations/__init__.py` — External API integrations package marker
- `backend/app/agents/__init__.py` — LangGraph agents package marker
- `backend/app/db/__init__.py` — Database repository package marker
- `backend/tests/__init__.py` — Test suite package marker
- `backend/.env.example` — Environment variable template (Supabase, Vertex AI, external APIs, Upstash, APNs)
- `backend/.gitignore` — Excludes .env, __pycache__, venv, IDE files

**Test results:**
- ✅ `python --version` returns Python 3.13.12
- ✅ `pip install -r requirements.txt` installs FastAPI 0.128.2 + uvicorn 0.40.0 successfully
- ✅ `uvicorn app.main:app` starts server on port 8000
- ✅ `curl http://127.0.0.1:8000/health` returns `{"status":"ok"}` (HTTP 200)
- ✅ Swagger docs available at `/docs` with title "Knot API" v0.1.0

**Notes:**
- Python 3.13.12 installed via Homebrew at `/opt/homebrew/bin/python3.13`
- Virtual environment located at `backend/venv/` (gitignored)
- To activate: `cd backend && source venv/bin/activate`
- To start server: `uvicorn app.main:app --host 127.0.0.1 --port 8000`
- Full dependency list (LangGraph, Supabase, Vertex AI, etc.) will be added in Step 0.5

---

### Step 0.5: Install Backend Dependencies ✅
**Date:** February 5, 2026  
**Status:** Complete

**What was done:**
- Updated `requirements.txt` with the full dependency list from the implementation plan
- Installed all packages into the Python 3.13 virtual environment
- Created `tests/test_imports.py` — 11 test functions verifying every package imports correctly
- Created `pyproject.toml` with pytest configuration (asyncio mode, warning filters for third-party deprecations)

**Files created/modified:**
- `backend/requirements.txt` — Updated with all dependencies (fastapi, uvicorn, langgraph, google-cloud-aiplatform, pydantic, pydantic-ai, supabase, pgvector, httpx, python-dotenv, pytest, pytest-asyncio)
- `backend/tests/test_imports.py` — Import verification test suite (11 tests)
- `backend/pyproject.toml` — Pytest config with asyncio_mode="auto" and warning filters for pyiceberg deprecation warnings

**Installed package versions (key packages):**
- `fastapi` 0.128.2
- `uvicorn` 0.40.0
- `langgraph` 1.0.7
- `google-cloud-aiplatform` 1.136.0
- `pydantic` 2.12.5
- `pydantic-ai` 1.56.0
- `supabase` 2.27.3
- `pgvector` 0.4.2
- `httpx` 0.28.1
- `python-dotenv` 1.2.1
- `pytest` 9.0.2

**Test results:**
- ✅ `pip install -r requirements.txt` installs all packages without errors
- ✅ `pytest tests/test_imports.py -v` — 11 passed, 0 failed, 0 warnings
- ✅ All key imports verified: `FastAPI`, `StateGraph` (LangGraph), `aiplatform` (Vertex AI), `BaseModel` (Pydantic), `Agent` (Pydantic AI), `create_client` (Supabase), `Vector` (pgvector), `AsyncClient` (httpx), `load_dotenv`
- ✅ `/health` endpoint still works after dependency expansion

**Notes:**
- `pyiceberg` (transitive dep of `supabase`) emits deprecation warnings — suppressed in `pyproject.toml` via `filterwarnings`. These are in third-party code and will resolve when pyiceberg updates.
- `pgvector` is used via its base `Vector` type (not the SQLAlchemy integration) since we use Supabase client for DB access.
- Run tests with: `cd backend && source venv/bin/activate && pytest tests/test_imports.py -v`

---

### Step 0.6: Set Up Supabase Project ✅
**Date:** February 5, 2026  
**Status:** Complete

**What was done:**
- Created Supabase project "knot-dev" via the Supabase dashboard
- Enabled the pgvector extension in the database via SQL Editor (`CREATE EXTENSION IF NOT EXISTS vector WITH SCHEMA extensions;`)
- Created `.env` file in the backend directory with Supabase credentials (URL, anon key, service role key)
- Updated `app/core/config.py` to load environment variables from `.env` using `python-dotenv` with a `validate_supabase_config()` function
- Created `app/db/supabase_client.py` with lazy-initialized Supabase clients (anon for RLS-respecting user operations, service_role for admin operations)
- Created `supabase/migrations/00001_enable_pgvector.sql` migration file
- Created `tests/test_supabase_connection.py` — 11 tests across 3 test classes

**Files created/modified:**
- `backend/.env` — Supabase credentials (gitignored, NEVER commit)
- `backend/app/core/config.py` — **Updated:** Now loads env vars via `python-dotenv`, exposes `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`, and `validate_supabase_config()`
- `backend/app/db/supabase_client.py` — **Created:** Provides `get_supabase_client()` (anon/RLS) and `get_service_client()` (admin/bypass RLS), plus `test_connection()` helper
- `backend/supabase/migrations/00001_enable_pgvector.sql` — **Created:** SQL to enable pgvector extension
- `backend/tests/test_supabase_connection.py` — **Created:** 11 tests verifying env config, Supabase connectivity, and pgvector library

**Test results:**
- ✅ `pytest tests/test_supabase_connection.py -v` — 11 passed, 0 failed, 2 warnings (Supabase library deprecation, not our code)
- ✅ `.env` file loads all three Supabase credentials correctly
- ✅ `validate_supabase_config()` passes — all required env vars present
- ✅ Anon client initializes successfully
- ✅ Service role client initializes successfully
- ✅ Simple query executes against live Supabase database (connected via PostgREST)
- ✅ pgvector `Vector` type imports and creates 768-dimension embeddings
- ✅ pgvector extension enabled in Supabase database
- ✅ Existing `test_imports.py` (11 tests) still passes
- ✅ `/health` endpoint still returns `{"status":"ok"}`

**Notes:**
- The Supabase client uses the new key format: `sb_publishable_...` (anon) and `sb_secret_...` (service_role)
- The `supabase` Python library emits 2 deprecation warnings about `timeout` and `verify` parameters — these are in the library's code, not ours, and will resolve when `supabase-py` updates
- `pgvector.Vector` uses `.to_list()` and `.to_numpy()` methods (not iterable via `list()`) — important for future embedding work
- Connection tests handle PostgREST error code `PGRST205` (table not in schema cache) as a successful connection signal
- Supabase clients are initialized lazily (on first use) to avoid import-time failures
- Run tests with: `cd backend && source venv/bin/activate && pytest tests/test_supabase_connection.py -v`

---

### Step 0.7: Configure Supabase Auth with Apple Sign-In ✅
**Date:** February 5, 2026  
**Status:** Complete

**What was done:**
- Enabled Apple Sign-In provider in Supabase dashboard (Authentication → Sign In / Providers → Apple)
- Configured Client ID with app bundle identifier (`com.ronniejay.knot`)
- Enabled "Allow users without an email" for Apple Private Relay users
- Added `supabase-swift` v2.41.0 SPM dependency to iOS project (Auth, PostgREST, Supabase modules)
- Created `tests/test_supabase_auth.py` — 6 tests verifying auth service and Apple provider configuration
- OAuth Secret Key intentionally left empty — Knot uses native iOS Sign in with Apple (not the web OAuth redirect flow)

**Files created/modified:**
- `iOS/project.yml` — **Updated:** Added `Supabase` SPM package with Auth, PostgREST, and Supabase product dependencies
- `iOS/Knot.xcodeproj/` — **Regenerated:** via `xcodegen generate` with new Supabase dependencies
- `backend/tests/test_supabase_auth.py` — **Created:** 6 tests across 2 test classes (auth reachability + Apple provider config)

**Test results:**
- ✅ `pytest tests/test_supabase_auth.py -v` — 6 passed, 0 failed
- ✅ GoTrue `/auth/v1/settings` endpoint returns 200 with provider list
- ✅ GoTrue `/auth/v1/health` endpoint returns healthy status
- ✅ Email provider enabled by default
- ✅ Apple provider is enabled (`"apple": true` in settings)
- ✅ Signup is not disabled (new users can register)
- ✅ Native auth endpoint (`/auth/v1/token?grant_type=id_token`) recognizes Apple as a valid provider
- ✅ iOS project builds with Supabase Swift SDK (supabase-swift v2.41.0)
- ✅ All existing tests still pass (22 from Steps 0.5–0.6)

**Supabase Dashboard Configuration:**
- Provider: Apple — **Enabled**
- Client IDs: `com.ronniejay.knot`
- Secret Key: Empty (not needed for native iOS auth)
- Allow users without email: **Enabled**
- Callback URL: `https://nmruwlfvhkvkbcdncwaq.supabase.co/auth/v1/callback` (for future web OAuth, not used by iOS)

**Notes:**
- Knot uses **native iOS Sign in with Apple** via `SignInWithAppleButton` (AuthenticationServices framework). The flow: iOS gets identity token from Apple → sends to Supabase via `signInWithIdToken(provider: .apple, idToken: token)`. This does NOT require the OAuth Secret Key or Callback URL.
- The OAuth Secret Key would only be needed if adding web-based Sign in with Apple in the future. Apple OAuth secrets expire every 6 months.
- The `supabase-swift` package brings transitive dependencies: swift-crypto, swift-asn1, swift-http-types, swift-clocks, swift-concurrency-extras, xctest-dynamic-overlay.
- Run tests with: `cd backend && source venv/bin/activate && pytest tests/test_supabase_auth.py -v`

---

### Step 1.1: Create Users Table ✅
**Date:** February 6, 2026  
**Status:** Complete

**What was done:**
- Created `public.users` table linked to `auth.users` via foreign key with `ON DELETE CASCADE`
- Columns: `id` (UUID PK), `email` (text, nullable), `created_at` (timestamptz), `updated_at` (timestamptz)
- Enabled Row Level Security (RLS) with three policies: `users_select_own`, `users_update_own`, `users_insert_own` — all enforce `auth.uid() = id`
- Created `handle_updated_at()` trigger function (reusable for future tables) that auto-updates `updated_at` on row changes
- Created `handle_new_user()` trigger (SECURITY DEFINER) on `auth.users` that auto-inserts a `public.users` row when a user signs up
- Granted SELECT/INSERT/UPDATE to `authenticated` role, SELECT to `anon` role (RLS still blocks anon from seeing rows)
- Created 10 tests verifying table existence, schema, RLS enforcement, and trigger behavior

**Files created:**
- `backend/supabase/migrations/00002_create_users_table.sql` — Full migration with table, RLS, triggers, and grants
- `backend/tests/test_users_table.py` — 10 tests across 4 test classes (Exists, Schema, RLS, Triggers)

**Test results:**
- ✅ `pytest tests/test_users_table.py -v` — 10 passed, 0 failed
- ✅ Table accessible via PostgREST API
- ✅ All 4 columns present (id, email, created_at, updated_at)
- ✅ id stores valid UUIDs matching auth.users
- ✅ created_at auto-populated via DEFAULT now()
- ✅ email accepts NULL (Apple Private Relay compatible)
- ✅ Anon client (no JWT) sees 0 rows — RLS enforced
- ✅ Service client (admin) can read all rows — RLS bypassed
- ✅ handle_new_user trigger auto-creates profile on auth signup
- ✅ set_updated_at trigger updates timestamp on row changes
- ✅ ON DELETE CASCADE removes public.users row when auth user is deleted
- ✅ All existing tests still pass (28 from Steps 0.5–0.7)

**Notes:**
- The Supabase SQL Editor runs multi-statement SQL as a single transaction. If any statement fails (e.g., a typo in a GRANT role name), the entire batch is rolled back. When debugging migration failures, run statements in smaller batches to isolate errors.
- `handle_updated_at()` is a reusable trigger function — future tables (partner_vaults, etc.) can attach their own `set_updated_at` trigger using the same function.
- `handle_new_user()` uses `SECURITY DEFINER` so it can insert into `public.users` despite RLS being enabled. It runs with the privileges of the function creator (postgres), not the calling user.
- The `anon` role has SELECT GRANT on the table, but RLS returns empty results because `auth.uid()` is NULL for the anon key. This layered defense (GRANT + RLS) is intentional.
- Run tests with: `cd backend && source venv/bin/activate && pytest tests/test_users_table.py -v`

---

## Next Steps

- [ ] **Step 1.2:** Create Partner Vault Table

---

## Notes for Future Developers

1. **Regenerating the Xcode project:** If you modify `project.yml`, run:
   ```bash
   cd iOS && xcodegen generate
   ```

2. **Bundle Identifier:** Changed from `com.knot.app` (taken) to `com.ronniejay.knot`

3. **Running on Simulator:** Select iPhone 17 Pro simulator (available: iPhone 17, 17 Pro, 17 Pro Max, iPhone Air on iOS 26.2). Avoid physical device to skip provisioning profile issues during development.

4. **XcodeGen required:** Install with `brew install xcodegen`

5. **Supabase credentials:** The `.env` file is gitignored. New developers must create their own by copying `.env.example` and filling in credentials from the Supabase dashboard (Settings → API).

6. **pgvector extension:** Must be enabled in the Supabase SQL Editor before creating tables with vector columns. Run the migration at `backend/supabase/migrations/00001_enable_pgvector.sql`.

7. **pgvector Vector API:** Use `vec.to_list()` (not `list(vec)`) to convert vectors to Python lists. Use `vec.to_numpy()` for NumPy arrays. The `Vector` object is not iterable.

8. **Apple Sign-In (native iOS):** Knot uses native `SignInWithAppleButton`, NOT the web OAuth redirect flow. The OAuth Secret Key in Supabase dashboard can be left empty. The native flow sends Apple's identity token directly to Supabase via `signInWithIdToken`.

9. **Supabase Swift SDK:** Added as SPM dependency in `project.yml`. Three products are linked: `Auth` (authentication), `PostgREST` (database queries), `Supabase` (umbrella). After modifying `project.yml`, regenerate with `cd iOS && xcodegen generate`.
