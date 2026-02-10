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

### Step 1.2: Create Partner Vault Table ✅
**Date:** February 6, 2026  
**Status:** Complete

**What was done:**
- Created `partner_vaults` table with 10 columns for storing partner profile data
- `id` is auto-generated UUID via `gen_random_uuid()` (unlike `users.id` which mirrors `auth.users.id`)
- `user_id` is `UNIQUE` — enforces one vault per user (MVP constraint)
- `partner_name` is `NOT NULL` — the only required text field
- `cohabitation_status` has a `CHECK` constraint for 3 valid enum values: `living_together`, `separate`, `long_distance`
- `location_country` defaults to `'US'` for domestic users; international users can override
- Foreign key on `user_id` references `public.users(id)` with `ON DELETE CASCADE` (cascades from auth.users → users → partner_vaults)
- Enabled RLS with 4 policies (SELECT, INSERT, UPDATE, DELETE) all enforcing `auth.uid() = user_id`
- Reused `handle_updated_at()` trigger function from Step 1.1 (no new trigger function needed)
- Granted full CRUD to `authenticated` role, read-only to `anon` role (blocked by RLS)
- Created 15 tests across 4 test classes

**Files created:**
- `backend/supabase/migrations/00003_create_partner_vaults_table.sql` — Full migration with table, CHECK constraint, RLS, trigger, and grants
- `backend/tests/test_partner_vaults_table.py` — 15 tests across 4 test classes (Exists, Schema, RLS, Triggers)

**Test results:**
- ✅ `pytest tests/test_partner_vaults_table.py -v` — 15 passed, 0 failed, 18.15s
- ✅ Table accessible via PostgREST API
- ✅ All 10 columns present (id, user_id, partner_name, relationship_tenure_months, cohabitation_status, location_city, location_state, location_country, created_at, updated_at)
- ✅ id is auto-generated UUID via gen_random_uuid()
- ✅ partner_name NOT NULL constraint enforced (missing name → HTTP 400)
- ✅ cohabitation_status CHECK constraint rejects invalid values
- ✅ All 3 valid cohabitation_status values accepted (living_together, separate, long_distance)
- ✅ location_country defaults to 'US' when not provided
- ✅ user_id UNIQUE constraint enforced (second vault for same user → HTTP 409)
- ✅ created_at auto-populated via DEFAULT now()
- ✅ Anon client (no JWT) sees 0 vaults — RLS enforced
- ✅ Service client (admin) can read all vaults — RLS bypassed
- ✅ User isolation verified: each user sees only their own vault
- ✅ set_updated_at trigger updates timestamp on row changes
- ✅ CASCADE delete verified: auth deletion removes vault row (auth.users → users → partner_vaults)
- ✅ Foreign key enforced: non-existent user_id rejected (HTTP 409)
- ✅ All existing tests still pass (38 from Steps 0.5–1.1)

**Notes:**
- Unlike the `users` table where `id` directly references `auth.users.id`, `partner_vaults` uses its own auto-generated `id` and links via `user_id`. This is because the vault is a child entity — one user has one vault, but the vault's identity is independent.
- The `UNIQUE` constraint on `user_id` automatically creates an implicit index, so no separate index was needed.
- The DELETE policy was added (unlike the `users` table) because users may need to delete and recreate their vault during profile management. Future tables (interests, milestones, vibes, etc.) will reference `partner_vaults.id` with CASCADE, so deleting a vault will cascade-clean all child data.
- The test file introduces a `test_auth_user_pair` fixture for creating two users simultaneously, used to verify RLS isolation between different users' vaults.
- PostgREST returns HTTP 409 for UNIQUE and foreign key constraint violations, and HTTP 400 for NOT NULL and CHECK constraint violations.
- Run tests with: `cd backend && source venv/bin/activate && pytest tests/test_partner_vaults_table.py -v`

---

### Step 1.3: Create Interests Table ✅
**Date:** February 6, 2026  
**Status:** Complete

**What was done:**
- Created `partner_interests` table with 5 columns for storing partner likes and dislikes
- `id` is auto-generated UUID via `gen_random_uuid()` (same pattern as `partner_vaults`)
- `vault_id` is a NOT NULL FK to `partner_vaults(id)` with `ON DELETE CASCADE`
- `interest_type` has a CHECK constraint for 2 valid enum values: `like`, `dislike`
- `interest_category` has a CHECK constraint for all 40 predefined interest categories (matching `iOS/Knot/Core/Constants.swift`)
- `UNIQUE(vault_id, interest_category)` composite constraint prevents:
  - Duplicate categories for the same vault
  - The same category appearing as both a like AND a dislike
