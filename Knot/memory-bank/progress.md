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

## Next Steps

- [ ] **Step 2.5:** Create Backend Auth Middleware
- [ ] **Step 3.4:** Build Dislikes Selection Screen (iOS)

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
