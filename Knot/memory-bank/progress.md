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

## Next Steps

- [ ] **Step 1.10:** Create User Feedback Table

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