- Enabled RLS with 4 policies (SELECT, INSERT, UPDATE, DELETE) using subquery to `partner_vaults` to check `auth.uid() = user_id` (since interests don't have a direct `user_id` column)
- Created index on `vault_id` for fast lookups (in addition to the composite unique index)
- Granted full CRUD to `authenticated` role, read-only to `anon` role (blocked by RLS)
- Created 22 tests across 5 test classes
- "Exactly 5 likes and 5 dislikes per vault" enforcement deferred to application layer (Step 3.10 API endpoint)

**Files created:**
- `backend/supabase/migrations/00004_create_partner_interests_table.sql` — Full migration with table, CHECK constraints (interest_type + interest_category), UNIQUE constraint, RLS, index, and grants
- `backend/tests/test_partner_interests_table.py` — 22 tests across 5 test classes (Exists, Schema, RLS, DataIntegrity, Cascades)

**Test results:**
- ✅ `pytest tests/test_partner_interests_table.py -v` — 22 passed, 0 failed, 45.66s
- ✅ Table accessible via PostgREST API
- ✅ All 5 columns present (id, vault_id, interest_type, interest_category, created_at)
- ✅ id is auto-generated UUID via gen_random_uuid()
- ✅ created_at auto-populated via DEFAULT now()
- ✅ interest_type CHECK constraint rejects invalid values (e.g., 'love')
- ✅ interest_type accepts both 'like' and 'dislike'
- ✅ interest_category CHECK constraint rejects invalid categories (e.g., 'Underwater Basket Weaving')
- ✅ All 40 valid interest categories accepted
- ✅ UNIQUE(vault_id, interest_category) prevents duplicate categories
- ✅ UNIQUE constraint prevents same category as both like and dislike (e.g., "Hiking" as both like and dislike → HTTP 409)
- ✅ interest_category NOT NULL enforced
- ✅ interest_type NOT NULL enforced
- ✅ Anon client (no JWT) sees 0 interests — RLS enforced
- ✅ Service client (admin) can read all interests — RLS bypassed
- ✅ User isolation verified: each vault sees only its own interests
- ✅ 5 likes + 5 dislikes inserted and retrieved correctly
- ✅ No overlap between likes and dislikes
- ✅ All stored interests from predefined list
- ✅ CASCADE delete verified: vault deletion removes interest rows
- ✅ Full CASCADE chain verified: auth.users → users → partner_vaults → partner_interests
- ✅ Foreign key enforced: non-existent vault_id rejected (HTTP 409)

**Notes:**
- RLS policies for child tables (like `partner_interests`) use a subquery pattern: `EXISTS (SELECT 1 FROM partner_vaults WHERE partner_vaults.id = partner_interests.vault_id AND partner_vaults.user_id = auth.uid())`. This is necessary because child tables don't have a direct `user_id` column — they inherit access control through their parent vault.
- The `UNIQUE(vault_id, interest_category)` constraint automatically creates a composite B-tree index on both columns. A separate single-column index on `vault_id` was also added for queries that filter only by `vault_id` (e.g., "get all interests for a vault").
- The implementation plan says "41 categories" but the actual predefined list (in both the plan and `Constants.swift`) contains 40 categories. The CHECK constraint matches the 40 listed categories exactly.
- The "exactly 5 likes and 5 dislikes" rule cannot be enforced at the database level with CHECK constraints (since PostgreSQL CHECK constraints operate on single rows, not across multiple rows). This will be enforced at the API layer in Step 3.10 via Pydantic validation in the `POST /api/v1/vault` endpoint.
- The CASCADE chain is now 4 levels deep: `auth.users` → `public.users` → `partner_vaults` → `partner_interests`.
- The test file introduces two new fixtures: `test_vault_with_interests` (creates a vault pre-populated with 5 likes and 5 dislikes) and `_insert_interest_raw` (returns the raw HTTP response for testing failure cases).
- Run tests with: `cd backend && source venv/bin/activate && pytest tests/test_partner_interests_table.py -v`

---

### Step 1.4: Create Milestones Table ✅
**Date:** February 6, 2026  
**Status:** Complete

**What was done:**
- Created `partner_milestones` table with 8 columns for storing partner milestones (birthdays, anniversaries, holidays, custom events)
- `id` is auto-generated UUID via `gen_random_uuid()` (same pattern as `partner_vaults` and `partner_interests`)
- `vault_id` is a NOT NULL FK to `partner_vaults(id)` with `ON DELETE CASCADE`
- `milestone_type` has a CHECK constraint for 4 valid enum values: `birthday`, `anniversary`, `holiday`, `custom`
- `milestone_name` is NOT NULL — display name for the milestone
- `milestone_date` is NOT NULL DATE — for yearly recurrence, uses year 2000 as placeholder (e.g., `2000-02-14` for Feb 14)
- `recurrence` has a CHECK constraint for 2 valid enum values: `yearly`, `one_time`
- `budget_tier` has a CHECK constraint for 3 valid enum values: `just_because`, `minor_occasion`, `major_milestone`
- Created `handle_milestone_budget_tier()` BEFORE INSERT trigger function that auto-sets budget_tier based on milestone_type when not explicitly provided:
  - `birthday` → `major_milestone`
  - `anniversary` → `major_milestone`
  - `holiday` → `minor_occasion` (app layer can override to `major_milestone` for Valentine's/Christmas by explicitly providing it)
  - `custom` → trigger does not set a default; NOT NULL constraint rejects NULL, forcing the user to provide a value
- Enabled RLS with 4 policies (SELECT, INSERT, UPDATE, DELETE) using the subquery pattern through `partner_vaults` to check `auth.uid() = user_id`
- Created index on `vault_id` for fast lookups
- Granted full CRUD to `authenticated` role, read-only to `anon` role (blocked by RLS)
- No UNIQUE constraint on `(vault_id, milestone_type)` — a vault can have multiple milestones of the same type (e.g., multiple holidays)
- Created 28 tests across 6 test classes

**Files created:**
- `backend/supabase/migrations/00005_create_partner_milestones_table.sql` — Full migration with table, CHECK constraints (milestone_type + recurrence + budget_tier), trigger function for budget_tier defaults, RLS, index, and grants
- `backend/tests/test_partner_milestones_table.py` — 28 tests across 6 test classes (Exists, Schema, BudgetTierDefaults, RLS, DataIntegrity, Cascades)

**Test results:**
- ✅ `pytest tests/test_partner_milestones_table.py -v` — 28 passed, 0 failed, 39.23s
- ✅ Table accessible via PostgREST API
- ✅ All 8 columns present (id, vault_id, milestone_type, milestone_name, milestone_date, recurrence, budget_tier, created_at)
- ✅ id is auto-generated UUID via gen_random_uuid()
- ✅ created_at auto-populated via DEFAULT now()
- ✅ milestone_type CHECK constraint rejects invalid values (e.g., 'graduation')
- ✅ All 4 valid milestone_type values accepted (birthday, anniversary, holiday, custom)
- ✅ recurrence CHECK constraint rejects invalid values (e.g., 'weekly')
- ✅ Both 'yearly' and 'one_time' recurrence values accepted
- ✅ budget_tier CHECK constraint rejects invalid values (e.g., 'extravagant')
- ✅ milestone_name NOT NULL constraint enforced
- ✅ milestone_date NOT NULL constraint enforced
- ✅ milestone_date stores year-2000 placeholder correctly (e.g., '2000-07-04')
- ✅ Birthday auto-defaults budget_tier to 'major_milestone' via trigger
- ✅ Anniversary auto-defaults budget_tier to 'major_milestone' via trigger
- ✅ Holiday auto-defaults budget_tier to 'minor_occasion' via trigger
- ✅ Holiday accepts explicit 'major_milestone' override (e.g., Valentine's Day)
- ✅ Custom milestones store all 3 user-provided budget_tier values
- ✅ Custom milestones without budget_tier correctly rejected (NOT NULL)
- ✅ Anon client (no JWT) sees 0 milestones — RLS enforced
- ✅ Service client (admin) can read all milestones — RLS bypassed
- ✅ User isolation verified: each vault sees only its own milestones
- ✅ Multiple milestones per vault stored correctly (4 test milestones)
- ✅ Birthday milestone fields verified (name, date, recurrence, budget_tier)
- ✅ Custom milestone fields verified (name, date, recurrence, budget_tier)
- ✅ Duplicate milestone types allowed (multiple holidays for same vault)
- ✅ CASCADE delete verified: vault deletion removed milestone rows
- ✅ Full CASCADE chain verified: auth.users → users → partner_vaults → partner_milestones
- ✅ Foreign key enforced: non-existent vault_id rejected
- ✅ All existing tests still pass (103 total from Steps 0.5–1.4, 2 warnings from third-party code)

**Notes:**
- Unlike `partner_interests` which has a UNIQUE constraint on `(vault_id, interest_category)`, `partner_milestones` has NO unique constraint on `(vault_id, milestone_type)`. A vault can have multiple milestones of the same type (e.g., multiple holidays like Christmas, Valentine's Day, New Year's Eve). This is intentional.
- The `handle_milestone_budget_tier()` trigger function is specific to this table (unlike `handle_updated_at()` which is reusable). It uses a `CASE` statement on `milestone_type` to determine the default. The trigger only fires when `budget_tier IS NULL` — if an explicit value is provided, the trigger does not override it.
- For yearly milestones, the `milestone_date` uses year 2000 as a placeholder (e.g., `2000-03-15` for March 15). The actual year is calculated dynamically by the application when determining "days until next occurrence."
- The holiday budget_tier split (Valentine's/Christmas = `major_milestone` vs Mother's Day/Father's Day = `minor_occasion`) is handled at the application layer by explicitly providing `budget_tier: 'major_milestone'` for major holidays. The database trigger defaults holidays to `minor_occasion` as the safe default.
- The CASCADE chain is now 4 levels deep (same depth as interests): `auth.users` → `public.users` → `partner_vaults` → `partner_milestones`.
- The test file introduces `test_vault_with_milestones` fixture (vault pre-populated with 4 milestones: birthday, anniversary, Valentine's Day holiday, custom "First Date") and `_insert_milestone_raw` helper for testing failure responses.
- Run tests with: `cd backend && source venv/bin/activate && pytest tests/test_partner_milestones_table.py -v`

---

### Step 1.5: Create Aesthetic Vibes Table ✅
**Date:** February 6, 2026  
**Status:** Complete

**What was done:**
- Created `partner_vibes` table with 4 columns for storing partner aesthetic vibe tags
- `id` is auto-generated UUID via `gen_random_uuid()` (same pattern as other child tables)
- `vault_id` is a NOT NULL FK to `partner_vaults(id)` with `ON DELETE CASCADE`
- `vibe_tag` has a CHECK constraint for 8 valid enum values: `quiet_luxury`, `street_urban`, `outdoorsy`, `vintage`, `minimalist`, `bohemian`, `romantic`, `adventurous`
- `UNIQUE(vault_id, vibe_tag)` composite constraint prevents duplicate vibes per vault (same pattern as `partner_interests`)
- Enabled RLS with 4 policies (SELECT, INSERT, UPDATE, DELETE) using the subquery pattern through `partner_vaults` to check `auth.uid() = user_id`
- Created index on `vault_id` for fast lookups (in addition to the composite unique index)
- Granted full CRUD to `authenticated` role, read-only to `anon` role (blocked by RLS)
- Created 19 tests across 5 test classes
- "Minimum 1, maximum 4 vibes per vault" enforcement deferred to application layer (Step 3.10 API endpoint)

**Files created:**
- `backend/supabase/migrations/00006_create_partner_vibes_table.sql` — Full migration with table, CHECK constraint (vibe_tag), UNIQUE constraint, RLS, index, and grants
- `backend/tests/test_partner_vibes_table.py` — 19 tests across 5 test classes (Exists, Schema, RLS, DataIntegrity, Cascades)

**Test results:**
- ✅ `pytest tests/test_partner_vibes_table.py -v` — 19 passed, 0 failed, 31.13s
- ✅ Table accessible via PostgREST API
- ✅ All 4 columns present (id, vault_id, vibe_tag, created_at)
- ✅ id is auto-generated UUID via gen_random_uuid()
- ✅ created_at auto-populated via DEFAULT now()
- ✅ vibe_tag CHECK constraint rejects invalid values (e.g., 'fancy')
- ✅ All 8 valid vibe_tag values accepted
- ✅ vibe_tag NOT NULL constraint enforced
- ✅ UNIQUE(vault_id, vibe_tag) prevents duplicate vibes per vault
- ✅ Same vibe_tag allowed for different vaults (UNIQUE scoped to vault)
- ✅ Anon client (no JWT) sees 0 vibes — RLS enforced
- ✅ Service client (admin) can read all vibes — RLS bypassed
- ✅ User isolation verified: each vault sees only its own vibes
- ✅ Multiple vibes per vault stored correctly (3 test vibes)
- ✅ Vibe tag field values verified (vault_id, vibe_tag)
- ✅ 4 vibes stored successfully (max for onboarding)
- ✅ Single vibe stored and retrievable (minimum for onboarding)
- ✅ CASCADE delete verified: vault deletion removed vibe rows
- ✅ Full CASCADE chain verified: auth.users → users → partner_vaults → partner_vibes
- ✅ Foreign key enforced: non-existent vault_id rejected
- ✅ All existing tests still pass (122 total from Steps 0.5–1.5, 2 warnings from third-party code)

**Notes:**
- The `partner_vibes` table is the simplest child table so far — no trigger functions, no computed defaults, just a straight tag storage table with a CHECK constraint for the 8 valid vibe values.
- The `UNIQUE(vault_id, vibe_tag)` constraint follows the same pattern as `partner_interests` — it prevents the same vibe from appearing twice for a vault. Unlike interests (which use the UNIQUE to also prevent like+dislike conflicts), vibes have no such dual-purpose need. The UNIQUE here is purely for deduplication.
- The "1-4 vibes per vault" cardinality rule cannot be enforced at the database level (PostgreSQL CHECK constraints operate on single rows, not across multiple rows). This will be enforced at the API layer in Step 3.10 via Pydantic validation in the `POST /api/v1/vault` endpoint, alongside the "exactly 5 likes and 5 dislikes" rule for interests.
- The CASCADE chain is now 4 levels deep (same depth as interests and milestones): `auth.users` → `public.users` → `partner_vaults` → `partner_vibes`.
- The test file introduces `test_vault_with_vibes` fixture (vault pre-populated with 3 vibes: quiet_luxury, minimalist, romantic) and `_insert_vibe_raw` helper for testing failure responses.
- Run tests with: `cd backend && source venv/bin/activate && pytest tests/test_partner_vibes_table.py -v`

---

### Step 1.6: Create Budget Tiers Table ✅
**Date:** February 6, 2026  
**Status:** Complete

**What was done:**
- Created `partner_budgets` table with 7 columns for storing partner budget tiers per occasion type
- `id` is auto-generated UUID via `gen_random_uuid()` (same pattern as other child tables)
- `vault_id` is a NOT NULL FK to `partner_vaults(id)` with `ON DELETE CASCADE`
- `occasion_type` has a CHECK constraint for 3 valid enum values: `just_because`, `minor_occasion`, `major_milestone`
- `min_amount` and `max_amount` are NOT NULL integers storing amounts in **cents** (e.g., 2000 = $20.00) to avoid floating-point precision issues
- `CHECK (min_amount >= 0)` prevents negative amounts
- `CHECK (max_amount >= min_amount)` prevents invalid budget ranges (max below min)
- `currency` defaults to `'USD'` — international users can override (e.g., `'GBP'`, `'EUR'`)
- `UNIQUE(vault_id, occasion_type)` prevents duplicate occasion types per vault — each vault has at most one budget per tier
- Enabled RLS with 4 policies (SELECT, INSERT, UPDATE, DELETE) using the subquery pattern through `partner_vaults` to check `auth.uid() = user_id`
- Created index on `vault_id` for fast lookups (in addition to the composite unique index)
- Granted full CRUD to `authenticated` role, read-only to `anon` role (blocked by RLS)
- No trigger functions needed — budgets are simple value storage with no computed defaults
- "Exactly 3 budget tiers per vault" enforcement deferred to application layer (Step 3.10 API endpoint)
- Created 27 tests across 5 test classes

**Files created:**
- `backend/supabase/migrations/00007_create_partner_budgets_table.sql` — Full migration with table, CHECK constraints (occasion_type + max>=min + min>=0), UNIQUE constraint, RLS, index, and grants
- `backend/tests/test_partner_budgets_table.py` — 27 tests across 5 test classes (Exists, Schema, RLS, DataIntegrity, Cascades)

**Test results:**
- ✅ `pytest tests/test_partner_budgets_table.py -v` — 27 passed, 0 failed, 36.86s
- ✅ Table accessible via PostgREST API
- ✅ All 7 columns present (id, vault_id, occasion_type, min_amount, max_amount, currency, created_at)
- ✅ id is auto-generated UUID via gen_random_uuid()
- ✅ created_at auto-populated via DEFAULT now()
- ✅ occasion_type CHECK constraint rejects invalid values (e.g., 'extravagant')
- ✅ All 3 valid occasion_type values accepted (just_because, minor_occasion, major_milestone)
- ✅ currency defaults to 'USD' when not provided
- ✅ currency accepts non-USD values (e.g., 'GBP')
- ✅ CHECK (max_amount >= min_amount) rejects invalid ranges (max < min)
- ✅ max_amount == min_amount allowed (exact budget, no range)
- ✅ CHECK (min_amount >= 0) rejects negative amounts
- ✅ occasion_type NOT NULL constraint enforced
- ✅ min_amount NOT NULL constraint enforced
- ✅ max_amount NOT NULL constraint enforced
- ✅ UNIQUE(vault_id, occasion_type) prevents duplicate occasion types per vault
- ✅ Same occasion_type allowed for different vaults (UNIQUE scoped to vault)
- ✅ Anon client (no JWT) sees 0 budgets — RLS enforced
- ✅ Service client (admin) can read all budgets — RLS bypassed
- ✅ User isolation verified: each vault sees only its own budgets
- ✅ All 3 budget tiers stored and retrieved correctly
- ✅ Budget amounts stored correctly (just_because $20-$50, minor_occasion $50-$150, major_milestone $100-$500)
- ✅ All field values verified (vault_id, currency)
- ✅ Amounts stored as integers (cents) — no floating-point issues
- ✅ Zero min_amount allowed (free/no minimum)
- ✅ CASCADE delete verified: vault deletion removed budget rows
- ✅ Full CASCADE chain verified: auth.users → users → partner_vaults → partner_budgets
- ✅ Foreign key enforced: non-existent vault_id rejected
- ✅ All existing tests still pass (122 from Steps 0.5–1.5 + 27 new = 149 total)

**Notes:**
- The `partner_budgets` table stores monetary amounts as **integers in cents** (not dollars/floats). This is a standard pattern for financial data to avoid floating-point precision issues. For display, divide by 100: `2000 cents → $20.00`. The API layer and iOS UI must convert between cents and display amounts.
- The `UNIQUE(vault_id, occasion_type)` constraint ensures each vault has at most one budget configuration per occasion type (just_because, minor_occasion, major_milestone). This means updating a budget tier requires an UPDATE on the existing row, not inserting a new one.
- The `CHECK (max_amount >= min_amount)` constraint is a cross-column CHECK — unlike CHECK constraints in other tables which only validate a single column's value. PostgreSQL supports cross-column CHECKs within the same row, making this enforceable at the database level (unlike cross-row cardinality rules which must go in the API layer).
- The `currency` column defaults to `'USD'` but accepts any string (no CHECK constraint). ISO 4217 currency code validation (e.g., only 3-letter codes) will be enforced at the API layer for flexibility.
- The CASCADE chain is now 4 levels deep (same depth as interests, milestones, and vibes): `auth.users` → `public.users` → `partner_vaults` → `partner_budgets`.
- The test file introduces `test_vault_with_budgets` fixture (vault pre-populated with 3 budget tiers matching the sensible defaults from the implementation plan: $20-$50, $50-$150, $100-$500) and `_insert_budget_raw` helper for testing failure responses.
- Run tests with: `cd backend && source venv/bin/activate && pytest tests/test_partner_budgets_table.py -v`

---

### Step 1.7: Create Love Languages Table ✅
**Date:** February 6, 2026  
**Status:** Complete

**What was done:**
- Created `partner_love_languages` table with 5 columns for storing a partner's primary and secondary love languages
- `id` is auto-generated UUID via `gen_random_uuid()` (same pattern as other child tables)
- `vault_id` is a NOT NULL FK to `partner_vaults(id)` with `ON DELETE CASCADE`
- `language` has a CHECK constraint for 5 valid enum values: `words_of_affirmation`, `acts_of_service`, `receiving_gifts`, `quality_time`, `physical_touch`
- `priority` has a CHECK constraint for 2 valid values: `1` (primary) and `2` (secondary)
- Two UNIQUE constraints enforce the "exactly one primary and one secondary" rule at the database level:
  - `UNIQUE(vault_id, priority)` — prevents duplicate priorities per vault (at most one primary, one secondary)
  - `UNIQUE(vault_id, language)` — prevents the same language from being both primary and secondary
- Combined with `CHECK(priority IN (1, 2))`, these constraints mean a vault can have at most 2 love language rows total — no valid priority slot exists for a third
- Enabled RLS with 4 policies (SELECT, INSERT, UPDATE, DELETE) using the subquery pattern through `partner_vaults` to check `auth.uid() = user_id`
- Created index on `vault_id` for fast lookups (in addition to the two composite unique indexes)
- Granted full CRUD to `authenticated` role, read-only to `anon` role (blocked by RLS)
- No trigger functions needed — love languages are simple value storage with no computed defaults
- "Exactly one primary and one secondary per vault" minimum cardinality enforced at API layer (Step 3.10); database enforces maximum cardinality
- Created 28 tests across 5 test classes

**Files created:**
- `backend/supabase/migrations/00008_create_partner_love_languages_table.sql` — Full migration with table, CHECK constraints (language + priority), two UNIQUE constraints (vault_id+priority, vault_id+language), RLS, index, and grants
- `backend/tests/test_partner_love_languages_table.py` — 28 tests across 5 test classes (Exists, Schema, RLS, DataIntegrity, Cascades)

**Test results:**
- ✅ `pytest tests/test_partner_love_languages_table.py -v` — 28 passed, 0 failed, 40.74s
- ✅ Table accessible via PostgREST API
- ✅ All 5 columns present (id, vault_id, language, priority, created_at)
- ✅ id is auto-generated UUID via gen_random_uuid()
- ✅ created_at auto-populated via DEFAULT now()
- ✅ language CHECK constraint rejects invalid values (e.g., 'gift_giving')
- ✅ All 5 valid language values accepted (words_of_affirmation, acts_of_service, receiving_gifts, quality_time, physical_touch)
- ✅ priority CHECK constraint rejects invalid values (e.g., 3, 0)
- ✅ Both valid priority values accepted (1=primary, 2=secondary)
- ✅ language NOT NULL constraint enforced
- ✅ priority NOT NULL constraint enforced
- ✅ UNIQUE(vault_id, priority) prevents duplicate primary love language
- ✅ UNIQUE(vault_id, priority) prevents duplicate secondary love language
- ✅ UNIQUE(vault_id, language) prevents same language as both primary and secondary
- ✅ Same language allowed for different vaults (UNIQUE scoped to vault)
- ✅ Third love language correctly rejected (no valid priority slot available)
- ✅ Anon client (no JWT) sees 0 love languages — RLS enforced
- ✅ Service client (admin) can read all love languages — RLS bypassed
- ✅ User isolation verified: each vault sees only its own love languages
- ✅ Primary and secondary love languages stored and retrieved correctly
- ✅ Love language field values verified (vault_id, language)
- ✅ Primary love language verified (quality_time, priority=1)
- ✅ Secondary love language verified (receiving_gifts, priority=2)
- ✅ Update primary to different language succeeded (quality_time → physical_touch)
- ✅ Update primary to same language as secondary correctly rejected (UNIQUE violation)
- ✅ CASCADE delete verified: vault deletion removed love language rows
- ✅ Full CASCADE chain verified: auth.users → users → partner_vaults → partner_love_languages
- ✅ Foreign key enforced: non-existent vault_id rejected
- ✅ All existing tests still pass (149 from Steps 0.5–1.6 + 28 new = 177 total)

**Notes:**
- The `partner_love_languages` table uses a **dual UNIQUE constraint** strategy to enforce the "exactly one primary, one secondary" rule at the database level as tightly as possible. `UNIQUE(vault_id, priority)` prevents multiple rows with the same priority, and `UNIQUE(vault_id, language)` prevents the same language from appearing at both priorities. Combined with `CHECK(priority IN (1, 2))`, the maximum cardinality is exactly 2 rows per vault — no third row can be inserted because all valid priority values are taken, and priority=3 is rejected by the CHECK constraint.
- The minimum cardinality (requiring that both a primary AND secondary exist) cannot be enforced at the database level — PostgreSQL constraints operate on existing rows, not missing ones. This will be enforced at the API layer in Step 3.10 via Pydantic validation in the `POST /api/v1/vault` endpoint.
- Unlike `partner_budgets` (which uses `UNIQUE(vault_id, occasion_type)` for one-to-one mapping), `partner_love_languages` uses TWO UNIQUE constraints for different purposes: one for priority deduplication, one for language mutual exclusion. This is the first table with multiple UNIQUE constraints.
- Updating a love language (e.g., changing primary from `quality_time` to `physical_touch`) works via a standard PATCH/UPDATE on the existing row. Updating primary to the same language as secondary is correctly blocked by `UNIQUE(vault_id, language)`.
- The CASCADE chain is 4 levels deep (same as all other child tables): `auth.users` → `public.users` → `partner_vaults` → `partner_love_languages`.
- The test file introduces `test_vault_with_love_languages` fixture (vault pre-populated with primary=quality_time, secondary=receiving_gifts), `_insert_love_language_raw` helper for testing failure responses, and `_update_love_language` helper for testing updates.
- Run tests with: `cd backend && source venv/bin/activate && pytest tests/test_partner_love_languages_table.py -v`

---

### Step 1.8: Create Hints Table with Vector Embedding ✅
**Date:** February 6, 2026  
**Status:** Complete

**What was done:**
- Created `hints` table with 7 columns for storing user-captured hints about their partner with pgvector embeddings for semantic search
- `id` is auto-generated UUID via `gen_random_uuid()` (same pattern as other child tables)
- `vault_id` is a NOT NULL FK to `partner_vaults(id)` with `ON DELETE CASCADE`
- `hint_text` is NOT NULL TEXT — the raw text of the captured hint (max 500 chars enforced at API layer)
- `hint_embedding` is `vector(768)` — **nullable** to allow storing hints even if Vertex AI embedding generation fails or is pending
- `source` has a CHECK constraint for 2 valid enum values: `text_input`, `voice_transcription`
- `is_used` is BOOLEAN NOT NULL DEFAULT false — tracks whether the hint was used in a recommendation
- Created **HNSW index** on `hint_embedding` using `vector_cosine_ops` for fast cosine similarity nearest-neighbor search
- Created **`match_hints()` RPC function** for semantic similarity search via PostgREST, accepting query embedding, vault_id, similarity threshold, and match count; returns hints ordered by cosine similarity with a computed `similarity` score column
- Enabled RLS with 4 policies (SELECT, INSERT, UPDATE, DELETE) using the subquery pattern through `partner_vaults` to check `auth.uid() = user_id`
- Created index on `vault_id` for fast lookups
- Granted full CRUD to `authenticated` role, read-only to `anon` role (blocked by RLS)
- Granted EXECUTE on `match_hints()` to `authenticated` and `anon` roles
- No UNIQUE constraints — a vault can have unlimited hints (no cardinality limit at database level)
- No trigger functions needed — hints are simple value storage with no computed defaults
- Created 30 tests across 6 test classes

**Files created:**
- `backend/supabase/migrations/00009_create_hints_table.sql` — Full migration with table, CHECK constraint (source), RLS, vault_id index, HNSW vector index, match_hints() RPC function, and grants
- `backend/tests/test_hints_table.py` — 30 tests across 6 test classes (Exists, Schema, RLS, DataIntegrity, VectorSearch, Cascades)

**Test results:**
- ✅ `pytest tests/test_hints_table.py -v` — 30 passed, 0 failed, 44.46s
- ✅ Table accessible via PostgREST API
- ✅ All 7 columns present (id, vault_id, hint_text, hint_embedding, source, created_at, is_used)
- ✅ id is auto-generated UUID via gen_random_uuid()
- ✅ created_at auto-populated via DEFAULT now()
- ✅ source CHECK constraint rejects invalid values (e.g., 'siri_dictation')
- ✅ source accepts both 'text_input' and 'voice_transcription'
- ✅ hint_text NOT NULL constraint enforced
- ✅ source NOT NULL constraint enforced
- ✅ is_used defaults to false when not provided
- ✅ hint_embedding is nullable (NULL when not provided)
- ✅ hint_embedding accepts 768-dimension vector
- ✅ Anon client (no JWT) sees 0 hints — RLS enforced
- ✅ Service client (admin) can read all hints — RLS bypassed
- ✅ User isolation verified: each vault sees only its own hints
- ✅ Multiple hints per vault stored correctly (3 test hints)
- ✅ Hint field values verified (vault_id, hint_text)
- ✅ Mixed sources stored correctly (text_input and voice_transcription)
- ✅ is_used can be updated from false to true
- ✅ Hint stored without embedding (nullable)
- ✅ Hint stored with 768-dim embedding vector
- ✅ match_hints() RPC returns results from similarity search
- ✅ Similarity search ordered correctly by cosine similarity (1.000 > 0.707 > 0.110)
- ✅ Similarity threshold filters out low-similarity results (threshold 0.5 excluded hint at 0.110)
- ✅ match_count parameter limits returned results
- ✅ Similarity search scoped to vault (other vault's hints excluded)
- ✅ Similarity search skips hints without embeddings (NULL hint_embedding)
- ✅ CASCADE delete verified: vault deletion removed hint rows
- ✅ Full CASCADE chain verified: auth.users → users → partner_vaults → hints
- ✅ Foreign key enforced: non-existent vault_id rejected
- ✅ All existing tests still pass (177 from Steps 0.5–1.7 + 30 new = 207 total)

**Notes:**
- The `hints` table is the **first table with a pgvector column** (`hint_embedding vector(768)`). This column stores 768-dimensional embeddings generated by Vertex AI's `text-embedding-004` model. The embeddings enable semantic similarity search — finding hints that are conceptually related to a query (e.g., "birthday gift ideas" matching hints like "she mentioned wanting a new yoga mat").
- The `hint_embedding` column is **intentionally nullable**. While the normal flow (Step 4.4) generates the embedding synchronously before storage, making it nullable provides resilience: if the Vertex AI API is temporarily unavailable, the hint text can still be stored and the embedding backfilled later.
- The **HNSW (Hierarchical Navigable Small World) index** was chosen over IVFFlat because: (1) it doesn't require a pre-build step with existing data, (2) it provides better recall (accuracy), and (3) it incrementally updates as data is inserted. The `vector_cosine_ops` operator class enables cosine distance queries via the `<=>` operator.
- The **`match_hints()` RPC function** is necessary because PostgREST doesn't natively support pgvector operators like `<=>`. The function is called via `POST /rest/v1/rpc/match_hints` and accepts: `query_embedding` (768-dim vector as string), `query_vault_id` (UUID), `match_threshold` (float, default 0.0), `match_count` (int, default 10). It returns rows with a computed `similarity` column (1.0 = identical, 0.0 = orthogonal).
- The similarity search tests use **carefully crafted 768-dim vectors** to verify ordering: Vector A `[1,0,0,...]` has cosine similarity 1.0 to query `[1,0,0,...]`, Vector B `[0.7,0.7,0,...]` has similarity ~0.707, and Vector C `[0.1,0.9,0,...]` has similarity ~0.110. This confirms both the HNSW index and the `match_hints()` function work correctly.
- Unlike other child tables, `hints` has **no UNIQUE constraints** — a vault can have unlimited hints, and the same hint text can appear multiple times (e.g., if the user re-enters it). There are no cardinality limits at the database level.
- The `is_used` column enables the recommendation engine (Step 5.2) to mark hints that have been incorporated into recommendations, preventing over-reliance on the same hints and encouraging the user to capture fresh observations.
- The CASCADE chain is 4 levels deep (same as all other child tables): `auth.users` → `public.users` → `partner_vaults` → `hints`.
- The test file introduces `test_vault_with_hints` fixture (vault pre-populated with 3 hints without embeddings), `test_vault_with_embedded_hints` fixture (vault with 3 hints with crafted embedding vectors for similarity testing), `_insert_hint_raw` helper for testing failure responses, and `_make_vector` helper for creating 768-dim vector strings.
- Run tests with: `cd backend && source venv/bin/activate && pytest tests/test_hints_table.py -v`

---

### Step 1.9: Create Recommendations History Table ✅
**Date:** February 6, 2026  
**Status:** Complete

**What was done:**
- Created `recommendations` table with 11 columns for storing AI-generated gift, experience, and date recommendations
- `id` is auto-generated UUID via `gen_random_uuid()` (same pattern as other child tables)
- `vault_id` is a NOT NULL FK to `partner_vaults(id)` with `ON DELETE CASCADE`
- `milestone_id` is a **nullable** FK to `partner_milestones(id)` with `ON DELETE SET NULL` — recommendations can exist without a milestone (e.g., "just because" browsing), and deleting a milestone preserves the recommendation as historical data
- `recommendation_type` has a CHECK constraint for 3 valid enum values: `gift`, `experience`, `date`
- `title` is NOT NULL — every recommendation requires a display title
- `description`, `external_url`, `merchant_name`, `image_url` are nullable — external APIs may not always return all fields
- `price_cents` is nullable INTEGER with `CHECK (price_cents >= 0)` — follows the cents pattern from `partner_budgets`; NULL when price is unknown
- Enabled RLS with 4 policies (SELECT, INSERT, UPDATE, DELETE) using the subquery pattern through `partner_vaults` to check `auth.uid() = user_id`
- Created two indexes: `idx_recommendations_vault_id` for querying by vault, `idx_recommendations_milestone_id` for querying by milestone
- Granted full CRUD to `authenticated` role, read-only to `anon` role (blocked by RLS)
- No UNIQUE constraints — a vault can have unlimited recommendations (generated in batches of 3)
- No trigger functions needed — recommendations are direct value storage from the LangGraph pipeline
- Created 31 tests across 6 test classes

**Files created:**
- `backend/supabase/migrations/00010_create_recommendations_table.sql` — Full migration with table, CHECK constraints (recommendation_type + price_cents >= 0), RLS, indexes, and grants
- `backend/tests/test_recommendations_table.py` — 31 tests across 6 test classes (Exists, Schema, RLS, DataIntegrity, MilestoneFK, Cascades)

**Test results:**
- ✅ `pytest tests/test_recommendations_table.py -v` — 31 passed, 0 failed, 44.26s
- ✅ Table accessible via PostgREST API
- ✅ All 11 columns present (id, vault_id, milestone_id, recommendation_type, title, description, external_url, price_cents, merchant_name, image_url, created_at)
- ✅ id is auto-generated UUID via gen_random_uuid()
- ✅ created_at auto-populated via DEFAULT now()
- ✅ recommendation_type CHECK constraint rejects invalid values (e.g., 'coupon')
- ✅ All 3 valid recommendation_type values accepted (gift, experience, date)
- ✅ title NOT NULL constraint enforced
- ✅ recommendation_type NOT NULL constraint enforced
- ✅ milestone_id is nullable (NULL for 'just because' recommendations)
- ✅ description is nullable
- ✅ price_cents CHECK constraint rejects negative values (-100)
- ✅ price_cents accepts zero (free items)
- ✅ price_cents is nullable (price unknown)
- ✅ Anon client (no JWT) sees 0 recommendations — RLS enforced
- ✅ Service client (admin) can read all recommendations — RLS bypassed
- ✅ User isolation verified: each vault sees only its own recommendations
- ✅ 3 recommendations (Choice of Three) stored and retrieved correctly
- ✅ All fields populated and verified for gift recommendation (vault_id, milestone_id, type, title, description, url, price, merchant, image)
- ✅ All 3 recommendation types stored: gift, experience, date
- ✅ Recommendation correctly linked to milestone via milestone_id
- ✅ Recommendation stored without milestone ('just because')
- ✅ Prices stored as integers in cents (4999, 12000, 18000)
- ✅ External URLs stored correctly for merchant handoff
- ✅ Merchant names stored: ClassBento, Etsy, OpenTable
- ✅ Milestone deletion sets recommendation.milestone_id to NULL (SET NULL, preserves history)
- ✅ milestone_id FK constraint enforced (non-existent milestone_id rejected)
- ✅ CASCADE delete verified: vault deletion removed recommendation rows
- ✅ Full CASCADE chain verified: auth.users → users → partner_vaults → recommendations
- ✅ Foreign key enforced: non-existent vault_id rejected
- ✅ All existing tests still pass (207 from Steps 0.5–1.8 + 31 new = 238 total)

**Notes:**
- The `recommendations` table introduces a **new FK behavior**: `ON DELETE SET NULL` for `milestone_id`. All previous FK relationships in the schema use `ON DELETE CASCADE`. The SET NULL choice is deliberate — recommendations are historical records that should persist even if the milestone they were generated for is deleted. The `vault_id` FK still uses CASCADE because deleting a vault means the user is deleting all partner data.
- Unlike `partner_budgets` which requires `price_cents` to be NOT NULL, the `recommendations` table makes it nullable because external APIs (Yelp, Ticketmaster, etc.) may not always return pricing information. The CHECK constraint `(price_cents >= 0)` still applies when a value is provided.
- The table has **no UNIQUE constraints** (same pattern as `hints`). A vault can accumulate unlimited recommendations over time, and the same recommendation could theoretically be generated again (e.g., after a refresh cycle). Each batch of 3 is simply appended.
- Two indexes are created instead of the usual one: `idx_recommendations_vault_id` (for "show all recommendations for this vault") and `idx_recommendations_milestone_id` (for "show recommendations generated for this specific milestone"). The milestone index is the first non-vault_id index on a child table.
- The test file introduces `test_vault_with_milestone` fixture (vault with a birthday milestone), `test_vault_with_recommendations` fixture (vault with 3 recommendations linked to the milestone), `_insert_recommendation_raw` helper for testing failure responses, and sample recommendation constants (`SAMPLE_GIFT_REC`, `SAMPLE_EXPERIENCE_REC`, `SAMPLE_DATE_REC`).
- Run tests with: `cd backend && source venv/bin/activate && pytest tests/test_recommendations_table.py -v`

---

### Step 1.10: Create User Feedback Table ✅
**Date:** February 6, 2026  
**Status:** Complete

**What was done:**
- Created `recommendation_feedback` table with 7 columns for storing user feedback on AI-generated recommendations
- `id` is auto-generated UUID via `gen_random_uuid()` (same pattern as other tables)
- `recommendation_id` is a NOT NULL FK to `recommendations(id)` with `ON DELETE CASCADE` — deleting a recommendation removes its feedback
- `user_id` is a NOT NULL FK to `users(id)` with `ON DELETE CASCADE` — deleting a user removes their feedback
- `action` has a CHECK constraint for 5 valid enum values: `selected`, `refreshed`, `saved`, `shared`, `rated`
- `rating` has a CHECK constraint for values 1-5 (nullable — only provided for `rated` action)
- `feedback_text` is nullable TEXT for optional text feedback (e.g., "She loved the pottery class!")
- Enabled RLS with 4 policies (SELECT, INSERT, UPDATE, DELETE) using direct `user_id = auth.uid()` (unlike child tables that use vault subquery, feedback has a direct `user_id` column)
- Created two indexes: `idx_feedback_recommendation_id` (for querying feedback by recommendation) and `idx_feedback_user_id` (for querying feedback by user)
- Granted full CRUD to `authenticated` role, read-only to `anon` role (blocked by RLS)
- No UNIQUE constraints — multiple feedback entries per recommendation allowed (e.g., `selected` then `rated`)
- Created 27 tests across 5 test classes

**Files created:**
- `backend/supabase/migrations/00011_create_recommendation_feedback_table.sql` — Full migration with table, CHECK constraints (action + rating 1-5), RLS, indexes, and grants
- `backend/tests/test_recommendation_feedback_table.py` — 27 tests across 5 test classes (Exists, Schema, RLS, DataIntegrity, Cascades)

**Test results:**
- ✅ `pytest tests/test_recommendation_feedback_table.py -v` — 27 passed, 0 failed, ~40s
- ✅ Table accessible via PostgREST API
- ✅ All 7 columns present (id, recommendation_id, user_id, action, rating, feedback_text, created_at)
- ✅ id is auto-generated UUID via gen_random_uuid()
- ✅ created_at auto-populated via DEFAULT now()
- ✅ action CHECK constraint rejects invalid values (e.g., 'clicked')
- ✅ All 5 valid action values accepted (selected, refreshed, saved, shared, rated)
- ✅ action NOT NULL constraint enforced
- ✅ rating CHECK constraint rejects 0 (must be >= 1)
- ✅ rating CHECK constraint rejects 6 (must be <= 5)
- ✅ rating accepts all valid values (1, 2, 3, 4, 5)
- ✅ rating is nullable (NULL for non-rated actions)
- ✅ feedback_text is nullable
- ✅ feedback_text stores value correctly when provided
- ✅ Anon client (no JWT) sees 0 feedback rows — RLS enforced
- ✅ Service client (admin) can read all feedback — RLS bypassed
- ✅ User isolation verified: each user sees only their own feedback
- ✅ Feedback for 'selected' action stored and queried by recommendation_id
- ✅ Rated feedback with text stored correctly (action=rated, rating=4, text present)
- ✅ Multiple feedback entries per recommendation allowed (selected + rated)
- ✅ CASCADE delete verified: recommendation deletion removed feedback rows
- ✅ Full CASCADE delete verified: auth deletion removed feedback rows
- ✅ FK constraint enforced: non-existent recommendation_id rejected
- ✅ FK constraint enforced: non-existent user_id rejected
- ✅ All existing tests still pass (238 from Steps 0.5–1.9 + 27 new = 265 total)

**Notes:**
- The `recommendation_feedback` table uses **direct RLS** (`user_id = auth.uid()`) instead of the subquery pattern used by vault child tables. This is because feedback has its own `user_id` column — it doesn't need to traverse through `partner_vaults` to determine ownership. This is simpler and more performant for RLS evaluation.
- The table has **dual FK relationships**: `recommendation_id → recommendations` (CASCADE) and `user_id → users` (CASCADE). This means feedback can be deleted from two directions: when the recommendation is removed, or when the user account is deleted. Both paths cascade cleanly.
- No UNIQUE constraints are imposed — a user can submit multiple feedback entries for the same recommendation (e.g., `selected` when they pick it, then `rated` after the purchase). This models the real user journey where feedback accumulates over time.
- The `rating` column uses a range CHECK (`rating >= 1 AND rating <= 5`) rather than an IN check, which is more natural for numeric ranges and would support fractional ratings in the future if needed.
- The test file introduces `test_vault_with_recommendation` fixture (vault with a single gift recommendation), `test_feedback_selected` fixture (feedback entry with action='selected'), `_insert_feedback_raw` helper for testing failure responses, and `_delete_feedback` helper for cleanup.
- Run tests with: `cd backend && source venv/bin/activate && pytest tests/test_recommendation_feedback_table.py -v`

---

### Step 1.11: Create Notification Queue Table ✅
**Date:** February 6, 2026  
**Status:** Complete

**What was done:**
- Created `notification_queue` table with 8 columns for scheduling proactive milestone notifications
- `id` is auto-generated UUID via `gen_random_uuid()` (same pattern as other tables)
- `user_id` is a NOT NULL FK to `users(id)` with `ON DELETE CASCADE`
- `milestone_id` is a NOT NULL FK to `partner_milestones(id)` with `ON DELETE CASCADE` — deleting a milestone cancels its pending notifications
- `scheduled_for` is NOT NULL TIMESTAMPTZ — the exact timestamp when the notification should be sent
- `days_before` has a CHECK constraint for 3 valid integer values: `14`, `7`, `3` — the notification schedule cadence
- `status` has a CHECK constraint for 4 valid enum values: `pending`, `sent`, `failed`, `cancelled` — defaults to `'pending'`
- `sent_at` is nullable TIMESTAMPTZ — NULL until the notification is actually sent
- Enabled RLS with 4 policies (SELECT, INSERT, UPDATE, DELETE) using direct `user_id = auth.uid()` (same pattern as `recommendation_feedback`)
- Created three indexes: `idx_notification_queue_user_id`, `idx_notification_queue_milestone_id`, and a **partial composite index** `idx_notification_queue_status_scheduled` on `(status, scheduled_for) WHERE status = 'pending'` for the notification processing job
- Granted full CRUD to `authenticated` role, read-only to `anon` role (blocked by RLS)
- Created 26 tests across 5 test classes

**Files created:**
- `backend/supabase/migrations/00012_create_notification_queue_table.sql` — Full migration with table, CHECK constraints (days_before + status), DEFAULT status, RLS, indexes (including partial), and grants
- `backend/tests/test_notification_queue_table.py` — 26 tests across 5 test classes (Exists, Schema, RLS, DataIntegrity, Cascades)

**Test results:**
- ✅ `pytest tests/test_notification_queue_table.py -v` — 26 passed, 0 failed, ~36s
- ✅ Table accessible via PostgREST API
- ✅ All 8 columns present (id, user_id, milestone_id, scheduled_for, days_before, status, sent_at, created_at)
- ✅ id is auto-generated UUID via gen_random_uuid()
- ✅ created_at auto-populated via DEFAULT now()
- ✅ days_before CHECK constraint rejects invalid values (e.g., 10)
- ✅ days_before accepts all 3 valid values (14, 7, 3)
- ✅ days_before NOT NULL constraint enforced
- ✅ status CHECK constraint rejects invalid values (e.g., 'delivered')
- ✅ status defaults to 'pending' when not explicitly provided
- ✅ status accepts all 4 valid values (pending, sent, failed, cancelled)
- ✅ sent_at is nullable (NULL until sent)
- ✅ scheduled_for NOT NULL constraint enforced
- ✅ Anon client (no JWT) sees 0 notifications — RLS enforced
- ✅ Service client (admin) can read all notifications — RLS bypassed
- ✅ User isolation verified: each user sees only their own notifications
- ✅ Pending notification stored and queryable by status
- ✅ Three notifications per milestone (14, 7, 3 days before) stored and ordered correctly
- ✅ All field values verified (user_id, milestone_id, days_before, status, sent_at, scheduled_for)
- ✅ Status updated from 'pending' to 'sent' with sent_at populated
- ✅ Status updated from 'pending' to 'cancelled'
- ✅ CASCADE delete verified: milestone deletion removed notification rows
- ✅ Full CASCADE delete verified: auth deletion removed notification rows
- ✅ FK constraint enforced: non-existent milestone_id rejected
- ✅ FK constraint enforced: non-existent user_id rejected
- ✅ All existing tests still pass (265 from Steps 0.5–1.10 + 26 new = 291 total)

**Notes:**
- The `notification_queue` table introduces a **partial composite index**: `CREATE INDEX ... ON notification_queue (status, scheduled_for) WHERE status = 'pending'`. This is the first partial index in the schema. It only indexes rows where `status = 'pending'`, making it highly efficient for the notification processing job's query pattern: "find all pending notifications scheduled before NOW." Rows with status `sent`, `failed`, or `cancelled` are excluded from the index, keeping it compact.
- Like `recommendation_feedback`, the `notification_queue` uses **direct RLS** (`user_id = auth.uid()`) rather than the subquery pattern. Both tables have their own `user_id` column for direct ownership checks.
- The `milestone_id` FK uses `ON DELETE CASCADE` (unlike `recommendations.milestone_id` which uses `ON DELETE SET NULL`). The reasoning: notification queue entries for a deleted milestone are meaningless and should be cleaned up. Recommendations are historical records worth preserving; scheduled notifications for a nonexistent milestone are not.
- The `days_before` CHECK uses `IN (14, 7, 3)` for discrete valid values rather than a range CHECK. This matches the implementation plan's specification that notifications fire at exactly these three intervals.
- The `status` column defaults to `'pending'` via `DEFAULT 'pending'` — the first column in the schema with a text default (other defaults have been `now()` for timestamps, `gen_random_uuid()` for UUIDs, `'US'` for country, and `false` for booleans).
- The test file introduces `test_vault_with_milestone` fixture (vault with a birthday milestone), `test_notification_pending` fixture (single pending notification at 14 days), `test_three_notifications` fixture (notifications at 14, 7, 3 days), `_insert_notification_raw` helper for testing failure responses, `_update_notification` helper for testing status transitions, and `_future_timestamp` helper for generating ISO 8601 timestamps.
- Run tests with: `cd backend && source venv/bin/activate && pytest tests/test_notification_queue_table.py -v`

---

### Step 1.12: Create SwiftData Models (iOS) ✅
**Date:** February 6, 2026  
**Status:** Complete

**What was done:**
- Created 4 SwiftData `@Model` classes mirroring key database tables for local access
- Created `SyncStatus` enum (`synced`, `pendingUpload`, `pendingDownload`) shared by all models
- Each model stores `syncStatusRaw` as a `String` (SwiftData-compatible) with a computed `syncStatus` property for type-safe enum access
- Registered all 4 models in `KnotApp.swift`'s `ModelContainer` schema
- Removed the `.gitkeep` placeholder from the `Models/` folder
- Regenerated the Xcode project via `xcodegen generate`

**Files created:**
- `iOS/Knot/Models/SyncStatus.swift` — `SyncStatus` enum with `synced`, `pendingUpload`, `pendingDownload` cases (Codable + Sendable)
- `iOS/Knot/Models/PartnerVaultLocal.swift` — SwiftData model mirroring `partner_vaults` table (10 DB columns + syncStatus)
- `iOS/Knot/Models/HintLocal.swift` — SwiftData model mirroring `hints` table (6 DB columns + syncStatus; excludes `hint_embedding`)
- `iOS/Knot/Models/MilestoneLocal.swift` — SwiftData model mirroring `partner_milestones` table (8 DB columns + syncStatus)
- `iOS/Knot/Models/RecommendationLocal.swift` — SwiftData model mirroring `recommendations` table (10 DB columns + syncStatus)

**Files modified:**
- `iOS/Knot/App/KnotApp.swift` — Updated `Schema` to include all 4 SwiftData models: `PartnerVaultLocal.self`, `HintLocal.self`, `MilestoneLocal.self`, `RecommendationLocal.self`
- `iOS/Knot.xcodeproj/` — Regenerated via `xcodegen generate` with new model files

**Files removed:**
- `iOS/Knot/Models/.gitkeep` — No longer needed (real files in folder)

**Test results:**
- ✅ `xcodegen generate` completed successfully
- ✅ `xcodebuild build` — zero errors, zero warnings
- ✅ All 4 @Model classes compile with SwiftData macros
- ✅ SyncStatus enum compiles as Codable + Sendable
- ✅ ModelContainer initialization succeeds with all 4 model types
- ✅ Build verified on iPhone 17 Pro Simulator (iOS 26.2)

**Notes:**
- The `@Model` macro automatically adds `Sendable` conformance. Explicitly declaring `: Sendable` on `@Model` classes causes a "redundant conformance" warning in Swift 6. The explicit conformance was removed from all 4 model classes.
- `SyncStatus` is stored as a raw `String` (`syncStatusRaw`) in SwiftData because SwiftData requires all persisted properties to be simple types. The computed `syncStatus` property provides type-safe access to the enum. This pattern avoids SwiftData limitations with persisting custom enums directly.
- `HintLocal` deliberately **excludes** the `hint_embedding` column (`vector(768)`) from the Supabase `hints` table. Embeddings are only used server-side for semantic search via `match_hints()` RPC. Storing 768-float vectors on-device would waste ~3KB per hint with no local utility.
- `RecommendationLocal` renames `description` to `descriptionText` to avoid conflict with Swift's built-in `CustomStringConvertible.description` protocol requirement.
- All models use `UUID?` for `remoteID` (nullable) because a locally-created record won't have a Supabase ID until it's synced. The `?` nullable pattern enables offline-first creation.
- The models do NOT define SwiftData `@Relationship` links between them (e.g., vault → hints). This is intentional for MVP — relationships are managed via UUID foreign keys, matching the Supabase schema pattern. SwiftData relationships can be added in a future iteration if local query performance requires it.
- Run iOS build with: `cd iOS && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build -project Knot.xcodeproj -scheme Knot -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet`

---

### Step 2.1: Implement Apple Sign-In Button (iOS) ✅
**Date:** February 6, 2026  
**Status:** Complete

**What was done:**
- Created `SignInView` in `/Features/Auth/` displaying the standard `SignInWithAppleButton` from `AuthenticationServices`
- Designed a clean, minimalist sign-in screen with Knot branding (Lucide heart icon, title, tagline), three value proposition rows (gift, calendar, sparkles icons), and the Apple Sign-In button at the bottom
- Button styled with `.signInWithAppleButtonStyle(.black)`, 54pt height, 12pt rounded corners matching the shadcn-inspired design system
- Implemented `handleSignInResult()` that extracts the Apple credential (user ID, email, identity token) on success — ready for Supabase integration in Step 2.2
- Error handling: user cancellation (`ASAuthorizationError.canceled`) is silently ignored; other errors display an alert with the error description
- Created `Knot.entitlements` with `com.apple.developer.applesignin` capability
- Updated `project.yml` with `entitlements` path and `CODE_SIGN_ENTITLEMENTS` build setting
- Updated `ContentView.swift` to show `SignInView()` as the root view (session-based navigation will be added in Step 2.3)
- Removed the placeholder Lucide icon test view from `ContentView` (no longer needed — icons are verified in `SignInView`)

**Files created:**
- `iOS/Knot/Features/Auth/SignInView.swift` — Sign-in screen with Apple Sign-In button, branding, value props, error handling
- `iOS/Knot/Knot.entitlements` — Sign in with Apple entitlement (`com.apple.developer.applesignin: [Default]`)

**Files modified:**
- `iOS/project.yml` — Added `entitlements` section and `CODE_SIGN_ENTITLEMENTS` build setting to Knot target
- `iOS/Knot/App/ContentView.swift` — Simplified to show `SignInView()` as the root view
- `iOS/Knot.xcodeproj/` — Regenerated via `xcodegen generate` with new files and entitlements

**Test results:**
- ✅ `xcodegen generate` completed successfully
- ✅ `xcodebuild clean build` — zero errors, zero warnings (BUILD SUCCEEDED)
- ✅ Swift 6 strict concurrency: no warnings or errors
- ✅ SignInView renders on iPhone 17 Pro Simulator (iOS 26.2): heart icon, "Knot" title, tagline, 3 feature rows, Apple button, privacy text
- ✅ Tapping "Sign in with Apple" triggers the AuthenticationServices flow
- ✅ Error handling verified: error alert displays with correct error message
- ✅ User cancellation: silently handled (no alert shown)
- ✅ Full sign-in flow validated on Simulator: Apple Sign-In sheet appears, user selects email sharing preference, enters password, credential returned successfully with User ID, email (`ronniejones22@gmail.com`), and identity token (JWT starting with `eyJraWQi...`). Requires paid Apple Developer Program and correct team selection in Xcode (not "Personal Team").

**Notes:**
- The `SignInView` uses `SignInWithAppleButton(.signIn)` from `AuthenticationServices` — this is Apple's official SwiftUI component. It automatically adapts to light/dark mode and locale.
- `requestedScopes` is set to `[.email]` — Apple will prompt the user to share or hide their email. The `email` property on the credential is only non-nil on first sign-in (Apple returns `nil` on subsequent logins).
- The identity token (`credential.identityToken`) is a JWT that Supabase Auth will validate in Step 2.2 via `signInWithIdToken(provider: .apple, idToken: token)`.
- Error 1000 on the Simulator is a known limitation when: (a) the Simulator doesn't have an Apple ID signed in (Settings > Apple Account), or (b) the app's bundle ID isn't registered with the Sign in with Apple capability in the Apple Developer portal, or (c) the developer isn't enrolled in the paid Apple Developer Program.
- The `SignInFeatureRow` is a private component within `SignInView.swift` (not in `/Components/`) because it's specific to the sign-in screen and not reusable elsewhere.
- `DEVELOPMENT_TEAM` must be set in the Xcode project (either via `project.yml` or directly in Xcode's Signing & Capabilities tab) for Sign in with Apple to work on the Simulator.
- Run iOS build with: `cd iOS && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build -project Knot.xcodeproj -scheme Knot -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet`

---

### Step 2.2: Connect Apple Sign-In to Supabase Auth (iOS) ✅
**Date:** February 6, 2026  
**Status:** Complete

**What was done:**
- Created `SupabaseClient.swift` in `/Services/` — singleton `SupabaseManager` that initializes the Supabase Swift client with the project URL and anon key from `Constants.Supabase`
- Created `AuthViewModel.swift` in `/Features/Auth/` — `@Observable @MainActor` class that manages the full Apple-to-Supabase authentication flow
- Implemented OIDC nonce security: generates a cryptographically secure random nonce (`SecRandomCopyBytes`), hashes it with SHA-256 (`CryptoKit`), sets the hash on the Apple Sign-In request, and forwards the raw nonce to Supabase for verification
- After successful Apple Sign-In, extracts the identity token from `ASAuthorizationAppleIDCredential` and sends it to Supabase via `signInWithIdToken(credentials: OpenIDConnectCredentials(provider: .apple, idToken:, nonce:))`
- The Supabase Swift SDK automatically stores the returned session (access token, refresh token) in the iOS Keychain — no manual Keychain code required
- Added loading overlay with `ProgressView("Signing in...")` and `.regularMaterial` background while the Supabase network request is in flight
- Disabled the Apple Sign-In button during loading to prevent duplicate requests
- Added `Constants.Supabase` enum with `projectURL` and `anonKey` to `Constants.swift`
- Updated `project.yml` to set `DEVELOPMENT_TEAM: VN5G3R8J23` (persists across xcodegen regenerations) and added `entitlements.properties` to prevent XcodeGen from overwriting the entitlements file
- Removed `Services/.gitkeep` placeholder (replaced by `SupabaseClient.swift`)

**Files created:**
- `iOS/Knot/Services/SupabaseClient.swift` — Singleton `SupabaseManager.client` initialized with project URL and anon key. The SDK auto-stores sessions in Keychain.
- `iOS/Knot/Features/Auth/AuthViewModel.swift` — `@Observable @MainActor` class with: `configureRequest()` (nonce generation + SHA-256 hash), `handleResult()` (credential extraction + error handling), `signInWithSupabase()` (sends identity token to Supabase Auth). Exposes `isLoading`, `isAuthenticated`, `signInError`, `showError` for the UI.

**Files modified:**
- `iOS/Knot/Core/Constants.swift` — Added `Supabase` enum with `projectURL` (`https://nmruwlfvhkvkbcdncwaq.supabase.co`) and `anonKey` (publishable key, safe to embed)
- `iOS/Knot/Features/Auth/SignInView.swift` — Replaced `@State`-based error handling with `@State private var viewModel = AuthViewModel()`. Added loading overlay, disabled button during loading, wired `configureRequest` and `handleResult` to the `SignInWithAppleButton` closures.
- `iOS/project.yml` — Set `DEVELOPMENT_TEAM: VN5G3R8J23`, added `entitlements.properties` with `com.apple.developer.applesignin: [Default]` to survive xcodegen regenerations
- `iOS/Knot/Knot.entitlements` — Restored `com.apple.developer.applesignin` capability (was overwritten to empty by xcodegen)
- `iOS/Knot.xcodeproj/` — Regenerated via `xcodegen generate` with new files

**Files removed:**
- `iOS/Knot/Services/.gitkeep` — No longer needed (real file in folder)

**Test results:**
- ✅ `xcodegen generate` completed successfully
- ✅ `xcodebuild build` — zero errors, zero warnings (BUILD SUCCEEDED)
- ✅ Swift 6 strict concurrency: no warnings or errors
- ✅ Loading overlay appears while Supabase sign-in is in progress ("Signing in..." with material background)
- ✅ Apple Sign-In button disabled during loading (prevents duplicate requests)
- ✅ Full end-to-end flow validated on iPhone 17 Pro Simulator (iOS 26.2):
  - Apple Sign-In sheet appears → user authenticates → identity token extracted
  - Token forwarded to Supabase via `signInWithIdToken` with OIDC nonce
  - Supabase sign-in succeeded with User ID `27B4A75F-541C-41FF-B948-60281EC30E93`
  - Email: `ronniejones22@gmail.com`
  - Access token received (JWT starting with `eyJhbGciOiJFUzI1NiIs...`)
  - Session automatically stored in iOS Keychain by the Supabase Swift SDK
- ✅ User visible in Supabase dashboard → Authentication → Users (Apple provider)
- ✅ `handle_new_user` trigger auto-created a row in `public.users` table
- ✅ User cancellation: silently handled (no alert, no Supabase call)
- ✅ Error handling: alert displays with error message on failure

**Notes:**
- The `AuthViewModel` uses `@Observable @MainActor` — this is the modern SwiftUI pattern for view models that manage async state. `@Observable` (iOS 17+ Observation framework) provides automatic change tracking, `@MainActor` ensures all property access is on the main thread.
- The `configureRequest` method is `nonisolated` because `SignInWithAppleButton`'s request closure may not be `@MainActor`-isolated. It uses `MainActor.assumeIsolated` to safely store the nonce.
- The nonce utility methods (`randomNonceString`, `sha256`) are `nonisolated static` to avoid actor isolation overhead — they are pure functions with no side effects.
- The Supabase Swift SDK handles session storage in the iOS Keychain automatically. No manual Keychain code is needed. The session includes both access and refresh tokens, and the SDK handles token refresh transparently.
- `DEVELOPMENT_TEAM` must be `VN5G3R8J23` in `project.yml` (not empty string) for Sign in with Apple to work. After the xcodegen regeneration in Step 2.2 initially reset this to empty, causing error 1000, the fix was applied and now persists across regenerations.
- The `entitlements.properties` section in `project.yml` ensures XcodeGen generates the entitlements file with the correct content even if the file is deleted and regenerated.
- Run iOS build with: `cd iOS && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build -project Knot.xcodeproj -scheme Knot -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet`

---

### Step 2.3: Implement Session Persistence (iOS) ✅
**Date:** February 6, 2026  
**Status:** Complete

**What was done:**
- Updated `AuthViewModel` to listen for Supabase `authStateChanges` on app launch, restoring sessions from the iOS Keychain automatically
- Added `isCheckingSession` state that starts `true` and transitions to `false` after the initial session check (the `initialSession` event)
- Refactored `ContentView` into a three-state auth router: loading spinner (checking Keychain), Home screen (authenticated), Sign-In screen (not authenticated)
- Created `AuthViewModel` as `@State` in `ContentView` and injected it into the SwiftUI environment so `SignInView` and `HomeView` share the same auth state
- Updated `SignInView` to read the shared `AuthViewModel` from `@Environment` instead of creating its own `@State` instance
- Created placeholder `HomeView` in `Features/Home/` showing welcome branding and session status indicator (full Home screen deferred to Phase 4)
- Removed manual `isAuthenticated = true` from `signInWithSupabase()` — auth state is now driven entirely by the `authStateChanges` listener (`signedIn` event sets it to `true`, `signedOut` sets it to `false`)
- Added `isListening` guard to prevent duplicate listener tasks if `listenForAuthChanges()` is called more than once
- Removed `Features/.gitkeep` placeholder (replaced by real feature folders: `Auth/`, `Home/`)
- Regenerated Xcode project via `xcodegen generate`

**Files created:**
- `iOS/Knot/Features/Home/HomeView.swift` — Placeholder Home screen with Knot branding, welcome message, and Lucide `circleCheck` icon. Reads `AuthViewModel` from environment (ready for sign-out in Step 2.4). Full implementation in Step 4.1.

**Files modified:**
- `iOS/Knot/Features/Auth/AuthViewModel.swift` — Added `isCheckingSession` (starts `true`), `isListening` (prevents duplicate listeners), `listenForAuthChanges()` async method (listens to Supabase `authStateChanges` stream). Handles 5 events: `initialSession` (restore from Keychain), `signedIn`, `signedOut`, `tokenRefreshed`, `userUpdated`. Removed manual `isAuthenticated = true` from `signInWithSupabase()`.
- `iOS/Knot/App/ContentView.swift` — Refactored from unconditional `SignInView()` to three-state auth router. Creates `@State AuthViewModel`, injects via `.environment()`, calls `listenForAuthChanges()` via `.task`. Shows `ProgressView` during session check, `HomeView` when authenticated, `SignInView` when not.
- `iOS/Knot/Features/Auth/SignInView.swift` — Changed from `@State private var viewModel = AuthViewModel()` to `@Environment(AuthViewModel.self) private var authViewModel`. Uses `@Bindable var viewModel = authViewModel` for the `.alert` binding. All action closures reference `authViewModel` directly.
- `iOS/Knot.xcodeproj/` — Regenerated via `xcodegen generate` with new `HomeView.swift` file

**Files removed:**
- `iOS/Knot/Features/.gitkeep` — No longer needed (real feature folders exist)

**Test results:**
- ✅ `xcodegen generate` completed successfully
- ✅ `xcodebuild build` — zero errors, zero warnings (BUILD SUCCEEDED)
- ✅ Swift 6 strict concurrency: no warnings or errors
- ✅ Session persistence verified: sign in → force-quit → relaunch → goes directly to Home screen (no re-sign-in required)
- ✅ No session: fresh install → shows Sign-In screen
- ✅ Auth state changes drive navigation reactively (signedIn → Home, signedOut → Sign-In)
- ✅ Loading spinner shown briefly during initial Keychain check (resolves in <100ms)
- ✅ Build verified on iPhone 17 Pro Simulator (iOS 26.2)

**Notes:**
- The Supabase Swift SDK's `authStateChanges` is an `AsyncSequence` that emits `(AuthChangeEvent, Session?)` tuples. The first event is always `initialSession`, which contains the session restored from Keychain (or `nil` if no session exists). This is the mechanism for session persistence — no manual Keychain code is needed.
- The `isCheckingSession` state prevents a flash of the Sign-In screen on app launch. Without it, `isAuthenticated` starts `false`, which would briefly show `SignInView` before the Keychain check completes and sets `isAuthenticated = true`. The loading spinner bridges this gap.
- `isAuthenticated` is no longer set manually in `signInWithSupabase()`. Instead, the `authStateChanges` listener handles it: Supabase SDK emits `signedIn` after a successful `signInWithIdToken`, which sets `isAuthenticated = true`. This ensures a single source of truth for auth state — all auth transitions flow through the listener.
- The `@Environment(AuthViewModel.self)` pattern is the modern SwiftUI approach for sharing `@Observable` objects. The environment injection in `ContentView` (`.environment(authViewModel)`) makes the same instance available to all descendant views. This replaces the older `@EnvironmentObject` pattern.
- The `@Bindable var viewModel = authViewModel` local variable in `SignInView` is necessary for the `.alert(isPresented: $viewModel.showError)` binding. SwiftUI's `@Environment` properties cannot be directly used with `$` binding syntax — the `@Bindable` wrapper provides this capability for `@Observable` objects.
- The `listenForAuthChanges()` async method runs for the lifetime of the root view (via `.task`). The `isListening` guard is a safety net to prevent multiple listener instances if `.task` is called more than once (e.g., during SwiftUI view lifecycle events).
- Lucide icon note: The library uses `Lucide.circleCheck` (not `checkCircle`). Lucide Swift follows the naming pattern `{shape}{action}` rather than `{action}{shape}`.
- Run iOS build with: `cd iOS && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build -project Knot.xcodeproj -scheme Knot -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet`

---

### Step 2.4: Implement Sign-Out (iOS) ✅
**Date:** February 6, 2026  
**Status:** Complete

**What was done:**
- Added `signOut()` async method to `AuthViewModel` that calls `SupabaseManager.client.auth.signOut()`
- The Supabase SDK handles three things on sign-out: (1) invalidates the session on the server, (2) removes tokens from the iOS Keychain, (3) emits a `signedOut` event via `authStateChanges`
- The existing `listenForAuthChanges()` listener catches the `signedOut` event and sets `isAuthenticated = false`, which causes `ContentView` to swap back to `SignInView` automatically
- Added a prominent "Sign Out" button to `HomeView` — red bordered button with Lucide `logOut` icon, full-width, 48pt height
- Added a toolbar button in the navigation bar (top-right) with the `logOut` icon for quick access
- Error handling: if `signOut()` throws, an alert is shown with "Sign-out failed. Please try again."
- No manual `isAuthenticated = false` assignment in `signOut()` — auth state is driven entirely by the `authStateChanges` listener (consistent with the pattern established in Step 2.3)

**Files modified:**
- `iOS/Knot/Features/Auth/AuthViewModel.swift` — Added `signOut()` async method in a new `// MARK: - Sign Out (Step 2.4)` section. Updated file header comment.
- `iOS/Knot/Features/Home/HomeView.swift` — Added full-width "Sign Out" button with Lucide `logOut` icon, toolbar button in navigation bar, updated file header and doc comment.

**Test results:**
- ✅ `xcodebuild build` — zero errors, zero warnings (BUILD SUCCEEDED)
- ✅ Swift 6 strict concurrency: no warnings or errors
- ✅ Sign in → tap "Sign Out" → Sign-In screen appears immediately
- ✅ After sign-out, force-quit and relaunch → Sign-In screen appears (session cleared from Keychain)
- ✅ Toolbar sign-out button works identically to the body button
- ✅ `authStateChanges` listener correctly handles `signedOut` event → `isAuthenticated = false`
- ✅ Build verified on iPhone 17 Pro Simulator (iOS 26.2)

**Notes:**
- The `signOut()` method follows the same pattern as `signInWithSupabase()` — it does NOT manually set `isAuthenticated = false`. Instead, it relies on the `authStateChanges` listener to handle the `signedOut` event. This maintains the single source of truth for auth state established in Step 2.3.
- Two sign-out UI affordances are provided: (1) a prominent red button at the bottom of the Home screen (visible for testing, will be moved to Settings in Step 11.1), and (2) a toolbar icon button in the navigation bar. The full Settings screen (Step 11.1) will be the permanent home for sign-out.
- The Supabase Swift SDK's `signOut()` is a server-side invalidation — it revokes the refresh token on the Supabase server, ensuring the session cannot be reused even if the Keychain is somehow restored. The local Keychain cleanup is also handled by the SDK.
- Run iOS build with: `cd iOS && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build -project Knot.xcodeproj -scheme Knot -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet`

---

### Step 3.1: Design Onboarding Flow Navigation (iOS) ✅
**Date:** February 7, 2026  
**Status:** Complete

**What was done:**
- Created `OnboardingViewModel` — `@Observable @MainActor` class managing all onboarding state across 9 steps
- Created `OnboardingStep` enum with 9 cases: welcome, basicInfo, interests, dislikes, milestones, vibes, budget, loveLanguages, completion
- Created `OnboardingContainerView` — navigation shell with animated progress bar, step content switching via `@ViewBuilder`, and Back/Next/Get Started buttons
- Created 9 placeholder step views in `Features/Onboarding/Steps/`, each reading the shared `OnboardingViewModel` from `@Environment`
- Added `hasCompletedOnboarding` flag to `AuthViewModel` for routing between Onboarding and Home
- Updated `ContentView` to route: authenticated + no vault → `OnboardingContainerView`, authenticated + vault → `HomeView`
- Progress bar animates between steps using `GeometryReader` with pink fill
- Step transitions use `.asymmetric` combined move+opacity animations
- Back button hidden on first step (Welcome), "Get Started" replaces "Next" on last step (Completion)
- `OnboardingViewModel` holds placeholder data properties for all future steps (partner name, interests, vibes, budgets, love languages, milestones) — ready for Steps 3.2–3.8 to populate

**Files created:**
- `iOS/Knot/Features/Onboarding/OnboardingViewModel.swift` — `OnboardingStep` enum (9 cases with title, isFirst, isLast, totalSteps) + `OnboardingViewModel` class (navigation state, data properties, goToNextStep/goToPreviousStep)
- `iOS/Knot/Features/Onboarding/OnboardingContainerView.swift` — Navigation container with progress bar, step content `@ViewBuilder`, Back/Next/Get Started buttons, `onComplete` closure
- `iOS/Knot/Features/Onboarding/Steps/OnboardingWelcomeView.swift` — Step 1: Welcome with Knot branding and checklist of vault sections
- `iOS/Knot/Features/Onboarding/Steps/OnboardingBasicInfoView.swift` — Step 2: Partner info placeholder (name, tenure, cohabitation, location)
- `iOS/Knot/Features/Onboarding/Steps/OnboardingInterestsView.swift` — Step 3: Interests placeholder (5 likes)
- `iOS/Knot/Features/Onboarding/Steps/OnboardingDislikesView.swift` — Step 4: Dislikes placeholder (5 hard avoids)
- `iOS/Knot/Features/Onboarding/Steps/OnboardingMilestonesView.swift` — Step 5: Milestones placeholder (birthday, anniversary, holidays)
- `iOS/Knot/Features/Onboarding/Steps/OnboardingVibesView.swift` — Step 6: Aesthetic vibes placeholder (1–4 vibes)
- `iOS/Knot/Features/Onboarding/Steps/OnboardingBudgetView.swift` — Step 7: Budget tiers placeholder (3 occasion types)
- `iOS/Knot/Features/Onboarding/Steps/OnboardingLoveLanguagesView.swift` — Step 8: Love languages placeholder (primary + secondary)
- `iOS/Knot/Features/Onboarding/Steps/OnboardingCompletionView.swift` — Step 9: Completion with success message and profile summary

**Files modified:**
- `iOS/Knot/App/ContentView.swift` — Added onboarding route: `isAuthenticated && !hasCompletedOnboarding` → `OnboardingContainerView`. Updated doc comments.
- `iOS/Knot/Features/Auth/AuthViewModel.swift` — Added `hasCompletedOnboarding` property (default `false`). Will be set `true` when vault is submitted (Step 3.11) or when existing vault is loaded on session restore.
- `iOS/Knot.xcodeproj/` — Regenerated via `xcodegen generate` with 12 new source files

**Test results:**
- ✅ `xcodegen generate` completed successfully
- ✅ `xcodebuild build` — zero errors, zero warnings (BUILD SUCCEEDED)
- ✅ Swift 6 strict concurrency: no warnings or errors
- ✅ After sign-in, onboarding flow appears (not Home screen)
- ✅ Navigate through all 9 steps using "Next" — each step is reachable
- ✅ Press "Back" — previous steps retain entered data (state lives in OnboardingViewModel)
- ✅ Progress bar animates correctly between steps (0% → 100%)
- ✅ Step counter updates ("Step 1 of 9" through "Step 9 of 9")
- ✅ Back button hidden on Welcome step (Step 1)
- ✅ "Get Started" button appears on Completion step (Step 9) — replaces "Next"
- ✅ Tapping "Get Started" transitions to Home screen
- ✅ Build verified on iPhone 17 Pro Simulator (iOS 26.2)

**Notes:**
- The `OnboardingContainerView` owns the `OnboardingViewModel` via `@State` and injects it into the environment via `.environment(viewModel)`. This is the same pattern used by `ContentView` with `AuthViewModel` — the container owns the state, child step views read it via `@Environment`.
- All 9 step views are placeholders with Lucide icons, titles, and gray rounded rectangles where the actual UI will go. Steps 3.2–3.8 will replace these placeholders with real form fields, chip grids, sliders, and date pickers.
- The `OnboardingViewModel` already contains all data properties needed for Steps 3.2–3.8 (partnerName, selectedInterests, selectedDislikes, selectedVibes, budget amounts, love languages, milestone data). These are pre-populated with sensible defaults so the placeholder views can reference them without crashing.
- The `canProceed` flag on `OnboardingViewModel` is currently always `true` (all placeholders allow proceeding). Steps 3.2–3.8 will set this to `false` when validation fails (e.g., name field empty, fewer than 5 interests selected).
- The `hasCompletedOnboarding` flag on `AuthViewModel` is currently in-memory only. It resets on app relaunch (new users will see onboarding again). Step 3.11 (Connect iOS Onboarding to Backend API) will persist this by checking whether a vault exists in Supabase when the session is restored.
- The step content uses `.id(viewModel.currentStep)` to force SwiftUI to create new views on step change, enabling the `.transition(.asymmetric(...))` animations. Without `.id()`, SwiftUI would try to diff the views in-place and the transition animation wouldn't fire.
- Run iOS build with: `cd iOS && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build -project Knot.xcodeproj -scheme Knot -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet`

---

### Step 3.2: Build Partner Basic Info Screen (iOS) ✅
**Date:** February 7, 2026  
**Status:** Complete

**What was done:**
- Replaced the `OnboardingBasicInfoView` placeholder with a full form collecting four data fields
- **Partner's Name** — `TextField` with `.givenName` content type, keyboard submit chaining (name → city → state → dismiss), and a deferred "Required" validation hint (only appears after user interaction via `hasInteractedWithName` flag to avoid jarring first-load UX)
- **Relationship Tenure** — Two inline `Picker` controls (`.menu` style, pink tint) for years (0–30) and months (0–11). Custom `Binding(get:set:)` objects decompose the ViewModel's single `relationshipTenureMonths: Int` into the two-component UI. A human-readable summary ("2 years, 6 months") displays below the pickers
- **Cohabitation Status** — `Picker` with `.segmented` style for three options: "Living Together", "Separate", "Long Distance". Includes contextual description text that updates dynamically with the selection
- **Location** — City and state `TextField`s (marked optional) with `.addressCity`/`.addressState` content types for iOS autofill. Lucide `mapPin` icon and helper text explain why location is useful for local recommendations
- Added centralized `validateCurrentStep()` method to `OnboardingViewModel` — called by `goToNextStep()`, `goToPreviousStep()`, and by the view's `.onAppear` / `.onChange(of: partnerName)` modifiers
- Validation rule: `canProceed = false` when `partnerName` (trimmed of whitespace) is empty; `true` otherwise
- Added `@FocusState` keyboard management with `Field` enum for submit-chaining between text fields
- Added `.scrollDismissesKeyboard(.interactively)` for smooth keyboard dismissal during scroll
- Added two `#Preview` variants: empty state and pre-filled state (for design iteration)
- Updated Xcode project to recommended settings (LastUpgradeCheck 2620, STRING_CATALOG_GENERATE_SYMBOLS)

**Files modified:**
- `iOS/Knot/Features/Onboarding/Steps/OnboardingBasicInfoView.swift` — Full rewrite from placeholder to complete form (62 lines → 312 lines). Header section, name field with deferred validation, tenure pickers with custom bindings, cohabitation segmented control with contextual description, location fields with mapPin icon and autofill support.
- `iOS/Knot/Features/Onboarding/OnboardingViewModel.swift` — Added `validateCurrentStep()` method with `.basicInfo` case (name required). Replaced `canProceed = true` resets in `goToNextStep()`/`goToPreviousStep()` with `validateCurrentStep()` calls. Future steps (3.3–3.8) will add cases to the switch.

**Test results:**
- ✅ `xcodegen generate` completed successfully
- ✅ `xcodebuild build` — zero errors, zero warnings (BUILD SUCCEEDED)
- ✅ Swift 6 strict concurrency: no warnings or errors
- ✅ Enter a name and select options → "Next" button enabled, navigation proceeds to Interests step
- ✅ Clear the name field → "Next" button disabled, "Name is required to continue" hint appears
- ✅ Relationship tenure pickers update `relationshipTenureMonths` correctly (e.g., 2 years + 6 months = 30 months)
- ✅ Cohabitation segmented control switches between all three options with contextual description
- ✅ Location fields accept text input with proper keyboard submit chaining
- ✅ Navigate forward → back → data persists (ViewModel state preserved across step transitions)
- ✅ Keyboard dismisses on scroll (`.scrollDismissesKeyboard(.interactively)`)
- ✅ Build verified on iPhone 17 Pro Simulator (iOS 26.2)

**Notes:**
- The `hasInteractedWithName` flag is `@State` (local to the view, reset on view recreation). Since `.id(viewModel.currentStep)` recreates the view on every step change, the "Required" hint resets when navigating away and back. This is intentional — the user already entered a name to leave the step, so the hint is unnecessary on return.
- The tenure pickers use `Binding(get:set:)` inside a computed property (`tenureSection`) because `@Bindable var vm = viewModel` is only available inside the `body` getter. The custom bindings decompose `relationshipTenureMonths` into years and months, and recompose them on set. Since `OnboardingViewModel` is `@Observable`, reads in the `get:` closure are tracked and writes in `set:` trigger view updates.
- The `validateCurrentStep()` method in the ViewModel provides a centralized switch statement for validation. This replaces the previous pattern of resetting `canProceed = true` in navigation methods. Each step's case defines its own validation rule. The `default` case returns `true` for placeholder steps that don't have validation yet.
- The view also calls `validateCurrentStep()` via `.onAppear` and `.onChange(of: partnerName)` to handle real-time validation as the user types. Both the ViewModel-level and view-level validation are kept in sync by calling the same method.
- Run iOS build with: `cd iOS && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build -project Knot.xcodeproj -scheme Knot -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet`

---

### Step 3.3: Build Interests Selection Screen (iOS) + App-Wide Design System ✅
**Date:** February 7, 2026  
**Status:** Complete

**What was done:**
- Built the full interests selection screen with a dark-themed 3-column image card grid, matching a reference design provided by the user
- Created `Theme.swift` — app-wide design system with centralized colors, gradients, and surfaces (dark purple aesthetic)
- Set `.preferredColorScheme(.dark)` at the app level in `KnotApp.swift` so the entire app uses dark mode
- Propagated the design system across ALL existing views: SignInView, ContentView, HomeView, OnboardingContainerView, OnboardingBasicInfoView, and all 9 onboarding step views
- Created `FlowLayout.swift` — a reusable `Layout` component for wrapping chip grids (will be reused by DislikesView Step 3.4 and VibesView Step 3.6)

**Interests Screen (OnboardingInterestsView) details:**
- **Personalized title:** "What does [name] love?" using the partner's name from Step 3.2
- **Search bar:** Rounded pill with magnifying glass icon, real-time filtering of the 40 interest categories, clear button
- **3-column card grid:** `LazyVGrid` with `InterestImageCard` components — each card has a themed gradient background (hue-rotated across 40 categories), an SF Symbol icon (e.g., airplane for Travel, flame for Cooking), interest name at bottom-left with text shadow, and dark gradient overlay for readability
- **Selection:** Exactly 5 required. Tapping selects (pink border + checkmark badge), tapping again deselects. 6th attempt triggers a horizontal shake animation
- **Counter:** "X selected (Y more needed)" in pink at the bottom, with checkmark icon when complete
- **Empty search state:** "No interests match..." message
- **Validation:** `.interests` case added to `OnboardingViewModel.validateCurrentStep()`: `canProceed = selectedInterests.count == 5`

**Design System (Theme.swift) details:**
- `Theme.backgroundTop` / `Theme.backgroundBottom` — dark purple gradient endpoints
- `Theme.backgroundGradient` — `LinearGradient` applied to major container views
- `Theme.surface` — `Color.white.opacity(0.08)` for cards, input fields, elevated content
- `Theme.surfaceElevated` — `Color.white.opacity(0.12)` for hover/pressed states
- `Theme.surfaceBorder` — `Color.white.opacity(0.12)` for borders
- `Theme.accent` — `Color.pink` (buttons, selected states, progress indicators)
- `Theme.textPrimary` / `.textSecondary` / `.textTertiary` — explicit white opacity levels
- `Theme.progressTrack` / `.progressFill` — progress bar colors

**Files created:**
- `iOS/Knot/Core/Theme.swift` — Centralized design system (dark purple aesthetic)
- `iOS/Knot/Components/FlowLayout.swift` — Reusable wrapping layout for chip grids

**Files modified:**
- `iOS/Knot/App/KnotApp.swift` — Added `.preferredColorScheme(.dark)` on ContentView
- `iOS/Knot/App/ContentView.swift` — Updated loading spinner with Theme colors and background gradient
- `iOS/Knot/Features/Auth/SignInView.swift` — Added Theme.backgroundGradient, changed Apple button to `.white` style, replaced hardcoded colors with Theme references
- `iOS/Knot/Features/Home/HomeView.swift` — Added Theme.backgroundGradient, replaced hardcoded colors with Theme references
- `iOS/Knot/Features/Onboarding/OnboardingContainerView.swift` — Added Theme.backgroundGradient, updated progress bar to Theme.progressTrack/progressFill, buttons to Theme.accent
- `iOS/Knot/Features/Onboarding/OnboardingViewModel.swift` — Added `.interests` validation case
- `iOS/Knot/Features/Onboarding/Steps/OnboardingInterestsView.swift` — Full rewrite: dark card grid with search, SF Symbol icons, themed gradients, shake animation. Removed view-level `.preferredColorScheme(.dark)` (now app-level)
- `iOS/Knot/Features/Onboarding/Steps/OnboardingBasicInfoView.swift` — Replaced `Color(.systemGray6)` with `Theme.surface`, `.tint(.pink)` with `Theme.accent`, added surface borders
- `iOS/Knot/Features/Onboarding/Steps/OnboardingWelcomeView.swift` — Replaced `.pink` with `Theme.accent`
- `iOS/Knot/Features/Onboarding/Steps/OnboardingDislikesView.swift` — Updated to Theme colors
- `iOS/Knot/Features/Onboarding/Steps/OnboardingMilestonesView.swift` — Updated to Theme colors
- `iOS/Knot/Features/Onboarding/Steps/OnboardingVibesView.swift` — Updated to Theme colors
- `iOS/Knot/Features/Onboarding/Steps/OnboardingBudgetView.swift` — Updated to Theme colors
- `iOS/Knot/Features/Onboarding/Steps/OnboardingLoveLanguagesView.swift` — Updated to Theme colors
- `iOS/Knot/Features/Onboarding/Steps/OnboardingCompletionView.swift` — Updated to Theme colors, added surface border

**Test results:**
- ✅ `xcodegen generate` completed successfully
- ✅ `xcodebuild build` — zero errors, zero warnings (BUILD SUCCEEDED)
- ✅ Swift 6 strict concurrency: no warnings or errors
- ✅ Tap 4 interests — "Next" disabled, counter shows "4 selected (1 more needed)"
- ✅ Tap a 5th — "Next" enables, counter shows "5 selected" with checkmark
- ✅ Tap a 6th — rejected with shake animation on the card
- ✅ Tap a selected interest — deselects, counter decrements
- ✅ Navigate forward then back — selections persist (ViewModel state preserved)
- ✅ Search bar filters interests in real-time
- ✅ Clear search restores full list
- ✅ Empty search shows "No interests match" message
- ✅ Dark theme consistent across all screens: Sign-In, Onboarding (all 9 steps), Home
- ✅ Apple Sign-In button renders as white-on-dark (high contrast)
- ✅ Progress bar uses Theme colors (dark track, pink fill)
- ✅ Form fields in BasicInfoView use Theme.surface with borders
- ✅ Build verified on iPhone 17 Pro Simulator (iOS 26.2)

**Notes:**
- The dark theme is set app-wide via `.preferredColorScheme(.dark)` on `KnotApp.swift`. Individual views do NOT need to set it — it propagates to the entire window.
- The background gradient is applied by each major container view (SignInView, OnboardingContainerView, HomeView) rather than at the app level, so views have flexibility to use different backgrounds in the future.
- Since the app is in permanent dark mode, SwiftUI semantic colors (`.primary`, `.secondary`, `.tertiary`) automatically resolve to light-on-dark values. Use `Theme.textSecondary` / `.textTertiary` only when you need the exact reference design opacity.
- The `FlowLayout` component was created for the initial chip design but is no longer used by the interests screen (which uses `LazyVGrid` for the card grid). Keep it for DislikesView (Step 3.4) and VibesView (Step 3.6) which may use chip layouts.
- SF Symbol icon mapping is a static dictionary in `OnboardingInterestsView`. All symbols target iOS 17.0+. If any symbol doesn't exist on a particular iOS version, the Image will render empty (graceful degradation).
- The card gradient uses hue rotation: `hue = index / count` spreads 40 categories across the full color wheel, ensuring visual uniqueness per card.
- Run iOS build with: `cd iOS && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build -project Knot.xcodeproj -scheme Knot -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet`

---

### Step 3.4: Build Dislikes Selection Screen (iOS) ✅
**Date:** February 7, 2026  
**Status:** Complete

**What was done:**
- Replaced the `OnboardingDislikesView` placeholder with a full dislikes selection screen matching the Interests screen (Step 3.3) visual style
- **3-column dark card grid:** Reuses `OnboardingInterestsView.cardGradient(for:)` and `.iconName(for:)` static methods for consistent gradient and icon visuals across both screens — no code duplication
- **Disabled "liked" interests:** Cards for interests already selected as likes in Step 3.3 are grayed out (flat `Color(white: 0.18)` instead of gradient), 50% opacity, `.disabled(true)` (not tappable), and show a heart badge in the top-right corner to indicate "already liked"
- **Personalized header:** "What doesn't [partner name] like?" using the name from Step 3.2, with subtitle "Choose 5 things your partner avoids. We'll make sure to steer clear of these."
- **Search bar:** Identical pill-style search to the Interests screen — real-time filtering of 40 categories, clear button, empty-state message
- **Exactly-5 validation:** Counter shows "X selected (Y more needed)" in pink; checkmark icon when complete. "Next" button disabled until exactly 5 dislikes are chosen
- **Shake animation:** 6th selection attempt triggers the same horizontal shake as the Interests screen
- **ViewModel validation:** Added `.dislikes` case to `OnboardingViewModel.validateCurrentStep()` — requires `selectedDislikes.count == 5` AND `selectedDislikes.isDisjoint(with: selectedInterests)` (no overlap with likes)
- **4 preview variants:** Empty (no likes), with liked interests grayed out, 3 dislikes selected, 5 dislikes selected (complete)

**`DislikeImageCard` visual states:**
- **Unselected:** Gradient background, semi-transparent SF Symbol icon, white text (identical to `InterestImageCard`)
- **Selected (disliked):** Pink border, checkmark badge in top-right corner
- **Disabled (liked):** Flat gray background, 50% opacity, dimmed text (35% white), heart badge in top-right, not tappable
- **Shaking:** Horizontal shake animation when 6th selection rejected

**Files modified:**
- `iOS/Knot/Features/Onboarding/Steps/OnboardingDislikesView.swift` — Full rewrite from placeholder to complete dislikes screen (62 lines → ~310 lines). Contains `OnboardingDislikesView` (main view) and `DislikeImageCard` (private struct with disabled state support).
- `iOS/Knot/Features/Onboarding/OnboardingViewModel.swift` — Added `.dislikes` validation case with count check and `isDisjoint(with:)` overlap guard. Updated comment noting Steps 3.5–3.8 remain.

**Test results:**
- ✅ `xcodebuild build` — zero errors, zero warnings (BUILD SUCCEEDED)
- ✅ Swift 6 strict concurrency: no warnings or errors
- ✅ Interests selected as likes in Step 3.3 appear grayed out with heart badge
- ✅ Attempt to tap a liked interest — cannot be selected (`.disabled(true)`)
- ✅ Select 5 different interests as dislikes — "Next" enables, counter shows checkmark
- ✅ Select only 4 — "Next" is disabled, counter shows "(1 more needed)"
- ✅ Attempt to select a 6th dislike — shake animation triggers on the card
- ✅ Tap a selected dislike to deselect — deselects correctly, counter decrements
- ✅ Search bar filters interests in real-time
- ✅ Clear search restores full list
- ✅ Empty search shows "No interests match" message
- ✅ Navigate forward then back — selections persist (ViewModel state preserved)
- ✅ Build verified on iPhone 17 Pro Simulator (iOS 26.2)

**Notes:**
- `DislikeImageCard` is a separate `private struct` from `InterestImageCard` (in InterestsView) because it adds an `isDisabled` state with different visual treatment (grayscale, heart badge, `.disabled()` modifier). Extracting a shared base card was considered but the disabled-state-specific logic makes the two cards diverge enough that separate implementations are cleaner.
- The gradient and icon mapping functions (`cardGradient(for:)` and `iconName(for:)`) are reused from `OnboardingInterestsView` via their `static` access level. They are NOT `private`, so DislikesView can call them directly. If these are ever made private, the dislikes view will fail to compile.
- The `isDisjoint(with:)` check in the ViewModel validation is a safety net — the UI already prevents selecting liked interests via `.disabled(true)`. The ViewModel check guards against programmatic state corruption.
- The `FlowLayout` component (created in Step 3.3) is still not used by this screen. It remains available for VibesView (Step 3.6) which may use a chip layout.
- Run iOS build with: `cd iOS && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build -project Knot.xcodeproj -scheme Knot -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet`

---

### Step 3.5: Build Milestones Input Screen (iOS) ✅
**Date:** February 7, 2026  
**Status:** Complete

**What was done:**
- Replaced the `OnboardingMilestonesView` placeholder with a full milestones input screen containing 4 sections: birthday (required), anniversary (optional), holiday quick-add, and custom milestones
- **Birthday section (required):** Month/day pickers using `Picker(.menu)` with pink tint, human-readable date display below (e.g., "July 22"), "Required" capsule badge. Day picker auto-clamps when month changes (e.g., switching from March 31 to February clamps to Feb 29)
- **Anniversary section (optional):** Toggle to enable/disable. When toggled on, month/day pickers animate in with `.opacity.combined(with: .move(edge: .top))` transition. Wrapped in a `Theme.surface.opacity(0.5)` card with border for visual grouping
- **Holiday Quick-Add:** 5 predefined US major holidays as toggleable list chips — Valentine's Day (Feb 14), Mother's Day (May 11), Father's Day (Jun 15), Christmas (Dec 25), New Year's Eve (Dec 31). Each chip shows SF Symbol icon, holiday name, date, and a `Lucide.circleCheck`/`Lucide.circle` toggle indicator. Selected state uses `Theme.accent.opacity(0.12)` background with pink border. Counter shows "X selected" in pink
- **Custom Milestones:** List of user-created milestones with star icon, name, date, recurrence label, and X delete button. "Add Custom Milestone" button with dashed border opens a `.sheet` with `NavigationStack`, name `TextField`, month/day pickers, yearly/one-time segmented recurrence picker, Cancel/Save toolbar buttons. Save button disabled when name is empty
- Created `CustomMilestone` struct (Identifiable, Sendable) with name, month, day, recurrence properties
- Created `HolidayOption` struct with static `allHolidays` array containing the 5 predefined US holidays (id, displayName, month, day, iconName)
- Created private `HolidayChip` view component for the toggleable holiday list items
- Added `daysInMonth()` and `clampDay()` static helper methods to `OnboardingViewModel` for date validation across month boundaries
- Added `customMilestones: [CustomMilestone]` array to `OnboardingViewModel`
- Added `.milestones` validation case: birthday always valid (has defaults); custom milestones must have non-empty names
- Added 3 preview variants: empty state, with partner name, with pre-filled data (birthday, anniversary, holidays, custom milestones)

**Files created:**
- None (all changes in existing files)

**Files modified:**
- `iOS/Knot/Features/Onboarding/OnboardingViewModel.swift` — Added `CustomMilestone` struct, `HolidayOption` struct with `allHolidays`, `customMilestones` array, `daysInMonth()` and `clampDay()` static helpers, `.milestones` validation case
- `iOS/Knot/Features/Onboarding/Steps/OnboardingMilestonesView.swift` — Full rewrite from placeholder to complete milestones screen (~450 lines). Contains `OnboardingMilestonesView` (main view with 4 sections + add custom sheet) and `HolidayChip` (private struct)

**Test results:**
- ✅ `xcodegen generate` completed successfully
- ✅ `xcodebuild build` — zero errors, zero warnings (BUILD SUCCEEDED)
- ✅ Swift 6 strict concurrency: no warnings or errors
- ✅ Enter a birthday and tap "Next" — navigation proceeds to Vibes step
- ✅ Skip anniversary (toggle off) — allowed, "Next" is enabled
- ✅ Toggle anniversary on — month/day pickers animate in
- ✅ Toggle "Valentine's Day" on — chip highlights with pink border and checkmark
- ✅ Toggle "Valentine's Day" off — chip returns to neutral state
- ✅ Add a custom milestone named "First Date" — appears in the milestones list with date and recurrence
- ✅ Delete a custom milestone via X button — removed with animation
- ✅ Add custom sheet: Save disabled when name is empty; enabled when name is entered
- ✅ Month change clamps day correctly (e.g., March 31 → February becomes Feb 29)
- ✅ Navigate forward then back — all selections persist (ViewModel state preserved)
- ✅ Build verified on iPhone 17 Pro Simulator (iOS 26.2)

**Notes:**
- The `HolidayOption` struct uses fixed month/day values for all holidays. Mother's Day and Father's Day use approximate dates (May 11, Jun 15) rather than computing the floating "2nd Sunday of May" / "3rd Sunday of June" dynamically. This is a simplification for MVP — the exact date for the current year will be computed dynamically when notifications are scheduled (Step 7.2).
- The `CustomMilestone` struct lives in `OnboardingViewModel.swift` alongside `HolidayOption` rather than in a separate file, because both are tightly coupled to the onboarding flow and small enough to colocate. If these grow or are needed outside onboarding (e.g., vault editing in Step 3.12), extract to `/Models/`.
- The `daysInMonth()` helper returns 29 for February (not 28) to support leap year birthdays. Since milestones store month+day only (year is computed dynamically), allowing day 29 for February ensures Feb 29 birthdays are storable. The year-specific validation (e.g., "2025 is not a leap year") happens when computing the next occurrence for notifications.
- The `.milestones` validation in the ViewModel always allows proceeding because birthday has defaults (Jan 1). The only constraint is that custom milestones, if any exist, must have non-empty names — this is enforced by the sheet's Save button being disabled when the name field is empty, and the ViewModel validation acts as a safety net.
- The `HolidayChip` is a `private struct` within `OnboardingMilestonesView.swift`. It's not in `/Components/` because it's specific to the milestones onboarding step and unlikely to be reused elsewhere.
- The custom milestone sheet uses `.presentationDetents([.medium])` for a half-height modal. This provides enough room for the name field, date pickers, and recurrence toggle without taking over the full screen.
- The reusable `monthPicker()` and `dayPicker()` helper functions are defined within `OnboardingMilestonesView` and used in both the main view (birthday, anniversary) and the custom milestone sheet. They accept `Binding<Int>` and use `Picker(.menu)` with pink tint.
- Run iOS build with: `cd iOS && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build -project Knot.xcodeproj -scheme Knot -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet`

---

### Step 2.5: Create Backend Auth Middleware ✅
**Date:** February 7, 2026  
**Status:** Complete

**What was done:**
- Created the `get_current_user_id` FastAPI dependency in `app/core/security.py` that extracts and validates Bearer tokens against Supabase Auth
- The middleware uses `HTTPBearer(auto_error=False)` to extract the Bearer token from the `Authorization` header, then validates it by calling Supabase's `/auth/v1/user` endpoint with the token and the anon API key
- Returns the authenticated user's UUID string on success; raises `HTTPException(401)` with `WWW-Authenticate: Bearer` header for all failure cases (missing token, invalid/expired token, network error, malformed response)
- Created a protected test endpoint `GET /api/v1/me` in `app/main.py` that uses `Depends(get_current_user_id)` and returns `{"user_id": "<uuid>"}` — serves as both a test route and a future-use "who am I" endpoint
- Uses a private `_get_apikey()` helper with lazy import to avoid circular dependency with the config module
- Created comprehensive test suite with 14 tests across 5 test classes covering all auth scenarios

**Files modified:**
- `backend/app/core/security.py` — **Updated:** Replaced placeholder with full auth middleware implementation. Exports `get_current_user_id` dependency for use in route handlers via `Depends()`
- `backend/app/main.py` — **Updated:** Added `GET /api/v1/me` protected endpoint importing `get_current_user_id` from security module

**Files created:**
- `backend/tests/test_auth_middleware.py` — 14 tests across 5 test classes (TestValidToken, TestInvalidToken, TestNoToken, TestMalformedHeaders, TestHealthEndpointUnprotected)

**Middleware architecture:**
1. `HTTPBearer(auto_error=False)` extracts Bearer token (returns `None` if missing instead of FastAPI's default 403)
2. If `credentials is None` → 401 with "Missing authentication token" message
3. Sends `GET {SUPABASE_URL}/auth/v1/user` with `Authorization: Bearer {token}` and `apikey: {anon_key}` headers
4. If `httpx.RequestError` (network failure) → 401 with "Authentication service unavailable"
5. If non-200 response from Supabase → 401 with "Invalid or expired authentication token"
6. If response JSON missing `id` field → 401 with "no user ID found"
7. Returns `user_data["id"]` (UUID string) on success

**Test results:**
- ✅ `pytest tests/test_auth_middleware.py -v` — 14 passed, 0 failed, 7.41s
- ✅ Valid Supabase JWT → HTTP 200 with correct user_id
- ✅ Returned user_id matches the authenticated user's ID from auth.users
- ✅ Response is valid JSON with `{"user_id": "<uuid>"}` structure
- ✅ Garbage token → HTTP 401 with descriptive error detail
- ✅ Structurally valid but fabricated JWT → HTTP 401 (validates with Supabase, not just format)
- ✅ Empty Bearer token → HTTP 401
- ✅ No Authorization header → HTTP 401 with descriptive message mentioning "token"
- ✅ 401 response includes `WWW-Authenticate: Bearer` header (RFC 7235 compliance)
- ✅ Basic auth (instead of Bearer) → HTTP 401
- ✅ Raw token without "Bearer " prefix → HTTP 401
- ✅ `/health` endpoint returns 200 without auth (unprotected)
- ✅ `/health` endpoint returns 200 with auth (ignores token gracefully)
- ✅ All existing tests still pass (280+ from Steps 0.5–3.5)

**Notes:**
- The middleware validates tokens by calling Supabase's GoTrue API (`/auth/v1/user`) rather than decoding JWTs locally. This ensures tokens are validated against the live session state (e.g., revoked sessions are properly rejected). The tradeoff is a network round-trip per request, but this is acceptable for MVP.
- The `apikey` header is required by Supabase's API gateway (Kong) for all requests, including authenticated ones. The anon key is safe to use here — actual access control is enforced by the Bearer token (JWT) and RLS policies.
- The `_get_apikey()` helper uses a lazy import (`from app.core.config import SUPABASE_ANON_KEY`) to avoid circular dependency issues when `security.py` is imported at module level.
- Tests create real Supabase auth users via the Admin API (`/auth/v1/admin/users`), sign them in to get valid JWTs, and clean up after each test. This requires `SUPABASE_SERVICE_ROLE_KEY` in `.env`.
- The test fixture `test_auth_user_with_token` includes a `time.sleep(0.5)` after user creation to allow the `handle_new_user` trigger to fire and create the `public.users` row before signing in.
- Usage in future route handlers: `from app.core.security import get_current_user_id` then `async def my_route(user_id: str = Depends(get_current_user_id))`.
- Run tests with: `cd backend && source venv/bin/activate && pytest tests/test_auth_middleware.py -v`

---

### Step 3.6: Build Aesthetic Vibes Screen (iOS) ✅
**Date:** February 7, 2026  
**Status:** Complete

**What was done:**
- Replaced the `OnboardingVibesView` placeholder with a full aesthetic vibes selection screen using a 2-column grid of 8 visual cards
- Each card displays a unique themed gradient background, a Lucide icon (large semi-transparent watermark + small icon above the name), the vibe display name (converted from `snake_case`), and a short description
- **Vibe-to-icon mapping:** quiet_luxury → `Lucide.gem`, street_urban → `Lucide.building2`, outdoorsy → `Lucide.trees`, vintage → `Lucide.watch`, minimalist → `Lucide.penLine`, bohemian → `Lucide.sun`, romantic → `Lucide.heart`, adventurous → `Lucide.compass`
- **Vibe-to-gradient mapping:** Each vibe has a hand-tuned 2-color gradient (e.g., warm gold for Quiet Luxury, forest green for Outdoorsy, cool steel for Minimalist, rose for Romantic)
- **No maximum limit:** Users can select any number of vibes (1 through all 8). The implementation plan originally specified max 4, but this was changed per user feedback
- **Selection feedback:** Pink border + checkmark badge in top-right corner on selected cards, subtle 1.02x scale-up effect
- **Selection counter** at bottom showing "X selected" with checkmark when at least 1 chosen, or "(pick at least 1)" when empty
- **Personalized header** using partner name from Step 3.2 (e.g., "What's Alex's aesthetic?")
- Added `.vibes` validation case to `OnboardingViewModel.validateCurrentStep()` — checks `selectedVibes.count >= 1`
- **Validation error banner (new pattern):** Added `validationMessage` computed property to `OnboardingViewModel` returning user-facing error strings for all steps (basicInfo, interests, dislikes, milestones, vibes). Updated `OnboardingContainerView` so the Next button is always tappable — when `canProceed` is false, tapping shows a red error banner that slides up with the validation message and auto-dismisses after 3 seconds. The button tint dims to 40% opacity when invalid. Error banner auto-clears on step change.
- Added 3 preview variants: empty state, 2 selected with partner name, 4 selected with partner name

**Files modified:**
- `iOS/Knot/Features/Onboarding/Steps/OnboardingVibesView.swift` — Full rewrite from placeholder to complete vibes screen (~360 lines). Contains `OnboardingVibesView` (main view with header, 2-column grid, counter, toggle logic, and static helper functions for display names, descriptions, icons, gradients) and `VibeCard` (private struct)
- `iOS/Knot/Features/Onboarding/OnboardingViewModel.swift` — Added `.vibes` validation case, added `validationMessage` computed property with per-step error strings
- `iOS/Knot/Features/Onboarding/OnboardingContainerView.swift` — Added `showValidationError` / `validationErrorText` state, red error banner view, always-tappable Next button with validation-on-tap logic, auto-dismiss after 3 seconds, dimmed tint when invalid

**Test results:**
- ✅ `xcodegen generate` completed successfully
- ✅ `xcodebuild build` — zero errors, zero warnings (BUILD SUCCEEDED)
- ✅ Swift 6 strict concurrency: no warnings or errors
- ✅ Tap a vibe — highlights as selected (pink border + checkmark + scale)
- ✅ Tap again — deselects (returns to gradient-only state)
- ✅ Select all 8 vibes — all highlight, no rejection
- ✅ Proceed with 1 vibe — allowed (`canProceed = true`)
- ✅ Tap Next with 0 vibes — red error banner appears: "Pick at least 1 vibe to continue."
- ✅ Error banner auto-dismisses after 3 seconds
- ✅ Navigate forward then back — all selections persist (ViewModel state preserved)
- ✅ Validation error messages work for all steps (tested basicInfo, interests, dislikes, vibes)
- ✅ Build verified on iPhone 17 Pro Simulator (iOS 26.2)

**Notes:**
- The implementation plan originally specified a maximum of 4 vibes, but this limit was removed per user feedback. The `Constants.Validation.maxVibes` constant still exists but is no longer enforced in the vibes step. If a max is needed later, re-add the check in `toggleVibe()` and the validation case.
- Unlike the Interests/Dislikes screens (3-column grid of 40 items), the Vibes screen uses a 2-column grid because there are only 8 options. Larger cards provide more visual impact and room for the description text.
- Vibe gradients are hand-tuned per vibe (not auto-generated via hue rotation like interests). This gives each vibe a distinct color identity that matches its aesthetic (e.g., warm gold for luxury, forest green for outdoorsy, rose for romantic).
- The `VibeCard` is a `private struct` within `OnboardingVibesView.swift`. Unlike `InterestImageCard`, it includes a description label and uses Lucide icons (UIImage) instead of SF Symbols. The card has two icon placements: a large semi-transparent watermark offset to the upper-right, and a small opaque icon at bottom-left above the name.
- Static helper functions (`displayName(for:)`, `vibeDescription(for:)`, `vibeIcon(for:)`, `vibeGradient(for:)`) are `static` on `OnboardingVibesView` and could be reused by future screens (e.g., the completion summary in Step 3.9, or the vibe override in Step 6.5).
- The validation error banner pattern is generic and works for all steps. When adding new steps with validation (Steps 3.7–3.8), add a case to `validationMessage` in the ViewModel — the container automatically picks it up.
- The Next button is no longer `.disabled()` — it's always tappable with a dimmed tint (`Theme.accent.opacity(0.4)`) when invalid. This replaces the previous pattern where the button was grayed out with no feedback. The tradeoff is that users can always tap Next, but they get immediate, specific feedback about what's missing.
- Run iOS build with: `cd iOS && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build -project Knot.xcodeproj -scheme Knot -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet`

---

### Step 3.7: Build Budget Tiers Screen (iOS) ✅
**Date:** February 7, 2026  
**Status:** Complete

**What was done:**
- Replaced the `OnboardingBudgetView` placeholder with a full budget tiers screen containing three tier cards with multi-select preset range buttons
- **Three budget tier cards** stacked vertically in a `ScrollView`, each with a unique accent color:
  - **Just Because** (teal accent, `Lucide.coffee`) — "Spontaneous dates & small surprises"
  - **Minor Occasion** (warm amber accent, `Lucide.gift`) — "Smaller holidays & celebrations"
  - **Major Milestone** (pink/Theme.accent, `Lucide.sparkles`) — "Birthdays, anniversaries & big holidays"
- **Multi-select range buttons:** Each tier displays 4 preset dollar ranges in a 2-column `LazyVGrid`. Users can select **multiple** ranges per tier — the effective min/max is computed as `min(selected mins)` / `max(selected maxes)`. At least one range must remain selected (last one can't be deselected)
- **"Select all" button** in each card's title row: shows "Select all" in accent color when not all selected; changes to "All selected" in muted text when all are active
- **Personalized header** using the partner's name from Step 3.2 (e.g., "Budget for Alex")
- **Preset ranges and defaults:**
  - Just Because: $5–$20, **$20–$50** (default), $50–$100, $100–$200
  - Minor Occasion: $25–$50, **$50–$150** (default), $150–$300, $300–$500
  - Major Milestone: $50–$100, **$100–$500** (default), $500–$750, $750–$1,000
- Added `BudgetRangeOption` (`fileprivate` struct, `Identifiable`, `Equatable`, `Sendable`) with computed `label` property using a file-level `formatDollars()` function (avoids `@MainActor` isolation issues)
- Added `BudgetTierCard` (`private` struct) with icon badge, title/subtitle, "Select all" button, and 2-column button grid
- Added `.budget` validation case to `OnboardingViewModel.validateCurrentStep()` — checks `max >= min` for all three tiers (always passes since preset ranges guarantee validity)
- Added `.budget` case to `validationMessage` — "Maximum budget must be at least the minimum for each tier."
- Added `justBecauseRanges`, `minorOccasionRanges`, `majorMilestoneRanges` (`Set<String>`) to `OnboardingViewModel` to persist multi-select state across step navigation
- `toggle()` helper uses `inout Set<String>` for toggling; `syncBudget()` recomputes effective min/max from selected ranges via closures
- Dollar amounts stored in cents (matching database convention); `formatDollars()` converts to "$XX" or "$X,XXX" display format using `NumberFormatter`
- Card uses `.clipShape(RoundedRectangle(cornerRadius: 16))` to prevent button overflow
- 3 preview variants: default, with name, multiple selected

**Files modified:**
- `iOS/Knot/Features/Onboarding/Steps/OnboardingBudgetView.swift` — Full rewrite from placeholder to complete budget screen (~310 lines). Contains `OnboardingBudgetView` (main view with header, 3 tier cards, toggle/sync helpers, preset options), `BudgetRangeOption` (fileprivate struct), `BudgetTierCard` (private struct), and `formatDollars()` (file-level function)
- `iOS/Knot/Features/Onboarding/OnboardingViewModel.swift` — Added `justBecauseRanges`, `minorOccasionRanges`, `majorMilestoneRanges` Set properties; added `.budget` validation case and validation message

**Test results:**
- ✅ `xcodebuild build` — zero errors, zero warnings (BUILD SUCCEEDED)
- ✅ Swift 6 strict concurrency: no warnings or errors
- ✅ Tap a range button — highlights with accent fill and white text
- ✅ Tap a different range — both are now highlighted (multi-select)
- ✅ Tap "Select all" — all 4 buttons highlight, text changes to "All selected"
- ✅ Tap a selected range to deselect — deselects correctly
- ✅ Attempt to deselect the last remaining range — prevented (stays selected)
- ✅ Default selections ($20–$50, $50–$150, $100–$500) pre-selected on load
- ✅ Navigate forward (Next) and back — all selections persist (ViewModel state preserved)
- ✅ Proceed to Love Languages step — navigation works
- ✅ Build verified on iPhone 17 Pro Simulator (iOS 26.2)

**Notes:**
- The original implementation plan specified sliders, but preset range buttons were chosen for cleaner UX — users tap to select comfort zones rather than fiddling with dual sliders
- `BudgetRangeOption` is `fileprivate` (not `private`) because `OnboardingBudgetView`'s static option arrays reference the type. The static arrays are also `fileprivate` to match. `BudgetTierCard` is `private` since it doesn't need to be referenced outside the file
- The `formatDollars()` function is at file level (not on the View) to avoid `@MainActor` isolation issues — `BudgetRangeOption.label` is a computed property on a non-isolated `Sendable` struct, so it can't call a `@MainActor`-isolated method
- `@Environment` viewModel doesn't support mutation through `WritableKeyPath` subscript. The toggle/selectAll logic uses direct property access (`viewModel.justBecauseRanges.insert(...)`) and closure-based setters (`setMin: { viewModel.justBecauseMin = $0 }`) instead
- The `FlowLayout` component (created in Step 3.3) was initially used for range buttons but replaced with `LazyVGrid` (2-column) for consistent equal-width layout. `FlowLayout` caused uneven wrapping with varying-width dollar labels
- `.clipShape(RoundedRectangle(cornerRadius: 16))` is applied to the card background to prevent button content from overflowing outside the rounded container
- Run iOS build with: `cd iOS && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build -project Knot.xcodeproj -scheme Knot -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet`

---

### Interest Card Images (Enhancement)
**Date:** February 7, 2026
**Status:** Complete

**What was done:**
- Added asset catalog support for custom images on interest cards (both Interests and Dislikes screens)
- Created `Assets.xcassets/Interests/` folder group with `provides-namespace: true` (40 image sets, one per interest category)
- Naming convention: `interest-{lowercased-hyphenated}` (e.g., `interest-travel`, `interest-board-games`)
- Added `imageName(for:)` static method to `OnboardingInterestsView` — converts interest name to asset path (`"Interests/interest-travel"`), returns `nil` if no image is in the catalog (checked via `UIImage(named:)`)
- Updated `InterestImageCard` to accept optional `imageName` — when present, renders a full-bleed photo (`.resizable().aspectRatio(contentMode: .fill)`); when absent, falls back to the existing gradient + SF Symbol icon
- Updated `DislikeImageCard` identically — disabled (already-liked) cards still use flat gray background regardless of image availability
- User added 40 JPEG images (~280x400px) to the asset catalog via Xcode

**Files modified:**
- `iOS/Knot/Features/Onboarding/Steps/OnboardingInterestsView.swift` — Added `imageName(for:)` static method; updated `InterestImageCard` struct with optional `imageName` parameter and conditional image/gradient rendering
- `iOS/Knot/Features/Onboarding/Steps/OnboardingDislikesView.swift` — Updated `DislikeImageCard` struct with optional `imageName` parameter and conditional image/gradient rendering; passes `OnboardingInterestsView.imageName(for:)` to each card
- `iOS/Knot/Resources/Assets.xcassets/Interests/` — 40 new `.imageset` folders with `Contents.json` and user-provided JPEG images

**Test results:**
- ✅ Build succeeds with zero errors and zero warnings
- ✅ Interest cards display custom images with dark gradient overlay for text readability
- ✅ Dislike cards display custom images; disabled (liked) cards show flat gray
- ✅ Cards without images gracefully fall back to gradient + SF Symbol

---

### Step 3.8: Build Love Languages Screen (iOS) ✅
**Date:** February 7, 2026  
**Status:** Complete

**What was done:**
- Replaced the `OnboardingLoveLanguagesView` placeholder with a full two-step love language selection screen
- **5 full-width cards** — one per love language, each with a unique gradient background, Lucide icon, display name, and contextual description:
  - **Words of Affirmation** (warm peach/coral, `Lucide.messageCircle`) — "They feel loved through compliments, encouragement, and heartfelt messages."
  - **Acts of Service** (earthy teal/green, `Lucide.heartHandshake`) — "Actions speak louder — they appreciate helpful, thoughtful gestures."
  - **Receiving Gifts** (rich purple/magenta, `Lucide.gift`) — "Meaningful, well-chosen gifts make them feel truly seen and valued."
  - **Quality Time** (warm amber/gold, `Lucide.clock`) — "Undivided attention and shared experiences matter most to them."
  - **Physical Touch** (deep rose/blush, `Lucide.hand`) — "Closeness, comfort, and physical connection bring them joy."
- **Two-step selection flow:**
  1. First tap on any card sets it as **Primary** (prominent pink border, "PRIMARY" capsule badge in top-right corner, 1.02x scale)
  2. Second tap on a *different* card sets it as **Secondary** (muted pink border, "SECONDARY" capsule badge in top-right corner)
  3. Both set → tapping a third card replaces Secondary
  4. Tapping current Primary → clears both selections (full reset)
  5. Tapping current Secondary → clears Secondary only
  6. Same card cannot be both Primary and Secondary
- **Badge overlay architecture:** "PRIMARY" / "SECONDARY" capsule badges are positioned in a separate `ZStack` layer (top-right corner), completely independent of the text content. This prevents long names like "Words of Affirmation" from wrapping when a badge appears
- **Dynamic header subtitle** guides the user through selection states: "Choose their primary love language first." → "Great! Now choose their secondary love language." → "Perfect — you can change either by tapping."
- **Selection status bar** at the bottom shows contextual state: "Pick primary love language" → "Primary set — pick secondary" (with `1.circle.fill` icon) → "Both selected" (with `checkmark.circle.fill` icon)
- **Personalized header** using the partner's name from Step 3.2 (e.g., "How does Alex feel loved?")
- Added `.loveLanguages` validation case to `OnboardingViewModel.validateCurrentStep()` — requires both `primaryLoveLanguage` and `secondaryLoveLanguage` to be non-empty
- Added `.loveLanguages` case to `validationMessage` — "Choose your partner's primary love language." or "Now choose a secondary love language." depending on state
- 3 preview variants: empty, primary only, both selected

**Files modified:**
- `iOS/Knot/Features/Onboarding/Steps/OnboardingLoveLanguagesView.swift` — Full rewrite from placeholder to complete love languages screen (~420 lines). Contains `OnboardingLoveLanguagesView` (main view with header, card list, selection logic, display/description/icon/gradient static mappings), `LoveLanguageSelectionState` (private enum: unselected/primary/secondary), and `LoveLanguageCard` (private struct with ZStack overlay layout)
- `iOS/Knot/Features/Onboarding/OnboardingViewModel.swift` — Added `.loveLanguages` validation case (`!primaryLoveLanguage.isEmpty && !secondaryLoveLanguage.isEmpty`) and validation message

**Test results:**
- ✅ Select a primary love language — highlighted with pink border + "PRIMARY" badge in top-right corner + 1.02x scale
- ✅ Tap the same card again (primary) — clears both selections (full reset), "Next" disables
- ✅ Select a different card as secondary — "SECONDARY" badge appears, both cards highlighted, "Next" enables
- ✅ Tap "Next" with nothing selected — error banner appears with "Choose your partner's primary love language."
- ✅ Tap "Next" with only primary selected — error banner appears with "Now choose a secondary love language."
- ✅ Navigate back and forward — both love language selections persist
- ✅ Header subtitle updates dynamically through all 3 states
- ✅ Selection status bar updates with icon + text through all 3 states
- ✅ Long names ("Words of Affirmation") display cleanly without wrapping — badge is in independent overlay layer
- ✅ Build verified on iPhone 17 Pro Simulator (iOS 26.2)

**Notes:**
- The badge was initially placed inline (HStack) with the display name, but this caused text wrapping for longer names like "Words of Affirmation". Moved to a `ZStack(alignment: .topTrailing)` overlay approach — the badge floats in the top-right corner of the card, completely independent of the text layout. Future card designs should use this overlay pattern when adding badges that shouldn't affect content flow
- `LoveLanguageSelectionState` is a private `Equatable` enum (not `Sendable` needed since it's only used in view code). The `.animation()` modifier on `LoveLanguageCard` uses this as its `value:` parameter for smooth state transitions
- Love language gradients are hand-tuned (like vibes) rather than auto-generated, since there are only 5 options and each gradient should semantically match the love language's meaning
- The `selectLanguage()` method handles all 5 selection flow branches in a single function with clear priority: primary tap → secondary tap → no primary → no secondary → replace secondary

---

### Step 3.9: Build Onboarding Completion Screen (iOS) ✅
**Date:** February 8, 2026  
**Status:** Complete

**What was done:**
- Replaced the `OnboardingCompletionView` placeholder with a full scrollable partner profile summary screen
- **Success header** — Party popper Lucide icon with personalized message (e.g., "Alex's vault is ready.")
- **6 summary sections** using a reusable `SummaryCard` generic component (private struct with Lucide icon + title header + `@ViewBuilder` content):
  1. **Partner Info** — Name, relationship tenure (formatted as "2y 2m"), cohabitation status, location
  2. **Interests & Dislikes** — Likes shown as accent-colored `CompactTag` capsule pills, dislikes as muted pills, both using `FlowLayout` wrapping. Sub-headers with Lucide `heart`/`ban` icons and count labels
  3. **Milestones** — Birthday, anniversary, holidays, custom milestones with SF Symbol icons and formatted dates (e.g., "Mar 15"). One-time milestones show "once" capsule badge. Includes computed "Next up" indicator showing days until nearest milestone
  4. **Aesthetic Vibes** — Displayed as accent-colored capsule pills with Lucide icons, using `OnboardingVibesView.displayName(for:)` and `.vibeIcon(for:)` for consistency
  5. **Budget Tiers** — Just Because / Minor Occasion / Major Milestone rows with Lucide icons and formatted dollar ranges (e.g., "$20 – $50")
  6. **Love Languages** — Primary and secondary with Lucide icons and "PRIMARY"/"SECONDARY" capsule badges, using `OnboardingLoveLanguagesView.displayName(for:)` and `.languageIcon(for:)`
- **Navigation button fix** — All 3 buttons (Back, Next, Get Started) updated with `.fixedSize(horizontal: true, vertical: false)` to prevent text wrapping, reduced from `.body` to `.subheadline` font, height from 50 to 44, and tighter horizontal padding
- **3 preview variants** — Empty, Full Profile (Alex with all data), Minimal Profile (Jordan with sparse data)

**Files modified:**
- `iOS/Knot/Features/Onboarding/Steps/OnboardingCompletionView.swift` — Full rewrite from placeholder to comprehensive summary (~630 lines). Contains `OnboardingCompletionView` (main view with 6 sections, formatting helpers, milestone computation), `SummaryCard` (private generic struct), `CompactTag` (private struct with `.accent`/`.muted` styles), and file-level `formatDollars()` function
- `iOS/Knot/Features/Onboarding/OnboardingContainerView.swift` — All 3 navigation buttons updated: added `.fixedSize()`, reduced font/height/padding to prevent text wrapping on smaller screens

**New private components (inside OnboardingCompletionView.swift):**
- `SummaryCard<Content: View>` — Reusable card container with Lucide icon + title header + generic content slot
- `CompactTag` — Small capsule pill with `.accent` (pink-tinted) and `.muted` (gray) styles for interests/dislikes
- `formatDollars()` — File-level cents-to-dollar formatter (same pattern as BudgetView, avoids `@MainActor` isolation)

**Test results:**
- ✅ All entered data displays correctly on completion screen (partner name, interests, dislikes, vibes, milestones, budget, love languages)
- ✅ "Get Started" navigates to Home screen
- ✅ Upcoming milestone indicator shows correct "Next up: Birthday in X days"
- ✅ Vibes display with correct icons and display names
- ✅ Love languages show Primary/Secondary badges
- ✅ Budget tiers show formatted dollar ranges
- ✅ Navigation buttons no longer wrap text on any screen width
- ✅ Build verified on iPhone 17 Pro Simulator (iOS 26.2) with zero errors

**Notes:**
- `FlowLayout` uses `horizontalSpacing` and `verticalSpacing` named parameters (not a single `spacing` parameter). Always use `FlowLayout(horizontalSpacing: 6, verticalSpacing: 6)`, not `FlowLayout(spacing: 6)`
- The completion view references static methods from other step views (`OnboardingVibesView.displayName(for:)`, `OnboardingVibesView.vibeIcon(for:)`, `OnboardingLoveLanguagesView.displayName(for:)`, `OnboardingLoveLanguagesView.languageIcon(for:)`). These must remain `static` (not `private static`) for cross-view access
- `nextUpcomingMilestone()` computes the nearest future milestone from all entered milestones (birthday, anniversary, holidays, custom). It checks the current year first, then rolls to next year if the date has passed. Returns `nil` if no milestones exist
- `SummaryCard` and `CompactTag` are `private` to the file — they are tightly coupled to the completion screen and not intended for reuse in `/Components/`. If future screens need similar card layouts, extract to `/Components/` at that point
- Navigation buttons were reduced from `.body` to `.subheadline` font and from height 50 to 44 to prevent text wrapping. `.fixedSize(horizontal: true, vertical: false)` is the key modifier — it tells SwiftUI to use the text's ideal width rather than compressing it

---

### Step 3.10: Create Vault Submission API Endpoint (Backend) ✅
**Date:** February 8, 2026  
**Status:** Complete

**What was done:**
- Created Pydantic models for the complete Partner Vault submission payload (`VaultCreateRequest`, `VaultCreateResponse`) with comprehensive validation
- Implemented `POST /api/v1/vault` endpoint that accepts the full onboarding payload and inserts into 6 database tables
- Registered the vault router in `main.py` via `app.include_router(vault_router)`
- Created 40 tests across 10 test classes covering happy paths, validation errors, auth, and data integrity

**Pydantic validation rules (enforced before database insertion):**
- `partner_name`: required, non-empty (whitespace-trimmed)
- `interests`: exactly 5, from predefined 40-category list, no duplicates
- `dislikes`: exactly 5, from predefined list, no duplicates, no overlap with interests (cross-field model validator)
- `milestones`: at least 1 required, must include a birthday; custom milestones require explicit `budget_tier`
- `vibes`: 1–8, from predefined 8-tag list, no duplicates
- `budgets`: exactly 3 (one per occasion type: just_because, minor_occasion, major_milestone), `max_amount >= min_amount >= 0`
- `love_languages`: primary and secondary must be different, both from the predefined 5-language list

**Database insertion order (6 tables):**
1. `partner_vaults` — basic info (name, tenure, cohabitation, location)
2. `partner_interests` — 10 rows (5 likes + 5 dislikes) in a single bulk insert
3. `partner_milestones` — birthday + optional anniversary, holidays, custom events; `budget_tier` set to `None` for birthday/anniversary/holiday (DB trigger handles defaults), explicit for custom and holiday overrides
4. `partner_vibes` — 1–8 vibe tag rows
5. `partner_budgets` — 3 rows (one per occasion type), amounts in cents
6. `partner_love_languages` — 2 rows (priority 1 = primary, priority 2 = secondary)

**Error handling:**
- 201 — Success with vault_id and summary counts
- 401 — Missing or invalid auth token (from `get_current_user_id` dependency)
- 409 — User already has a vault (UNIQUE constraint on `user_id` in `partner_vaults`)
- 422 — Pydantic validation error (auto-generated by FastAPI)
- 500 — Unexpected database error with `_cleanup_vault()` to remove partial data

**Cleanup strategy:** If any child table insert fails after the vault is created, `_cleanup_vault()` deletes the vault row. CASCADE on `partner_vaults` automatically removes all child rows. This simulates a transaction using PostgREST's non-transactional API.

**Files created:**
- `backend/app/models/vault.py` — Pydantic models: `VaultCreateRequest` (with `MilestoneCreate`, `BudgetCreate`, `LoveLanguagesCreate` sub-models), `VaultCreateResponse`, and `VALID_*` constant sets mirroring DB CHECK constraints
- `backend/tests/test_vault_api.py` — 40 tests across 10 classes (TestValidPayload, TestDataIntegrity, TestInterestValidation, TestVibeValidation, TestBudgetValidation, TestLoveLanguageValidation, TestMilestoneValidation, TestMissingRequiredFields, TestAuthRequired, TestDuplicateVault)

**Files modified:**
- `backend/app/api/vault.py` — Full implementation replacing placeholder: `create_vault()` endpoint with Pydantic validation, sequential DB inserts, error handling, and `_cleanup_vault()` helper
- `backend/app/main.py` — Added `from app.api.vault import router as vault_router` and `app.include_router(vault_router)`

**Test results:**
- ✅ Valid full payload → 201 with vault_id UUID and correct summary counts
- ✅ Valid minimal payload (only required fields, no optional location/tenure/cohabitation) → 201
- ✅ Data integrity: all 6 tables populated correctly (partner_vaults, partner_interests, partner_milestones, partner_vibes, partner_budgets, partner_love_languages)
- ✅ Milestone budget tier auto-defaults: birthday → major_milestone, anniversary → major_milestone, Valentine's Day (explicit override) → major_milestone, custom → user-provided minor_occasion
- ✅ 4 interests → 422; 6 interests → 422; invalid category "Golf" → 422; duplicate interests → 422
- ✅ 4 dislikes → 422; interest/dislike overlap → 422
- ✅ 0 vibes → 422; invalid vibe "fancy" → 422; 9 vibes → 422; duplicate vibes → 422
- ✅ 2 budgets → 422; max < min → 422; negative min → 422; duplicate occasion types → 422
- ✅ Same love language primary/secondary → 422; invalid language → 422; missing secondary → 422
- ✅ No milestones → 422; no birthday → 422; custom without budget_tier → 422; empty milestone name → 422
- ✅ Missing required fields (partner_name, interests, love_languages, vibes, budgets) → 422; empty partner_name → 422
- ✅ No auth token → 401; invalid token → 401
- ✅ Second vault for same user → 409 with "already exists" message
- ✅ 40 passed, 0 failed, 2 warnings (harmless supabase-py deprecation notices)

**Notes:**
- The endpoint uses `get_service_client()` (service_role key, bypasses RLS) rather than the anon client because we need to insert into multiple tables for the authenticated user. The user's identity is validated by `get_current_user_id` (auth middleware), so RLS bypass is safe here
- Milestone `budget_tier` is sent as `None` in the JSON payload for birthday/anniversary/holiday types. PostgREST converts this to SQL `NULL`, and the `handle_milestone_budget_tier()` BEFORE INSERT trigger sets the default. The trigger does NOT fire differently for NULL vs omitted — both are treated as "not provided"
- The `_cleanup_vault()` helper is best-effort. If it fails (e.g., network issue), the original error is still raised. Orphaned partial vaults would need manual cleanup, but this edge case is extremely unlikely in practice
- Pydantic's `Literal` types provide compile-time-like validation for enum values. This mirrors the database CHECK constraints but catches errors earlier (at the API layer) with better error messages
- The `@model_validator(mode="after")` on `VaultCreateRequest.validate_no_interest_overlap` runs after all field validators, so it can safely access both `self.interests` and `self.dislikes`
- Total backend test count is now **345 tests** across 16 test files (305 from Phase 1-2 + 40 from Step 3.10)

---

### Step 3.11: Connect iOS Onboarding to Backend API ✅
**Date:** February 7, 2026  
**Status:** Complete

**What was done:**
- Created `DTOs.swift` with Codable structs matching the backend Pydantic models (`VaultCreatePayload`, `MilestonePayload`, `BudgetPayload`, `LoveLanguagesPayload`, `VaultCreateResponse`) with snake_case `CodingKeys` for JSON serialization
- Created `VaultService.swift` with two methods: `createVault(_:)` (POST to backend with Bearer token) and `vaultExists()` (PostgREST query for vault existence check)
- Added `buildVaultPayload()` to `OnboardingViewModel` that serializes all 9 steps of onboarding data (partner info, interests, dislikes, milestones, vibes, budgets, love languages) into the API-compatible `VaultCreatePayload`
- Added `submitVault()` async method to `OnboardingViewModel` with full error handling and loading state
- Updated `OnboardingContainerView` "Get Started" button to call `submitVault()`, with a loading overlay during submission and an error alert with "Try Again" retry option
- Updated `AuthViewModel.listenForAuthChanges()` to check vault existence on `initialSession` (app relaunch) and `signedIn` (returning user) events, so returning users skip onboarding
- Updated `Constants.swift` with `#if DEBUG` conditional for backend URL (`http://127.0.0.1:8000` for dev, `https://api.knot-app.com` for prod)
- Added `NSAllowsLocalNetworking` to `Info.plist` for localhost HTTP connections during development
- Created `test_step_3_11_ios_integration.py` — 9 tests simulating the exact iOS-to-backend flow

**Files created:**
- `iOS/Knot/Models/DTOs.swift` — Codable request/response structs for `POST /api/v1/vault`
- `iOS/Knot/Services/VaultService.swift` — HTTP client for vault API + PostgREST vault existence check
- `backend/tests/test_step_3_11_ios_integration.py` — 9 iOS integration tests (payload acceptance, all 6 tables verified, vault existence check, error handling, returning user flow)

**Files modified:**
- `iOS/Knot/Core/Constants.swift` — `#if DEBUG` backend URL (localhost for dev, production URL for release)
- `iOS/Knot/Info.plist` — Added `NSAppTransportSecurity` → `NSAllowsLocalNetworking` for HTTP localhost
- `iOS/Knot/Features/Onboarding/OnboardingViewModel.swift` — Added `isSubmitting`, `submissionError`, `showSubmissionError` state; `submitVault()` async method; `buildVaultPayload()` serializer; `formatMilestoneDate()` helper
- `iOS/Knot/Features/Onboarding/OnboardingContainerView.swift` — "Get Started" button now calls `submitVault()` then `onComplete()` on success; loading overlay with spinner during submission; error alert with "Try Again"/"Cancel" buttons; button disabled during submission
- `iOS/Knot/Features/Auth/AuthViewModel.swift` — `initialSession`: vault existence check before `isCheckingSession = false`; `signedIn`: vault existence check for returning users; `signedOut`: resets `hasCompletedOnboarding = false`

**Payload serialization details:**
- Birthday milestone: `"birthday"` type, name = `"{partnerName}'s Birthday"`, date = `"2000-MM-DD"` (year 2000 placeholder), `budget_tier: null` (DB trigger sets `major_milestone`)
- Anniversary milestone: optional, same trigger default
- Holiday milestones: mapped from `HolidayOption.allHolidays` by ID, `budget_tier: null` (trigger sets based on type)
- Custom milestones: `budget_tier: "minor_occasion"` (iOS default — the UI does not collect a budget tier for custom milestones)
- Budgets: 3 tiers, amounts in cents from ViewModel (e.g., `justBecauseMin = 2000` → `$20.00`)
- Empty location fields serialized as `null` (not empty string)
- All strings trimmed of whitespace before submission

**Error handling:**
- `VaultServiceError` enum with 6 cases: `.noAuthSession`, `.networkError`, `.serverError`, `.decodingError`, `.vaultAlreadyExists`, `.validationError`
- Network errors differentiated by `URLError.code`: no internet, timeout, cannot connect to host
- Backend responses parsed for two FastAPI error formats: string `detail` (409, 500) and array `detail` (422 Pydantic validation)
- Loading overlay prevents interaction during submission
- Error alert offers "Try Again" (re-calls `submitVault()`) and "Cancel" (dismisses, user can re-enter data)

**Test results:**
- ✅ iOS project builds with zero errors on iPhone 17 Pro Simulator (iOS 26.2)
- ✅ 40 existing vault API tests still pass (no regressions)
- ✅ `test_ios_payload_accepted` — Exact iOS DTO payload → 201 with correct summary
- ✅ `test_ios_data_stored_in_all_6_tables` — All 6 tables populated (vaults, interests, milestones with trigger defaults, vibes, budgets in cents, love languages with priorities)
- ✅ `test_vault_exists_after_creation` — PostgREST existence check returns vault (simulates `VaultService.vaultExists()`)
- ✅ `test_vault_not_exists_before_creation` — New user gets empty result (shows onboarding)
- ✅ `test_duplicate_vault_returns_409` — Double-tap "Get Started" → 409 "already exists"
- ✅ `test_no_auth_returns_401` — Missing token → 401
- ✅ `test_invalid_token_returns_401` — Bad token → 401
- ✅ `test_error_response_has_detail_field` — Error body has `detail` for iOS parsing
- ✅ `test_vault_persists_after_new_session` — Sign out → sign in → vault still exists (returning user skips onboarding)
- ✅ Total: 49 tests passed (40 existing + 9 new), 0 failed, 2 warnings (harmless supabase-py deprecation)
- ✅ Total backend test count is now **354 tests** across 17 test files (345 from Phase 1-2 + Step 3.10, + 9 from Step 3.11)

**Notes:**
- Custom milestones default to `budget_tier: "minor_occasion"` because the onboarding UI (Step 3.5) does not include a budget tier picker for custom milestones. The implementation plan says "User selects tier during creation" — this should be addressed in Step 3.12 (Edit Vault) or as a future enhancement to the custom milestone sheet
- The vault existence check uses Supabase PostgREST directly (not the FastAPI backend) because `GET /api/v1/vault` doesn't exist yet (planned for Step 3.12). RLS ensures only the current user's vault is returned
- `VaultService` is `@MainActor` because it's called from `OnboardingViewModel` (also `@MainActor`). It uses `URLSession.shared` which is safe to call from the main actor
- The `#if DEBUG` conditional in Constants.swift means release builds automatically use the production URL. No manual URL swapping needed before deployment
- `NSAllowsLocalNetworking` in Info.plist only permits HTTP for local network (localhost, 127.0.0.1). It does NOT disable ATS globally — external domains still require HTTPS

---

### Step 3.12: Implement Vault Edit Functionality (iOS + Backend) ✅
**Date:** February 8, 2026  
**Status:** Complete

**What was done:**

**Backend — GET /api/v1/vault (Retrieve Vault):**
- Created `GET /api/v1/vault` endpoint that loads the authenticated user's full vault data from all 6 tables (partner_vaults, partner_interests, partner_milestones, partner_vibes, partner_budgets, partner_love_languages)
- Returns 200 with full vault data, 401 without auth, 404 if no vault exists
- Separates interests into `interests` (likes) and `dislikes` arrays based on `interest_type` column
- Milestones include their database `id` for future reference
- Budgets include their database `id` for future reference
- Love languages returned as array with `language` + `priority` (1=primary, 2=secondary)

**Backend — PUT /api/v1/vault (Update Vault):**
- Created `PUT /api/v1/vault` endpoint that accepts the same `VaultCreateRequest` payload as POST
- Uses "replace all" strategy: updates the vault row, then deletes and re-inserts all child rows
- Preserves the `vault_id` (updates in place, not recreated)
- Same Pydantic validation as POST (exactly 5 interests, 5 dislikes, no overlap, valid categories, etc.)
- Returns 200 with updated summary, 401 without auth, 404 if no vault exists, 422 for validation errors

**Backend — Pydantic Models:**
- Added `MilestoneResponse`, `BudgetResponse`, `LoveLanguageResponse` sub-models for GET response
- Added `VaultGetResponse` — full vault data with all related tables
- Added `VaultUpdateResponse` — summary counts after update (mirrors `VaultCreateResponse`)

**iOS — VaultService Additions:**
- Added `getVault()` — `GET /api/v1/vault` with full error handling (200, 401, 404)
- Added `updateVault(_:)` — `PUT /api/v1/vault` with full error handling (200, 401, 404, 422)
- Both methods follow the same pattern as `createVault()`: Bearer token auth, typed `VaultServiceError`, network error differentiation

**iOS — DTOs:**
- Added `VaultGetResponse`, `MilestoneGetResponse`, `BudgetGetResponse`, `LoveLanguageGetResponse` — for deserializing GET response with snake_case `CodingKeys`
- Added `VaultUpdateResponse` — for deserializing PUT response

**iOS — EditVaultView (New):**
- Created `Features/Settings/EditVaultView.swift` — full-screen Edit Profile screen
- Loads existing vault data via `getVault()` into a fresh `OnboardingViewModel`
- Populates all ViewModel properties from GET response (basic info, interests, dislikes, milestones, vibes, budgets, love languages)
- Shows sectioned list with icon, title, and subtitle for each vault section
- Tapping a section opens the corresponding onboarding step view in a sheet (reuses existing views via `.environment(vm)`)
- "Save" toolbar button builds payload via `buildVaultPayload()` and calls `updateVault()`
- Handles loading, error, saving, and success states
- Uses `EditSection` enum (Identifiable) for sheet presentation
- Parses milestone dates ("2000-MM-DD") back into month/day integers
- Holiday milestones matched back to `HolidayOption.allHolidays` by month/day

**iOS — HomeView Update:**
- Added "Edit Partner Profile" button with Lucide `userPen` icon
- Added toolbar button (top-left) for quick access
- Presents `EditVaultView` as `.fullScreenCover`
- Temporary placement until Settings screen in Step 11.1

**Files created:**
- `iOS/Knot/Features/Settings/EditVaultView.swift` — Edit Profile screen with section navigation and vault CRUD
- `backend/tests/test_vault_edit_api.py` — 32 tests for GET and PUT vault endpoints

**Files modified:**
- `backend/app/api/vault.py` — Added `get_vault()` and `update_vault()` endpoints
- `backend/app/models/vault.py` — Added GET response models (`MilestoneResponse`, `BudgetResponse`, `LoveLanguageResponse`, `VaultGetResponse`) and `VaultUpdateResponse`
- `iOS/Knot/Models/DTOs.swift` — Added `VaultGetResponse`, `MilestoneGetResponse`, `BudgetGetResponse`, `LoveLanguageGetResponse`, `VaultUpdateResponse`
- `iOS/Knot/Services/VaultService.swift` — Added `getVault()` and `updateVault(_:)` methods
- `iOS/Knot/Features/Home/HomeView.swift` — Added Edit Profile button + toolbar icon + fullScreenCover

**Test results:**
- ✅ 32 new tests, all passing, 2 warnings (harmless supabase-py deprecation)
- ✅ **GET tests (13):** 200 response, partner_name, basic_info, vault_id match, interests (5), dislikes (5), milestones (2 with all fields), vibes, budgets (3 tiers with amounts), love_languages (primary/secondary), 404 no vault, 401 no auth, 401 invalid token
- ✅ **PUT tests (19):** 200 response, name persists, basic info persists, interests replaced, dislikes replaced, milestones replaced (count change OK), vibes replaced, budgets replaced (amounts verified), love languages replaced, vault_id preserved, response summary, 404 no vault, 401 no auth, 401 invalid token, 422 interests count, 422 interest/dislike overlap, 422 empty name, multiple sequential updates, single field change
- ✅ iOS project builds with zero errors on iPhone 17 Pro Simulator (iOS 26.2)
- ✅ Total backend test count is now **386 tests** across 18 test files (354 from Step 3.11 + 32 from Step 3.12)

**Notes:**
- PUT uses "replace all" strategy (delete + re-insert child rows) rather than granular diffs. This is simpler and avoids tracking which specific interests/milestones changed. Acceptable for MVP — the overhead is minimal since child tables have at most ~15 rows each
- The `VaultCreateRequest` Pydantic model is reused for PUT (same validation rules). No separate `VaultUpdateRequest` model was created since the same constraints apply
- The `vault_id` is preserved across updates (the vault row is updated, not deleted and recreated). All child rows get new UUIDs on each update, which is fine — they are not referenced externally
- `GET /api/v1/vault` now exists, so the vault existence check in `AuthViewModel` could be refactored to use it instead of direct PostgREST. However, the current approach (PostgREST `select id limit 1`) is lighter weight and doesn't require parsing the full response — leaving as-is for now
- The Edit Profile screen reuses all existing onboarding step views by injecting a pre-populated `OnboardingViewModel` into the environment. No step views were modified
- Budget range IDs in the edit view are set to the exact min-max from the database (e.g., `"3000-8000"`), which may not match the preset range IDs from onboarding (e.g., `"2000-5000"`). The budget view's preset buttons won't appear "selected" for custom ranges — this is acceptable for MVP and can be refined later
- The `EditSection` enum conforms to `Identifiable` (via `rawValue: String`) to support SwiftUI's `.sheet(item:)` modifier

---

### Step 4.1: Build Home Screen Layout (iOS) ✅
**Date:** February 8, 2026  
**Status:** Complete

**What was done:**
- Created `NetworkMonitor.swift` — `@Observable` class using `NWPathMonitor` to track network connectivity and publish `isConnected` on the main actor for safe SwiftUI binding
- Created `HomeViewModel.swift` — `@Observable` class that loads vault data from `GET /api/v1/vault` via `VaultService`, computes milestone countdowns with year rollover logic, and provides computed properties for the UI (partner name, upcoming milestones, vibes, recent hints)
- Completely rebuilt `HomeView.swift` from the Step 2.3 placeholder into the full Home screen with 5 distinct sections:
  1. **Offline banner** — Red banner with Lucide `wifiOff` icon when `networkMonitor.isConnected` is `false`, animated show/hide
  2. **Header section** — Time-of-day greeting ("Good morning/afternoon/evening/night"), partner name (32pt bold, scales down for long names), next milestone countdown badge (circular, 28pt rounded number), milestone countdown subtitle with SF Symbol icon, and horizontally scrollable vibe capsule tags
  3. **Hint Capture section** — `TextEditor` with placeholder text overlay, character counter ("0/500", turns red at 450+), Lucide `mic` button (Step 4.3 placeholder), Lucide `arrowUp` submit button (accent when active, surface when disabled), border highlights on focus
  4. **Upcoming Milestones section** — Next 1-2 milestones sorted by days until occurrence, each as a card with SF Symbol type icon, name, formatted date, and countdown capsule pill. Color-coded by urgency: red (≤3 days), orange (≤7), yellow (≤14), pink/accent (distant). Loading spinner and dashed-border empty state included
  5. **Recent Hints section** — Last 3 hints preview with source icon (pen/mic), text (2-line truncation), relative timestamp. "View All" button (Step 4.5 placeholder). Dashed-border empty state with descriptive guidance text
- All interactive sections disabled + dimmed to 50% opacity when offline
- Toolbar: Knot branding (heart + "Knot") on leading, edit profile (`userPen`) + sign out (`logOut`) icons on trailing
- Edit Profile still accessible via `.fullScreenCover`, vault data auto-refreshes on dismiss via `.onChange(of: showEditProfile)`
- Keyboard dismisses interactively on scroll via `.scrollDismissesKeyboard(.interactively)`
- Hint submit provides haptic feedback (`UIImpactFeedbackGenerator`) and clears input (full API call in Step 4.2)
- Regenerated Xcode project via `xcodegen generate` to include new files

**Supporting types created:**
- `UpcomingMilestone` (Identifiable, Sendable) — milestone with countdown info, `formattedDate` ("Feb 14"), `countdownText` ("in 14 days" / "Tomorrow" / "Today!"), `iconName` (SF Symbol per type), `urgencyLevel` (critical/soon/upcoming/distant)
- `HintPreview` (Identifiable, Sendable) — hint preview model for Recent Hints section (populated when Hints API is available in Step 4.5)

**Files created:**
- `iOS/Knot/Core/NetworkMonitor.swift` — Network connectivity observer using `NWPathMonitor`
- `iOS/Knot/Features/Home/HomeViewModel.swift` — Home screen data management, vault loading, milestone countdowns

**Files modified:**
- `iOS/Knot/Features/Home/HomeView.swift` — Complete rebuild from placeholder to full Home screen
- `iOS/Knot.xcodeproj/` — Regenerated via `xcodegen generate` with 2 new source files

**Test results (visual verification on simulator):**
- ✅ All 5 sections render correctly on iPhone 17 Pro Simulator (iOS 26.2)
- ✅ Header shows partner name ("Jas"), greeting ("Good morning"), vibe tags ("Bohemian")
- ✅ Milestone countdown shows "Jas's Birthday in 327 days" with red circular badge (327)
- ✅ Upcoming Milestones card shows "Jas's Birthday" with "Jan 1" date and "in 327 days" countdown pill
- ✅ Hint capture input renders with placeholder, mic button, submit button, and "0/500" counter
- ✅ Recent Hints shows empty state with descriptive text
- ✅ Toolbar shows Knot branding + edit profile + sign out icons
- ✅ Edit Profile accessible from toolbar, vault refreshes on dismiss
- ✅ Build succeeds with zero errors
- ✅ Total backend test count remains **386 tests** (no new backend tests — Step 4.1 is iOS-only, data needs served by existing `GET /api/v1/vault` from Step 3.12)

**Notes:**
- The backend server must be running (`uvicorn app.main:app --host 127.0.0.1 --port 8000`) for the Home screen to load vault data. If the server was started before Step 3.10 code was written, it must be restarted to pick up the vault routes
- `CHHapticPattern` errors in simulator logs ("hapticpatternlibrary.plist couldn't be opened") are standard iOS simulator noise — haptics work on physical devices, not simulators. These do not indicate bugs in our code
- `nw_connection` and socket errors from Supabase SDK are transient networking noise — the SDK retries automatically and the app handles failures gracefully
- The hint submit button currently only provides haptic feedback and clears the input. The actual API call (`POST /api/v1/hints`) will be connected in Step 4.2
- The microphone button is a visual placeholder — voice capture will be implemented in Step 4.3 using `SFSpeechRecognizer`
- Recent Hints is always empty until Step 4.5 (Hint List View) populates `viewModel.recentHints`
- Milestone countdown correctly handles year rollover: if a birthday has already passed this year, it computes days until next year's occurrence
- `NetworkMonitor` uses `NWPathMonitor` on a dedicated dispatch queue and dispatches updates to `@MainActor` for thread-safe SwiftUI binding. It starts immediately on init and cancels on deinit
- The `vibeDisplayName()` helper converts snake_case to Title Case inline (e.g., "quiet_luxury" → "Quiet Luxury"). It does NOT use the static `OnboardingVibesView.displayName(for:)` method because that would create a dependency on the Onboarding module from the Home feature. If more vibe display logic is needed across features, extract to a shared utility

---

### Step 4.2: Implement Text Hint Capture (iOS + Backend) ✅
**Date:** February 8, 2026  
**Status:** Complete

**What was done:**
- Created `backend/app/models/hints.py` — Pydantic schemas for hint API: `HintCreateRequest` (with 500-char validation via `@field_validator`), `HintCreateResponse`, `HintListResponse`, `HintResponse`
- Rewrote `backend/app/api/hints.py` — Two authenticated endpoints:
  - `POST /api/v1/hints` — Validates hint text (non-empty, ≤500 chars), looks up the user's vault_id from `partner_vaults`, inserts into the `hints` table. Returns 201 on success, 404 if no vault, 422 if validation fails. `hint_embedding` is stored as NULL (deferred to Step 4.4 for Vertex AI embedding generation)
  - `GET /api/v1/hints` — Lists hints in reverse chronological order with `limit`/`offset` pagination. Selects only display columns (excludes `hint_embedding` for performance). Returns total count via `count="exact"` for pagination
- Registered the hints router in `backend/app/main.py`
- Added hint DTOs to `iOS/Knot/Models/DTOs.swift`: `HintCreatePayload`, `HintCreateResponse`, `HintItemResponse`, `HintListResponse` — all with snake_case `CodingKeys` matching backend Pydantic schemas
- Created `iOS/Knot/Services/HintService.swift` — `@MainActor` service following the same patterns as `VaultService`: Bearer token auth via `SupabaseManager.client.auth.session`, typed error enum (`HintServiceError` with 6 cases), URL error mapping, two FastAPI error format parsers (string detail + array detail)
- Updated `HomeViewModel.swift`:
  - Added `submitHint(text:source:)` — Calls `HintService.createHint()`, sets `showHintSuccess` flag for checkmark animation, refreshes recent hints via `loadRecentHints()`, auto-dismisses success after 1.5 seconds
  - Added `loadRecentHints()` — Fetches last 3 hints from `GET /api/v1/hints?limit=3`
  - Added state properties: `isSubmittingHint`, `showHintSuccess`, `hintErrorMessage`
  - Added `parseISO8601(_:)` static helper for Supabase timestamp parsing (with/without fractional seconds)
- Updated `HomeView.swift` — Wired up the hint capture section:
  - Submit button calls `viewModel.submitHint()` via the real `HintService` API
  - **Success animation:** Green checkmark + "Hint saved!" text with `.scale.combined(with: .opacity)` transition overlays the input field, auto-dismisses after 1.5s
  - **Loading state:** `ProgressView` spinner replaces arrow icon in submit button while `isSubmittingHint`
  - **Haptic feedback:** Light impact on tap, notification success/error on completion via `UINotificationFeedbackGenerator`
  - **Error display:** Red error message shown below input (left-aligned), character counter remains (right-aligned)
  - Input clears immediately on submit for responsiveness (API call is async in background)
  - `.task` now also calls `loadRecentHints()` on appear
  - `.onChange(of: showEditProfile)` also refreshes hints on dismiss
- Regenerated Xcode project via `xcodegen generate` to include `HintService.swift`

**Files created:**
- `backend/app/models/hints.py` — Pydantic schemas for hint API (request/response models)
- `iOS/Knot/Services/HintService.swift` — Hint capture and listing service

**Files modified:**
- `backend/app/api/hints.py` — Rewritten from placeholder to full POST + GET endpoints
- `backend/app/main.py` — Added `hints_router` registration
- `iOS/Knot/Models/DTOs.swift` — Added 4 hint DTOs (HintCreatePayload, HintCreateResponse, HintItemResponse, HintListResponse)
- `iOS/Knot/Features/Home/HomeViewModel.swift` — Added submitHint(), loadRecentHints(), parseISO8601(), 3 new state properties
- `iOS/Knot/Features/Home/HomeView.swift` — Wired up API call, success animation, loading state, error display, haptics
- `iOS/Knot.xcodeproj/` — Regenerated via `xcodegen generate` with HintService.swift

**Test results:**
- ✅ Type a hint and submit — hint appears in "Recent Hints" section below
- ✅ Submit an empty string — submit button is disabled (cannot tap)
- ✅ Type 501 characters — counter turns red and submit button is disabled
- ✅ Type exactly 500 characters — submit works successfully
- ✅ Success animation: green checkmark + "Hint saved!" appears, auto-dismisses after 1.5s
- ✅ Recent Hints section updates immediately after submission
- ✅ Backend `POST /api/v1/hints` returns 201 with created hint data
- ✅ Backend `GET /api/v1/hints` returns hints in reverse chronological order
- ✅ Build succeeds with zero errors after `xcodegen generate`

**Notes:**
- The backend server MUST be restarted after adding the hints router. The old server process doesn't know about `POST /api/v1/hints` and returns a generic 404, which the iOS app misinterprets as "No partner vault found." Always restart: `kill $(lsof -i :8000 -t) && cd backend && source venv/bin/activate && uvicorn app.main:app --host 127.0.0.1 --port 8000`
- Consider using `uvicorn app.main:app --reload` during development to auto-restart on file changes
- `hint_embedding` is stored as NULL for now — Step 4.4 will add Vertex AI `text-embedding-004` embedding generation
- `HintService` follows the same `@MainActor` pattern as `VaultService` (see architectural note #62)
- The `HintServiceError` enum mirrors `VaultServiceError` structure. If more services are added, consider extracting a shared `APIServiceError` base
- `ISO8601DateFormatter` with `.withFractionalSeconds` handles Supabase's microsecond-precision timestamps. The fallback without fractional seconds handles simpler formats

---

### Step 4.4: Create Hint Submission API Endpoint with Embedding (Backend) ✅
**Date:** February 9, 2026  
**Status:** Complete

**What was done:**
- Created `backend/app/services/embedding.py` — Embedding service wrapping Vertex AI `text-embedding-004` model. Lazy-initializes the model on first use, generates 768-dimension embeddings asynchronously via `asyncio.to_thread()` to avoid blocking the FastAPI event loop, and degrades gracefully (returns `None`) when Vertex AI is not configured or the API call fails
- Updated `backend/app/api/hints.py` — `POST /api/v1/hints` now calls `generate_embedding()` after Pydantic validation and vault lookup. If embedding succeeds, formats it via `format_embedding_for_pgvector()` (converts `list[float]` to pgvector string `"[0.1,0.2,...,0.768]"`) and stores in the `hint_embedding` column. If it fails or Vertex AI is unconfigured, the hint is still saved with `hint_embedding = NULL`
- Updated `backend/app/core/config.py` — Added `validate_vertex_ai_config()` (returns `bool`, non-fatal) and `is_vertex_ai_configured()` (checks `GOOGLE_CLOUD_PROJECT` presence) for credential checking by tests and services
- Created `backend/tests/test_hint_submission_api.py` — 35 tests across 9 test classes:
  - `TestValidHintSubmission` (8 tests): 201 response, hint data, source types, default source, 500-char boundary, DB storage, multiple hints
  - `TestEmbeddingGeneration` (4 tests, requires Vertex AI): non-NULL embedding, 768 dimensions, different texts → different embeddings, voice transcription gets embedding
  - `TestGracefulDegradation` (2 tests): hint saved with NULL embedding when Vertex AI mocked as unavailable, 201 response unchanged
  - `TestValidationErrors` (6 tests): empty text, whitespace-only, 501 chars with "Hint too long", 1000 chars, missing field, invalid source
  - `TestAuthRequired` (3 tests): no token, invalid token, malformed header → 401
  - `TestNoVault` (1 test): user without vault → 404
  - `TestEmbeddingWithMock` (4 tests): mocked embedding stored in DB, 768 dimensions verified, called with exact hint text, stripped text
  - `TestEmbeddingUtilities` (5 tests): pgvector format, 768-dim format, empty list, constants, reset state
  - `TestHintListAfterEmbedding` (2 tests): GET excludes embedding, correct count regardless of embedding status

**Files created:**
- `backend/app/services/embedding.py` — Vertex AI text-embedding-004 embedding service
- `backend/tests/test_hint_submission_api.py` — 35 tests for Step 4.4

**Files modified:**
- `backend/app/api/hints.py` — Integrated embedding generation into POST endpoint
- `backend/app/core/config.py` — Added Vertex AI config validation helpers

**Test results:**
- ✅ `pytest tests/test_hint_submission_api.py -v` — 31 passed, 4 skipped, 2 warnings
- ✅ 4 Vertex AI live tests skipped (GOOGLE_CLOUD_PROJECT not configured) — will pass once GCP credentials are added to `.env`
- ✅ 2 warnings are harmless supabase-py deprecation (third-party code)
- ✅ Full test suite: `pytest tests/ -v` — **417 passed**, 4 skipped, 2 warnings (386 existing + 31 new, 0 regressions)

**Notes:**
- The embedding service uses **lazy initialization** — the Vertex AI model is only loaded once, on first `generate_embedding()` call. Subsequent calls reuse the cached model. `_reset_model()` is exposed for tests only
- **Graceful degradation is the key design pattern:** If `GOOGLE_CLOUD_PROJECT` is empty or Vertex AI fails, `generate_embedding()` returns `None`. The hint API saves the hint with `hint_embedding = NULL`. No error is raised to the client — the 201 response is identical whether or not an embedding was generated. This means the iOS app and existing tests work identically regardless of Vertex AI configuration
- `asyncio.to_thread()` wraps the synchronous Vertex AI SDK call to avoid blocking the FastAPI event loop. This is the recommended pattern for CPU-bound or IO-bound synchronous operations in async FastAPI endpoints
- `format_embedding_for_pgvector()` converts `list[float]` → `"[0.1,0.2,...,0.768]"` string. PostgREST accepts this format for `vector(768)` columns. The Supabase Python client sends it as a string in the JSON payload
- The `requires_vertex_ai` pytest marker gates the 4 live embedding tests. To run them: set `GOOGLE_CLOUD_PROJECT` in `.env` and ensure GCP Application Default Credentials are configured (`gcloud auth application-default login`)
- The mocked tests (`TestEmbeddingWithMock`, `TestGracefulDegradation`) use `unittest.mock.patch` + `AsyncMock` to override `app.api.hints.generate_embedding` at the import location. This lets them verify embedding storage and API contract without real GCP credentials

---

### Step 4.5: Implement Hint List View (iOS) ✅
**Date:** February 9, 2026
**Status:** Complete

**What was done:**
- Created `iOS/Knot/Features/Home/HintsListViewModel.swift` — ViewModel managing hints list state and deletion. Loads all hints via `HintService.listHints(limit: 100)`, maps backend DTOs to local `HintItem` model (with parsed ISO 8601 dates), and includes placeholder `deleteHint(id:)` for Step 4.6 (currently removes from local state only)
- Created `iOS/Knot/Features/Home/HintsListView.swift` — Full-screen hints list UI with swipe-to-delete. Displays hints in reverse chronological order using a `List` view, shows hint text, source icon (keyboard/microphone), date, time, and "Used" badge for hints in recommendations. Swipe-to-delete with haptic feedback, pull-to-refresh, empty state with "Back to Home" button, and X button navigation
- Updated `iOS/Knot/Features/Home/HomeView.swift` — Added `showHintsList` state variable, connected "View All" button to open hints list sheet, and added `.onChange` handler to refresh recent hints when returning from the list
- **Fixed swipe-to-delete implementation:** Initial ScrollView + LazyVStack approach did not support SwiftUI's `.swipeActions()`. Converted to `List` with `.listStyle(.plain)`, `.listRowBackground(.clear)`, `.listRowSeparator(.hidden)`, and custom insets for consistent spacing

**Files created:**
- `iOS/Knot/Features/Home/HintsListViewModel.swift` — State management for hints list (loading, deletion placeholder, error handling)
- `iOS/Knot/Features/Home/HintsListView.swift` — Full hints list UI with swipe-to-delete

**Files modified:**
- `iOS/Knot/Features/Home/HomeView.swift` — Added sheet presentation and "View All" button wiring

**Test results:**
- ✅ Navigate to hints list via "View All" button — sheet opens with title "All Hints"
- ✅ All hints display in reverse chronological order (newest first)
- ✅ Each hint shows: text (3-line limit), source icon, date, time, and "Used" badge if applicable
- ✅ Swipe right-to-left on any hint → red "Delete" button appears
- ✅ Tap delete or full swipe → hint removed with haptic feedback (local state only, Step 4.6 will add backend DELETE)
- ✅ Pull-to-refresh reloads hints from backend
- ✅ Add new hint from Home → tap "View All" → new hint appears at top of list
- ✅ Empty state displays when all hints deleted with icon, message, and "Back to Home" button
- ✅ X button (top-left) dismisses sheet and returns to Home
- ✅ Recent hints on Home screen refresh automatically when returning from hints list

**Notes:**
- **SwiftUI List vs ScrollView for swipe actions:** `.swipeActions()` requires a `List` view to function properly. The initial implementation used `ScrollView` + `LazyVStack`, which caused swipe gestures to fail. Converted to `List` with transparent background (`.listRowBackground(Color.clear)`) and hidden separators for custom card styling
- **Swipe direction:** iOS swipe actions appear on the trailing edge, requiring **right-to-left swipe** (not left-to-right). This is standard iOS behavior
- **Deletion is local-only for now:** The `deleteHint()` method in `HintsListViewModel` currently only removes hints from the local `hints` array. Step 4.6 will add the `DELETE /api/v1/hints/{id}` API endpoint and connect it to `HintService.deleteHint(id:)`
- **HintItem model:** Created as a local struct in `HintsListViewModel.swift` (not in `/Models/DTOs.swift`) since it's specific to the list view display. Contains parsed `Date` instead of raw ISO 8601 string for easy relative formatting
- **ISO 8601 parsing:** The ViewModel handles both fractional seconds (`2026-02-09T10:35:42.123456Z`) and non-fractional formats (`2026-02-09T10:35:42Z`) via `ISO8601DateFormatter` with `.withFractionalSeconds` fallback
- **Backend server must be running:** The app requires the FastAPI backend at `http://127.0.0.1:8000` to load hints. If connection fails, an error alert displays with the message from `HintService.networkError`

---

### Step 4.6: Create Hint Deletion API Endpoint (Backend + iOS) ✅
**Date:** February 9, 2026
**Status:** Complete

**What was done:**
- Added `DELETE /api/v1/hints/{hint_id}` endpoint to `backend/app/api/hints.py` — validates the hint exists AND belongs to the authenticated user's vault before hard-deleting. Returns 204 on success, 404 if hint not found or belongs to another user. Uses the same vault ownership pattern as POST and GET endpoints
- Added `deleteHint(id:)` method to `iOS/Knot/Services/HintService.swift` — sends `DELETE /api/v1/hints/{id}` with Bearer auth. Handles 204 success, 401 auth errors, 404 not found. Follows the same error handling pattern as `createHint()` and `listHints()`
- Updated `iOS/Knot/Features/Home/HintsListViewModel.swift` — replaced the placeholder `deleteHint(id:)` (which only removed from local state after a simulated delay) with a real API call via `HintService.deleteHint(id:)`. On success removes from local `hints` array; on failure sets `errorMessage` for the alert
- Created `backend/tests/test_hint_deletion_api.py` — 12 tests across 5 test classes

**Files created:**
- `backend/tests/test_hint_deletion_api.py` — Hint deletion API test suite (12 tests)

**Files modified:**
- `backend/app/api/hints.py` — Added DELETE endpoint (Step 4.6)
- `iOS/Knot/Services/HintService.swift` — Added `deleteHint(id:)` method
- `iOS/Knot/Features/Home/HintsListViewModel.swift` — Connected deletion to real API

**Test results:**
- ✅ `pytest tests/test_hint_deletion_api.py -v` — 12 passed, 0 failed, 32.94s
- ✅ Delete a hint → 204 No Content
- ✅ Deleted hint removed from database (verified via direct PostgREST query)
- ✅ Deleted hint excluded from GET /api/v1/hints response
- ✅ Deleting one hint does not affect other hints
- ✅ Attempt to delete another user's hint → 404 (hint persists)
- ✅ Attempt to delete non-existent hint ID → 404
- ✅ Double-delete → 204 on first, 404 on second
- ✅ No auth token → 401
- ✅ Invalid auth token → 401
- ✅ Hint persists after failed authentication delete attempt
- ✅ User without vault → 404 with "vault" in message

**Notes:**
- **Hard-delete, not soft-delete:** The endpoint permanently removes the hint from the database. The implementation plan left the choice open ("soft-deletes or hard-deletes") — hard-delete was chosen because hints have no downstream dependencies that would break (unlike recommendations which reference milestones). If soft-delete is needed later, add an `is_deleted` column and filter in GET queries
- **Ownership validation uses vault_id join:** The endpoint verifies `hint.vault_id == user's vault_id` rather than checking a direct `user_id` on the hints table. This matches the RLS pattern — hints don't have a `user_id` column, only `vault_id`, and vault ownership is checked via `partner_vaults.user_id`
- **404 for unauthorized access (not 403):** Returns 404 (not 403) when a user tries to delete another user's hint. This prevents information leakage — the attacker cannot distinguish "hint exists but isn't yours" from "hint doesn't exist"
- **Test file uses mocked embeddings:** All hint creation in tests patches `generate_embedding` to return `None`, so tests run without GCP credentials

---

### Step 5.1: Define Recommendation State Schema (Backend) ✅
**Date:** February 9, 2026
**Status:** Complete

**What was done:**
- Created `backend/app/agents/state.py` — 8 Pydantic models defining the complete LangGraph recommendation pipeline state
- `BudgetRange` — min/max budget for the active occasion (in cents, with currency)
- `VaultBudget` — budget tier from the partner vault (adds occasion_type label to BudgetRange)
- `VaultData` — full partner profile: basic info, interests/dislikes, vibes, love languages, and all 3 budget tiers
- `RelevantHint` — a hint retrieved via pgvector semantic search (includes similarity_score)
- `MilestoneContext` — the milestone being planned for (type, name, date, budget_tier, days_until)
- `LocationData` — optional location info for experience/date recommendations
- `CandidateRecommendation` — external API result with 4 scoring fields (interest, vibe, love_language, final) that accumulate as the candidate passes through graph nodes
- `RecommendationState` — the main LangGraph state tying all components together: vault_data, occasion_type, milestone_context (optional), budget_range, and 4 list fields (relevant_hints, candidate_recommendations, filtered_recommendations, final_three) that are progressively populated by graph nodes
- Created `backend/tests/test_recommendation_state.py` — 37 tests across 9 test classes

**Files created:**
- `backend/app/agents/state.py` — Recommendation pipeline state schema (8 Pydantic models)
- `backend/tests/test_recommendation_state.py` — State schema test suite (37 tests, 9 classes)

**Test results:**
- ✅ `pytest tests/test_recommendation_state.py -v` — 37 passed, 0 failed, 0.05s
- ✅ BudgetRange: instantiation, currency default, JSON serialization
- ✅ VaultBudget: instantiation, rejects invalid occasion_type
- ✅ VaultData: full profile instantiation, optional field defaults, rejects invalid cohabitation_status, budgets are VaultBudget instances, JSON serialization
- ✅ RelevantHint: full instantiation, defaults, rejects invalid source, JSON serialization
- ✅ MilestoneContext: full instantiation, days_until default, rejects invalid milestone_type/budget_tier/recurrence, JSON serialization
- ✅ LocationData: all fields optional, full instantiation
- ✅ CandidateRecommendation: full instantiation, scoring defaults to zero, optional field defaults, rejects invalid source/type, location is LocationData instance, JSON serialization
- ✅ RecommendationState: full state instantiation, minimal state with defaults, rejects invalid occasion_type, error field, JSON serialization, round-trip JSON serialization, model_dump dict output, final_three diverse types

**Notes:**
- **Literal types over Enum:** Follows the existing project pattern (vault.py, hints.py) of using `Literal["value1", "value2"]` instead of Python `Enum` classes. This keeps the schema compatible with Pydantic's JSON serialization without custom serializers
- **Scoring fields on CandidateRecommendation:** Four `float` fields (`interest_score`, `vibe_score`, `love_language_score`, `final_score`) default to 0.0 and are populated incrementally as the candidate flows through filtering/matching graph nodes. This avoids separate "scored" vs "unscored" model variants
- **VaultData vs VaultGetResponse:** `VaultData` is a flattened, pipeline-optimized view of the vault (love languages as `primary_love_language`/`secondary_love_language` strings, budgets as `list[VaultBudget]`). It is NOT the same as `VaultGetResponse` (which uses nested response models). A conversion function will be needed in Step 5.2+ to transform the GET response into `VaultData`
- **BudgetRange vs VaultBudget:** `BudgetRange` is the min/max for the *current occasion* (no occasion_type label). `VaultBudget` stores all 3 tiers from the vault (with occasion_type). The `RecommendationState.budget_range` is derived from the vault's `VaultBudget` matching the `occasion_type`
- **`RecommendationState.error`:** Optional string field for pipeline error tracking. If any node encounters a non-fatal error (e.g., external API timeout), it sets this field. Downstream nodes can check it and adjust behavior (e.g., skip availability verification if aggregation failed)
- **`Field(default_factory=list)`:** All list fields on `RecommendationState` use `default_factory` to avoid the mutable default argument pitfall. This ensures each state instance gets its own empty list
- **No LangGraph-specific annotations yet:** The state is a plain Pydantic `BaseModel`. LangGraph `Annotated[..., reducer]` annotations for state merging will be added in Step 5.2+ when the graph nodes are implemented and the merge strategy is known
- Run tests with: `cd backend && source venv/bin/activate && pytest tests/test_recommendation_state.py -v`

---

### Step 5.2: Create Hint Retrieval Node (Backend) ✅
**Date:** February 9, 2026
**Status:** Complete

**What was done:**
- Created `backend/app/agents/hint_retrieval.py` — LangGraph node for retrieving semantically relevant hints from pgvector
- **`_build_query_text(state)`** — Constructs a natural-language query from the recommendation state. Uses milestone name and type when available (e.g., "Alex's Birthday birthday gift ideas"), includes an occasion-type label ("casual date or small gift" / "thoughtful gift or fun outing" / "special gift or memorable experience"), and appends the top 3 partner interests for better semantic matching. Works with or without a milestone context (supports "just because" browsing).
- **`retrieve_relevant_hints(state)`** — The main LangGraph node function. Takes `RecommendationState`, builds a query, generates an embedding via Vertex AI `text-embedding-004`, calls `match_hints()` RPC for the top 10 similar hints, and returns `{"relevant_hints": list[RelevantHint]}`. Falls back to chronological ordering when embedding generation is unavailable.
- **`_semantic_search(vault_id, query_embedding)`** — Calls Supabase `match_hints()` RPC via `get_service_client().rpc()`, passing the embedding string, vault_id, threshold, and max_count. Maps response rows to `RelevantHint` Pydantic models with similarity scores.
- **`_chronological_fallback(vault_id)`** — Fallback when Vertex AI is not configured or embedding generation fails. Queries the `hints` table directly via PostgREST, ordered by `created_at DESC`, limited to 10 results. Returns `RelevantHint` objects with `similarity_score=0.0`.
- Created `backend/tests/test_hint_retrieval_node.py` — 29 tests across 5 test classes

**Files created:**
- `backend/app/agents/hint_retrieval.py` — Hint retrieval LangGraph node (3 public functions + 1 private helper)
- `backend/tests/test_hint_retrieval_node.py` — Hint retrieval test suite (29 tests, 5 classes)

**Test results:**
- ✅ `pytest tests/test_hint_retrieval_node.py -v` — 29 passed, 0 failed, 51.72s, 2 warnings (supabase library deprecation)
- ✅ `_build_query_text` with milestone context includes milestone name, type, occasion label, and interests
- ✅ `_build_query_text` without milestone uses occasion label and interests only
- ✅ `_build_query_text` handles all 3 occasion types (just_because, minor_occasion, major_milestone)
- ✅ `_build_query_text` handles empty interests list and fewer than 3 interests
- ✅ `_build_query_text` handles all 4 milestone types (birthday, anniversary, holiday, custom)
- ✅ `_semantic_search` returns hints ordered by cosine similarity (1.0 > 0.707 > 0.110)
- ✅ `_semantic_search` returns properly typed `RelevantHint` objects with all fields
- ✅ `_semantic_search` respects `max_count` parameter (limits to 1 result)
- ✅ `_semantic_search` respects similarity `threshold` (filters out hints below 0.5)
- ✅ `_semantic_search` skips hints with NULL embeddings (only returns embedded hints)
- ✅ `_semantic_search` returns empty list for vault with no hints
- ✅ `_semantic_search` returns empty list for nonexistent vault_id (no error)
- ✅ `_chronological_fallback` returns hints in reverse chronological order (most recent first)
- ✅ `_chronological_fallback` respects `max_count` (default 10, configurable)
- ✅ `_chronological_fallback` returns correct `RelevantHint` fields with `similarity_score=0.0`
- ✅ `_chronological_fallback` returns empty list for empty vault and nonexistent vault
- ✅ `retrieve_relevant_hints` uses semantic path when embedding generation succeeds (mocked)
- ✅ `retrieve_relevant_hints` uses chronological fallback when embedding returns None (mocked)
- ✅ `retrieve_relevant_hints` returns empty list for vault with no hints
- ✅ `retrieve_relevant_hints` result dict compatible with `state.model_copy(update=result)`
- ✅ `retrieve_relevant_hints` passes correct query text to `generate_embedding`
- ✅ `retrieve_relevant_hints` works without milestone context (just_because browsing)
- ✅ `RelevantHint` model round-trip serialization
- ✅ All existing tests still pass (37 from Step 5.1)

**Notes:**
- **Node return type is `dict[str, Any]`**, not a full `RecommendationState`. This follows the LangGraph convention where nodes return partial state updates. The returned dict `{"relevant_hints": [...]}` can be merged into the state via `state.model_copy(update=result)`. When the full graph is composed in Step 5.8, LangGraph will handle the merge automatically.
- **Semantic search uses `get_service_client()` (bypasses RLS):** The node runs server-side in the recommendation pipeline, not in a user-facing request. The vault_id is already validated by the time the pipeline runs. Using the service client avoids needing to set a user JWT on the Supabase client for RPC calls.
- **Graceful degradation pattern:** If Vertex AI is not configured (`GOOGLE_CLOUD_PROJECT` not set) or embedding generation fails for any reason, the node falls back to chronological hint retrieval. This means the recommendation pipeline can still function (with less precision) even without Vertex AI credentials configured.
- **Query text construction strategy:** The query combines milestone name ("Alex's Birthday"), milestone type keywords ("birthday gift ideas"), occasion label ("special gift or memorable experience"), and top 3 interests ("Cooking, Travel, Music"). This produces a rich semantic query that matches hints about gift ideas, activities, and partner preferences. The embedding model captures the semantic meaning, so hints like "she mentioned wanting pottery classes" will match a "birthday gift ideas" query.
- **Integration tests use crafted vectors, not real Vertex AI:** The semantic search tests insert hints with hand-crafted 768-dim vectors (`[1.0, 0, ...]`, `[0.7, 0.7, ...]`, `[0.1, 0.9, ...]`) to verify the `match_hints()` RPC ordering without requiring Vertex AI credentials. The full node tests mock `generate_embedding` to return crafted vectors. This means the test suite runs without GCP credentials.
- **Constants `MAX_HINTS=10` and `DEFAULT_SIMILARITY_THRESHOLD=0.0`:** These are module-level constants in `hint_retrieval.py`. The threshold of 0.0 means all hints are returned by default (no minimum similarity). These can be tuned based on real-world embedding distributions once the pipeline is running with real Vertex AI embeddings.
- Run tests with: `cd backend && source venv/bin/activate && pytest tests/test_hint_retrieval_node.py -v`

---

### Step 5.3: Create External API Aggregation Node (Backend) ✅
**Date:** February 9, 2026
**Status:** Complete

**What was done:**
- Created `backend/app/agents/aggregation.py` — LangGraph node for aggregating recommendation candidates from external APIs (stubbed initially)
- **`_INTEREST_GIFTS`** — Stub catalog mapping all 40 predefined interest categories to 2-3 gift product ideas each (~104 gift entries total). Each entry includes title, description, price in cents, merchant name, and source (`amazon` or `shopify`). Price range spans $22–$249 across entries for realistic budget filtering
- **`_VIBE_EXPERIENCES`** — Stub catalog mapping all 8 aesthetic vibes to 3 experience/date ideas each (24 experience entries total). Each entry includes title, description, price in cents, merchant name, source (`yelp` or `ticketmaster`), and recommendation type (`experience` or `date`). Price range spans $30–$350
- **`_build_gift_candidate(interest, entry)`** — Constructs a `CandidateRecommendation` from a gift catalog tuple. Generates a unique UUID, builds a slug-based URL, records the matched interest in metadata, and sets `location=None` (gifts are shipped, not location-bound)
- **`_build_experience_candidate(vibe, entry, location)`** — Constructs a `CandidateRecommendation` from an experience catalog tuple. Generates a unique UUID, attaches the vault's location data, and records the matched vibe in metadata
- **`_fetch_gift_candidates(interests, budget_min, budget_max)`** — Async function that looks up gifts for each of the vault's interests from the stub catalog. Filters out candidates whose `price_cents` falls outside the budget range. Caps at `MAX_GIFTS_PER_INTEREST=3` per interest. In Phase 8, this will call `AmazonService` and `ShopifyService`
- **`_fetch_experience_candidates(vibes, budget_min, budget_max, location)`** — Async function that looks up experiences/dates for each vibe. Filters by budget range and attaches location. Caps at `MAX_EXPERIENCES_PER_VIBE=3` per vibe. In Phase 8, this will call `YelpService` and `TicketmasterService`
- **`aggregate_external_data(state)`** — The main LangGraph node function. Takes `RecommendationState`, extracts interests/vibes/budget/location from vault data (location guard checks city, state, or country), calls `_fetch_gift_candidates` and `_fetch_experience_candidates` in parallel via `asyncio.gather(return_exceptions=True)`, handles partial failures (if one fetch fails, the other's results are still returned), interleaves gifts and experiences before capping at `TARGET_CANDIDATE_COUNT=20`, and returns `{"candidate_recommendations": list[CandidateRecommendation]}`. Sets `{"error": "No candidates found matching budget and criteria"}` when zero candidates survive filtering. All logger calls use lazy `%s`/`%d` formatting
- Created `backend/tests/test_aggregation_node.py` — 54 tests across 5 test classes

**Files created:**
- `backend/app/agents/aggregation.py` — External API aggregation LangGraph node (stub catalogs + node function)
- `backend/tests/test_aggregation_node.py` — Aggregation node test suite (54 tests, 5 classes)

**Test results:**
- ✅ `pytest tests/test_aggregation_node.py -v` — 54 passed, 0 failed, 0.07s
- ✅ All 40 interests have gift catalog entries (2-3 each)
- ✅ All 8 vibes have experience catalog entries (3 each)
- ✅ All gift entries use valid source ('amazon' or 'shopify')
- ✅ All experience entries use valid source ('yelp' or 'ticketmaster')
- ✅ All experience entries use valid type ('experience' or 'date')
- ✅ All catalog prices are positive integers (cents)
- ✅ Gift candidate has all required fields (title, description, price, URL, merchant, source, type)
- ✅ Gift candidates get unique UUIDs
- ✅ Gift candidate metadata records matched interest
- ✅ Gift candidates have no location (null)
- ✅ Experience candidate has all required fields
- ✅ Experience candidate includes location when provided
- ✅ Experience candidate metadata records matched vibe
- ✅ Experience candidate 'date' type works correctly
- ✅ Experience candidate accepts null location gracefully
- ✅ Fetch returns candidates for known interests
- ✅ Budget range filters out candidates outside min/max
- ✅ Narrow budget (1-2 cents) returns empty list
- ✅ Unknown interest returns empty list (no crash)
- ✅ Multiple interests combine results from all interests
- ✅ All gift candidates typed as 'gift'
- ✅ Gift sources are 'amazon' or 'shopify'
- ✅ Fetch returns experience candidates for known vibes
- ✅ Experience budget filtering works correctly
- ✅ Location attached to experience candidates
- ✅ Null location accepted for experiences
- ✅ Experience sources are 'yelp' or 'ticketmaster'
- ✅ Node returns 'candidate_recommendations' key
- ✅ All candidates are CandidateRecommendation instances
- ✅ All candidates have title, price_cents > 0, external_url, merchant_name
- ✅ All candidates within budget range
- ✅ Result includes both gifts and experiences/dates
- ✅ Gift candidates match vault interests (subset check)
- ✅ Experience candidates match vault vibes (subset check)
- ✅ Experience candidates carry vault location
- ✅ Missing city/state handled gracefully (experiences get LocationData with country only when country defaults to "US")
- ✅ All candidates have unique IDs
- ✅ Reasonable candidate count (10-20 for standard vault)
- ✅ Capped at TARGET_CANDIDATE_COUNT=20 when all 8 vibes selected
- ✅ Result compatible with state.model_copy(update=result)
- ✅ No error set on normal run
- ✅ Error set when budget excludes all candidates ("No candidates found matching budget and criteria")
- ✅ Gift sources correct on full node run
- ✅ Experience sources correct on full node run
- ✅ All URLs start with https://
- ✅ All candidates have descriptions
- ✅ All scoring fields default to 0.0 (scoring happens in later nodes)
- ✅ Just-because budget ($20-$50) returns affordable candidates
- ✅ Single interest + single vibe returns candidates from each
- ✅ Different currency (EUR) passes through without affecting filtering
- ✅ All 8 vibes selected: result capped at 20
- ✅ CandidateRecommendation JSON round-trip serialization works
- ✅ All existing tests still pass (66 from Steps 5.1-5.2)

**Notes:**
- **Stub catalogs are intentionally comprehensive:** All 40 interests and 8 vibes have catalog entries with realistic product/experience data. This ensures downstream nodes (Steps 5.4-5.6: filter_by_interests, match_vibes_and_love_languages, select_diverse_three) will have meaningful candidates to work with during pipeline development. In Phase 8, the stub catalogs will be replaced by real API calls
- **Budget filtering happens at aggregation time:** Candidates outside `[budget_range.min_amount, budget_range.max_amount]` are excluded before returning. This is efficient (avoids sending irrelevant candidates through the scoring pipeline) and mirrors real API behavior where budget is passed as a query parameter
- **Node return type is `dict[str, Any]`**, following the same LangGraph convention as `retrieve_relevant_hints`. Returns `{"candidate_recommendations": [...]}` and optionally `{"error": "..."}`. Merged into state via `state.model_copy(update=result)`
- **Parallel fetching with `asyncio.gather(return_exceptions=True)`:** Gift and experience fetches run concurrently. If one fails, the other's results are still returned (partial failure tolerance). This pattern will be critical in Phase 8 when real API calls may have independent failure modes
- **Interleaved candidate merging:** Gifts and experiences are interleaved (gift, experience, gift, experience, ...) before the cap is applied. This prevents biased truncation where one type would be systematically dropped when the total exceeds `TARGET_CANDIDATE_COUNT`
- **No external dependencies:** The stub catalogs are pure Python dictionaries. The entire node runs without network access, database queries, or API credentials. This makes the test suite fast (0.07s) and reliable
- **Metadata tracks provenance:** Each candidate records `{"matched_interest": "Cooking"}` or `{"matched_vibe": "romantic"}` in its metadata dict. This enables downstream nodes to trace why a candidate was selected and supports the refresh/exclusion logic in Step 5.10
- **Location is attached to experiences only:** Gift candidates always have `location=None` (they're shipped products). Experience/date candidates carry the vault's location when available. Location is constructed when any of `location_city`, `location_state`, or `location_country` is set (country defaults to `"US"` in VaultData, so location is almost always present). This matches real-world API behavior (Yelp/Ticketmaster are location-aware; Amazon/Shopify are not)
- **Lazy logger formatting:** All `logger.info/error/warning` calls use `%s`/`%d` placeholders instead of f-strings, avoiding string formatting overhead when log levels are disabled
- **`TARGET_CANDIDATE_COUNT=20`:** The node caps total results at 20 via interleaved merging. For a typical vault (5 interests × 2-3 gifts + 2 vibes × 3 experiences = 16-21 before budget filtering), the cap rarely applies. It becomes relevant when all 8 vibes are selected (up to 15 gifts + 24 experiences = 39 pre-filter). Interleaving ensures both types are represented proportionally after capping
- Run tests with: `cd backend && source venv/bin/activate && pytest tests/test_aggregation_node.py -v`

---

## Next Steps

- [ ] **Step 5.4:** Create Semantic Filtering Node (Backend)

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

10. **Apple Developer Program (paid):** Sign in with Apple on the Simulator requires the paid Apple Developer Program ($99/year). Without it, you'll get `ASAuthorizationError error 1000`. The code is correct — it's an account-level limitation. Enroll at [developer.apple.com](https://developer.apple.com) to register App IDs with Sign in with Apple capability.

11. **Sign in with Apple on Simulator:** Three requirements for the Apple Sign-In sheet to appear: (1) `DEVELOPMENT_TEAM` set in Xcode build settings, (2) Apple ID signed in on the Simulator (Settings > Apple Account), (3) App ID registered with Sign in with Apple capability in the Apple Developer portal (requires paid program).

12. **Feature-based folder structure:** New features go in `/Features/{FeatureName}/`. Step 2.1 created `Features/Auth/SignInView.swift`. Future features follow the same pattern: `Features/Onboarding/`, `Features/Home/`, etc.

13. **XcodeGen entitlements gotcha:** XcodeGen will overwrite the entitlements file to an empty `<dict/>` on regeneration UNLESS `entitlements.properties` is specified in `project.yml`. Always declare entitlement capabilities in both the `.entitlements` file AND in `project.yml`'s `entitlements.properties` section.

14. **DEVELOPMENT_TEAM in project.yml:** Must be set to the paid team ID (`VN5G3R8J23`), not empty string. If left empty, `xcodegen generate` will reset the team in the Xcode project, causing error 1000 on Sign in with Apple.

15. **Supabase session storage:** The Supabase Swift SDK automatically stores auth sessions in the iOS Keychain. No manual Keychain code is needed. Session tokens are persisted across app launches and the SDK handles token refresh.

16. **Auth state is driven by `authStateChanges`:** After Step 2.3, all auth state transitions (`isAuthenticated`) flow through the `listenForAuthChanges()` async listener in `AuthViewModel`. Never set `isAuthenticated` manually — let the Supabase SDK emit `signedIn`/`signedOut` events.

17. **Shared AuthViewModel via environment:** `ContentView` creates the `AuthViewModel` and injects it into the SwiftUI environment. All feature views (`SignInView`, `HomeView`, future views) read it via `@Environment(AuthViewModel.self)`. Do not create separate `AuthViewModel` instances in child views.

18. **`@Bindable` wrapper for alert bindings:** When using `@Environment` with `@Observable` objects, you need `@Bindable var viewModel = authViewModel` to create `$`-bindable references for `.alert(isPresented:)` and similar SwiftUI modifiers.

19. **Lucide icon naming convention:** The library uses `{shape}{action}` naming (e.g., `Lucide.circleCheck`, not `Lucide.checkCircle`). Verify icon names against the Lucide Swift source or the derived data symbols.

20. **Sign-out follows the listener pattern:** `signOut()` calls `SupabaseManager.client.auth.signOut()` and does NOT manually set `isAuthenticated = false`. The `authStateChanges` listener handles the `signedOut` event. This is the same single-source-of-truth pattern used for sign-in. Never bypass the listener for auth state changes.

21. **Sign-out button placement (temporary):** The sign-out button is currently on the placeholder Home screen for testing. It will move to the Settings screen in Step 11.1. The toolbar icon can remain for quick access during development.

22. **Onboarding folder structure:** The onboarding feature lives in `Features/Onboarding/`. The container and view model are at the root level; individual step views are in the `Steps/` subfolder. This keeps the file count manageable while maintaining clear organization.

23. **OnboardingViewModel owns all step data:** A single `OnboardingViewModel` holds data for all 9 steps. It is created by `OnboardingContainerView` and injected via `.environment()`. All step views read/write it via `@Environment(OnboardingViewModel.self)`. This ensures data persists when navigating back and forth — the view model is never recreated during the flow.

24. **`canProceed` validation pattern (updated in Step 3.2):** Validation is now centralized in `OnboardingViewModel.validateCurrentStep()` — a switch statement with one case per step. The ViewModel calls it automatically after `goToNextStep()`/`goToPreviousStep()`. Step views also call it via `.onAppear` and `.onChange(of:)` for real-time validation as the user types. When implementing a new step, add a case to the switch in `validateCurrentStep()` and call it from the view's `.onChange` modifier.

25. **`hasCompletedOnboarding` is in-memory only (for now):** The flag resets on app relaunch. Until Step 3.11 (Connect iOS Onboarding to Backend API) checks for an existing vault on session restore, authenticated users will see onboarding on every launch. This is expected during development.

26. **Step transitions use `.id()` for animation:** The step content in `OnboardingContainerView` uses `.id(viewModel.currentStep)` to force SwiftUI view identity changes on each step, enabling the `.transition(.asymmetric(...))` animations. Without `.id()`, SwiftUI would diff in-place and skip the transition.

27. **`@Bindable` in body vs computed properties:** In `OnboardingBasicInfoView`, `@Bindable var vm = viewModel` is declared inside `body` and used for `$vm.partnerName` bindings passed to sub-methods. For computed properties that need bindings (like `tenureSection`), use `Binding(get:set:)` with the `@Environment` viewModel directly, since `@Bindable` is scoped to `body`.

28. **Deferred validation hints:** The "Name is required" hint uses a `@State private var hasInteractedWithName` flag to defer display until the user interacts with the field. This avoids showing validation errors on first load (before the user has had a chance to type). The flag is reset when navigating away (view is recreated via `.id()`), which is correct — the user must have entered a name to leave the step.

29. **Custom Binding decomposition for tenure pickers:** The ViewModel stores tenure as a single `relationshipTenureMonths: Int`. The UI decomposes this into years (0–30) and months (0–11) using `Binding(get: { months / 12 }, set: { viewModel.months = newYears * 12 + remainingMonths })`. This keeps the ViewModel simple (single integer) while the view handles the UI decomposition.

30. **App-wide dark theme (`.preferredColorScheme(.dark)`):** Set in `KnotApp.swift` on the `ContentView`. Affects the entire window — all system controls, navigation bars, and semantic colors resolve to dark mode values automatically. Individual views should NOT set `.preferredColorScheme(.dark)` — it's handled globally.

31. **`Theme.swift` design system:** All colors are centralized in `Core/Theme.swift`. Use `Theme.accent` instead of `.pink`, `Theme.surface` instead of `Color(.systemGray6)`, `Theme.backgroundGradient` for screen backgrounds. When adding new views, always use `Theme` constants — never hardcode colors.

32. **Background gradient strategy:** `Theme.backgroundGradient` (dark purple gradient) is applied by each major container view (`SignInView`, `OnboardingContainerView`, `HomeView`) with `.ignoresSafeArea()`. Step views inside the onboarding container are transparent and inherit the container's background. New container-level screens should apply the gradient; new child views should not.

33. **Apple Sign-In button on dark background:** Uses `.signInWithAppleButtonStyle(.white)` for high contrast. The `.black` style is invisible on the dark background. If the app theme changes, this should be updated accordingly.

34. **SF Symbol icon mapping for interests:** A static `[String: String]` dictionary in `OnboardingInterestsView` maps each of the 40 interest categories to an SF Symbol name. All symbols target iOS 17.0+. Add new mappings here when adding new interest categories.

35. **Card gradient hue rotation:** Interest cards use `hue = index / count` to spread 40 categories across the full color wheel (0.0 to 1.0). This ensures every card has a unique, visually distinct gradient without manual color assignment. The formula works for any number of categories.

36. **Reusing static methods across onboarding views:** `OnboardingInterestsView.cardGradient(for:)` and `.iconName(for:)` are `static` (not `private static`) so that `OnboardingDislikesView` can call them directly for consistent visuals. Do not make these `private` — it would break the dislikes screen.

37. **Disabled card pattern for conflict prevention:** The dislikes screen uses a `DislikeImageCard` with an `isDisabled` parameter. When `true`, the card shows flat gray (`Color(white: 0.18)`), 50% opacity, dimmed text, a heart badge, and `.disabled(true)` on the `Button`. The action closure also guards with `if !isLiked` as a secondary safety net.

38. **Double-guard validation for likes/dislikes overlap:** The UI prevents overlap via `.disabled(true)` on liked cards. The ViewModel adds `isDisjoint(with:)` as a programmatic safety net. Both guards exist because the ViewModel may be modified in tests or future code without the UI guardrail.

39. **`CustomMilestone` and `HolidayOption` structs:** Both live in `OnboardingViewModel.swift` (not in `/Models/`). They are small, tightly coupled to onboarding, and conform to `Identifiable` + `Sendable`. If vault editing (Step 3.12) needs them, extract to a shared location.

40. **Holiday dates are approximate for floating holidays:** Mother's Day (`May 11`) and Father's Day (`Jun 15`) use fixed dates in `HolidayOption`. The actual "2nd Sunday of May" / "3rd Sunday of June" computation happens at notification scheduling time (Step 7.2), not during onboarding. This is intentional — onboarding stores the holiday *identity* (e.g., `"mothers_day"`), not the exact date for a specific year.

41. **Day clamping when month changes:** `OnboardingViewModel.clampDay(_:toMonth:)` ensures the day value stays valid when the month changes (e.g., March 31 → February clamps to 29). The birthday and anniversary `Binding(get:set:)` closures call this on every month change. The custom milestone sheet also clamps before saving.

42. **February allows day 29:** `daysInMonth(2)` returns 29 to support leap year birthdays. Year-specific validation happens when computing next occurrence for notifications, not during onboarding input.

43. **Reusable `monthPicker()` and `dayPicker()` within MilestonesView:** These are `private func` helpers inside the view, not `/Components/` components, because they are specific to the month+day milestone format. They accept `Binding<Int>` and could be extracted if future screens need similar date pickers.

44. **Custom milestone sheet state management:** The sheet uses `@State` properties (`customName`, `customMonth`, `customDay`, `customRecurrence`) local to `OnboardingMilestonesView`, not the ViewModel. This keeps the sheet's temporary "work in progress" state separate from committed data. The `resetCustomSheetState()` method clears these before each sheet presentation.

45. **`HolidayChip` is a private struct:** The `HolidayChip` component lives inside `OnboardingMilestonesView.swift` as a `private struct`. It is not reusable outside this file and does not need to be in `/Components/`.

46. **Vibes use hand-tuned gradients (not hue rotation):** Unlike interests (which use `hue = index / count` for auto-generated gradients), each vibe has a manually defined 2-color gradient that evokes its aesthetic. This is intentional — 8 vibes are few enough to curate, and the color should match the vibe's meaning (warm gold = luxury, forest green = outdoorsy, etc.).

47. **Vibes have no maximum selection limit:** The implementation plan specified max 4, but this was removed per user feedback. All 8 can be selected. The `Constants.Validation.maxVibes` constant still exists but is not enforced. If a cap is reintroduced, add the check in `OnboardingVibesView.toggleVibe()` and restore the max check in `validateCurrentStep()`.

48. **`VibeCard` uses Lucide icons (UIImage), not SF Symbols:** The vibes screen maps each vibe to a `Lucide.*` static property returning `UIImage`. These are rendered via `Image(uiImage:).renderingMode(.template)`. The interests screen uses SF Symbols (`Image(systemName:)`). Both approaches work on the dark theme — use whichever icon library has the best match for the concept.

49. **Validation error banner pattern (Step 3.6):** The `OnboardingContainerView` now shows a red error banner when the user taps Next while `canProceed` is false. The message comes from `OnboardingViewModel.validationMessage` — a computed property with a `switch` on `currentStep`. To add validation messages for new steps: (1) add a case to `validateCurrentStep()`, (2) add a matching case to `validationMessage`. The container handles display, animation, and auto-dismiss automatically.

50. **Next button is always tappable (post-Step 3.6):** The Next button no longer uses `.disabled(!viewModel.canProceed)`. Instead, it's always tappable and checks `canProceed` in its action closure. When invalid, it shows the error banner. When valid, it advances normally. The button tint dims to `Theme.accent.opacity(0.4)` when invalid as a visual hint. This change applies to ALL onboarding steps, not just vibes.

51. **`FlowLayout` named parameters:** The custom `FlowLayout` component uses `horizontalSpacing` and `verticalSpacing` named parameters, NOT a single `spacing` parameter. Always call `FlowLayout(horizontalSpacing: 6, verticalSpacing: 6)`. Using `FlowLayout(spacing: 6)` will not compile.

52. **Cross-view static method references for display names/icons:** The completion screen calls `OnboardingVibesView.displayName(for:)`, `.vibeIcon(for:)`, `OnboardingLoveLanguagesView.displayName(for:)`, and `.languageIcon(for:)`. These must stay `static` (not `private static`). Any step view that exposes display names or icon mappings should follow this pattern for cross-view reuse.

53. **`SummaryCard` and `CompactTag` are private to OnboardingCompletionView.swift:** These are not in `/Components/` because they are tightly coupled to the completion screen. If future screens need similar card layouts or tag components, extract them to `/Components/` at that point.

54. **`.fixedSize(horizontal: true, vertical: false)` for non-wrapping buttons:** Applied to all navigation button `HStack` labels in `OnboardingContainerView`. This tells SwiftUI to use the text's ideal width and never compress or wrap. Essential for short labels ("Back", "Next", "Get Started") that should always remain on one line.

55. **Navigation button sizing (post-Step 3.9):** Buttons use `.subheadline` font (not `.body`), height 44 (not 50), and reduced horizontal padding (Back: 14, Next/Get Started: 20) to fit comfortably side-by-side without text wrapping on any screen size.

56. **Vault API uses service_role client:** The `POST /api/v1/vault` endpoint uses `get_service_client()` (bypasses RLS) because it inserts into 6 tables on behalf of the authenticated user. The user's identity is validated by the `get_current_user_id` auth middleware dependency. This is safe because the endpoint only creates data for `user_id` — it cannot access other users' data.

57. **Pydantic models mirror DB CHECK constraints:** The `VALID_*` constant sets in `app/models/vault.py` mirror the CHECK constraints in the database migrations. Validation happens twice: first at the API layer (Pydantic, with friendly error messages) and again at the DB layer (CHECK constraints, as a safety net). Keep these in sync when adding new categories.

58. **Milestone `budget_tier` nullable in Pydantic, NOT NULL in DB:** The `MilestoneCreate.budget_tier` is `Optional` in the Pydantic model because the DB trigger sets defaults for birthday/anniversary/holiday types. Custom milestones require it (enforced by `@model_validator`). PostgREST sends `null` for `None` values, and the BEFORE INSERT trigger converts it to the correct default.

59. **Vault creation is pseudo-transactional:** PostgREST does not support multi-table transactions. The endpoint inserts sequentially and uses `_cleanup_vault()` to delete partial data if a later insert fails. CASCADE on `partner_vaults` removes all child rows. This is a "poor man's transaction" — acceptable for MVP but should be replaced with a Supabase Edge Function or stored procedure for production.

60. **409 Conflict for duplicate vaults:** The UNIQUE constraint on `partner_vaults.user_id` prevents multiple vaults per user. The endpoint catches this as a `23505` PostgreSQL error code (or "duplicate"/"unique" in the error string) and returns 409 with a message directing users to `PUT /api/v1/vault` (Step 3.12).

61. **Test pattern for vault API tests:** The `test_vault_api.py` tests follow the same fixture pattern as `test_auth_middleware.py`: `test_auth_user_with_token` creates a real auth user, signs them in, and yields the access token. Cleanup deletes the auth user (CASCADE removes all data). The `_valid_vault_payload()` helper returns a complete payload that can be modified per test. `_query_table()` queries PostgREST directly with the service role key to verify data integrity.

62. **VaultService is `@MainActor` (Step 3.11):** `VaultService` is annotated `@MainActor` because it's called from `OnboardingViewModel` and `AuthViewModel` (both `@MainActor`). It uses `URLSession.shared` (which is safe to call from any actor) and `SupabaseManager.client` (also safe). The `@MainActor` annotation satisfies Swift 6 strict concurrency without requiring `nonisolated` workarounds.

63. **Backend URL conditional compilation (Step 3.11):** `Constants.API.baseURL` uses `#if DEBUG` to switch between localhost (development) and the production URL. This is evaluated at compile time — no runtime cost. Release builds (Archive for App Store) automatically use the production URL.

64. **Vault existence check is non-throwing (Step 3.11):** `VaultService.vaultExists()` returns `Bool` (not `throws`). If the PostgREST query fails for any reason (network, table doesn't exist yet, auth expired), it catches the error and returns `false`. This safe default means the user sees onboarding, and if they already have a vault, the submission will return 409 (handled gracefully). Failing open to onboarding is preferable to failing closed to Home with no data.

65. **`isCheckingSession` delayed until vault check completes (Step 3.11):** In `AuthViewModel.listenForAuthChanges()`, `isCheckingSession = false` is set AFTER the `vaultExists()` call (not before). This keeps the loading spinner visible during both session restore and vault existence check. Without this ordering, the user sees a flash of the onboarding screen before being redirected to Home.

66. **`hasCompletedOnboarding` reset on sign-out (Step 3.11):** The `signedOut` handler sets `hasCompletedOnboarding = false`. This is necessary because a different user might sign in on the same device. Without the reset, the second user would skip onboarding based on the first user's vault state.

67. **Custom milestones default to `minor_occasion` budget tier (Step 3.11):** The onboarding UI (Step 3.5) does not include a budget tier picker for custom milestones, but the backend requires one. `buildVaultPayload()` defaults to `"minor_occasion"`. To add budget tier selection for custom milestones, add a picker to the custom milestone sheet in `OnboardingMilestonesView.swift` and a corresponding property on `CustomMilestone`.

68. **`NSAllowsLocalNetworking` scope (Step 3.11):** The `Info.plist` setting only allows HTTP for local network addresses (localhost, 127.0.0.1, link-local). External domains still require HTTPS. This is safe to leave in production builds — it has no effect on App Store apps since they don't connect to localhost.

69. **PUT uses "replace all" strategy (Step 3.12):** The `PUT /api/v1/vault` endpoint deletes all child rows (interests, milestones, vibes, budgets, love languages) and re-inserts new ones, rather than diffing changes. This is simpler, avoids tracking which specific rows changed, and the overhead is minimal (~15 rows per table). The vault row itself is updated in place (not deleted), preserving the `vault_id`. If granular updates become needed (e.g., for performance with large datasets), switch to a diff-based approach with `UPSERT` operations.

70. **`VaultCreateRequest` is reused for PUT (Step 3.12):** No separate `VaultUpdateRequest` Pydantic model was created because the same validation rules apply (exactly 5 interests, 5 dislikes, valid categories, etc.). The endpoint function signature uses `VaultCreateRequest` directly. If PUT ever needs different validation (e.g., optional fields that POST requires), create a `VaultUpdateRequest` extending or modifying the base.

71. **Edit Profile reuses onboarding step views (Step 3.12):** `EditVaultView` creates a fresh `OnboardingViewModel`, populates it from the GET response, and injects it via `.environment()`. The onboarding step views (InterestsView, VibesView, etc.) read from `@Environment(OnboardingViewModel.self)` and work identically in both onboarding and edit contexts. No step views were modified. This pattern works because step views are pure functions of ViewModel state.

72. **Budget range IDs don't round-trip perfectly (Step 3.12):** When loading vault data for editing, budget min/max are set on the ViewModel directly (e.g., `justBecauseMin = 3000`, `justBecauseMax = 8000`), and the range ID is set to `"\(min)-\(max)"` (e.g., `"3000-8000"`). This may not match the preset range IDs from onboarding (e.g., `"2000-5000"`). As a result, the budget view's preset buttons won't appear "selected" for custom or previously saved ranges. The effective min/max values are still correct. To fix: map saved ranges back to nearest presets, or add visual indicator for custom ranges.

73. **Holiday milestones matched by month/day (Step 3.12):** When loading vault data, holiday milestones are matched back to `HolidayOption.allHolidays` by comparing `(month, day)` — not by name or ID. This works because each holiday has a unique month/day combination. If two holidays share a date in the future, add a `holiday_id` column to `partner_milestones` for unambiguous matching.

74. **`EditSection` enum is `Identifiable` via `rawValue` (Step 3.12):** The `EditSection` enum uses `rawValue: String` and `var id: String { rawValue }` to conform to `Identifiable`. This enables SwiftUI's `.sheet(item: $activeSection)` modifier to present the correct sheet for each section. The `title` computed property provides human-readable names for navigation bar titles.

75. **Edit Profile uses `.fullScreenCover` not `.sheet` (Step 3.12):** The Edit Profile is presented as `.fullScreenCover(isPresented:)` from HomeView, not `.sheet`. This provides a full-screen experience matching onboarding and prevents accidental dismissal by swiping down. The "Cancel" button in the navigation bar is the only way to dismiss.

76. **`CustomMilestone` and `HolidayOption` stay in OnboardingViewModel.swift (Step 3.12):** Note #39 mentioned extracting these if vault editing needed them. `EditVaultView` accesses them just fine since they're public structs in the same module. No extraction was necessary. If they're ever needed by backend code or a separate framework target, extract them to `/Models/`.

77. **Embedding service uses lazy initialization (Step 4.4):** `app/services/embedding.py` initializes the Vertex AI model only once, on the first call to `generate_embedding()`. The `_initialized` flag ensures initialization is attempted only once — if it fails, subsequent calls skip immediately (return `None`). Use `_reset_model()` in tests to force re-initialization.

78. **Graceful degradation for embeddings (Step 4.4):** The entire embedding pipeline is designed to be non-fatal. If `GOOGLE_CLOUD_PROJECT` is empty, the model isn't loaded. If the API call fails, the exception is caught and logged. In all failure cases, `generate_embedding()` returns `None`, and the hint is saved with `hint_embedding = NULL`. The 201 response is identical to the client whether or not embedding succeeded. This means the iOS app works identically with or without Vertex AI configured.

79. **`asyncio.to_thread()` for synchronous SDK calls (Step 4.4):** The Vertex AI Python SDK's `model.get_embeddings()` is synchronous. Wrapping it in `asyncio.to_thread()` runs it in the default thread pool executor, preventing it from blocking the FastAPI async event loop. This is the standard pattern for calling synchronous libraries from async FastAPI endpoints.

80. **pgvector string format for PostgREST (Step 4.4):** `format_embedding_for_pgvector()` converts `list[float]` to the string `"[0.1,0.2,...,0.768]"`. PostgREST (and by extension the Supabase Python client) accepts this format for `vector(768)` columns. The database stores it as a native pgvector type. When reading back via PostgREST, the column returns as a string in the same format.

81. **Mocking pattern for embedding tests (Step 4.4):** Tests use `unittest.mock.patch("app.api.hints.generate_embedding", new_callable=AsyncMock)` to mock at the import location in `hints.py`. This is the correct pattern because `hints.py` does `from app.services.embedding import generate_embedding` — patching at `app.services.embedding.generate_embedding` would not affect the already-imported reference in `hints.py`. Always patch at the import site, not the definition site.

82. **`requires_vertex_ai` test marker (Step 4.4):** The 4 live Vertex AI tests are gated by `requires_vertex_ai = pytest.mark.skipif(not _vertex_ai_configured(), ...)`. To enable them: (1) set `GOOGLE_CLOUD_PROJECT=your-project-id` in `.env`, (2) ensure Application Default Credentials are configured (`gcloud auth application-default login`). The `GOOGLE_APPLICATION_CREDENTIALS` env var is optional if ADC is configured.
