# Architecture Guide: Project Knot

This document explains the purpose of each file and folder for future developers.

---

## Project Structure Overview

```
Knot/
├── memory-bank/               # Documentation and planning
│   ├── PRD.md                 # Product Requirements Document
│   ├── techstack.md           # Technology stack decisions
│   ├── IMPLEMENTATION_PLAN.md # Step-by-step build instructions
│   ├── progress.md            # Implementation progress log
│   └── architecture.md        # This file
├── iOS/                       # iOS application (Swift/SwiftUI)
└── backend/                   # Python/FastAPI backend
```

---

## iOS Application (`iOS/`)

### Configuration Files

| File | Purpose |
|------|---------|
| `project.yml` | XcodeGen configuration. Defines targets, build settings, and dependencies. Run `xcodegen generate` after modifying. |
| `Knot.xcodeproj/` | Generated Xcode project. **Do not edit directly** — modify `project.yml` instead. |
| `Knot/Info.plist` | iOS app configuration (bundle name, supported orientations, launch screen). |

### Source Code (`iOS/Knot/`)

#### `/App` — Application Entry Point
| File | Purpose |
|------|---------|
| `KnotApp.swift` | Main app entry point. Configures SwiftData ModelContainer and injects it into the app environment. |
| `ContentView.swift` | Root view displayed on launch. Will be replaced with navigation logic (Auth vs Home). |

#### `/Features` — Feature Modules
Organized by feature, each containing Views, ViewModels, and feature-specific components.

| Folder | Purpose |
|--------|---------|
| `Auth/` | Apple Sign-In flow, session management |
| `Onboarding/` | Partner Vault creation (9-step wizard) |
| `Home/` | Main dashboard with hint capture and milestone cards |
| `Recommendations/` | Choice-of-Three UI, refresh flow |
| `HintCapture/` | Text and voice hint input |
| `Settings/` | User preferences, account management |

#### `/Core` — Shared Utilities
| File | Purpose |
|------|---------|
| `Constants.swift` | App-wide constants: API URLs, validation rules, predefined categories (41 interests, 8 vibes, 5 love languages). |

Future files:
- `Extensions.swift` — Swift type extensions
- `Theme.swift` — Colors, typography, spacing (design system)
- `NetworkMonitor.swift` — Online/offline detection

#### `/Services` — Data & API Layer
| File | Purpose |
|------|---------|
| `SupabaseClient.swift` | Supabase connection and auth client |
| `APIClient.swift` | HTTP client for backend API calls |
| `AuthService.swift` | Authentication logic (sign in, sign out, session) |
| `VaultService.swift` | Partner Vault CRUD operations |
| `HintService.swift` | Hint capture and retrieval |
| `RecommendationService.swift` | Recommendation fetching and feedback |

#### `/Models` — Data Models
| File | Purpose |
|------|---------|
| `PartnerVaultLocal.swift` | SwiftData model for local vault storage |
| `HintLocal.swift` | SwiftData model for hints |
| `MilestoneLocal.swift` | SwiftData model for milestones |
| `RecommendationLocal.swift` | SwiftData model for recommendations |
| `DTOs.swift` | Data Transfer Objects for API requests/responses |

#### `/Components` — Reusable UI Components
Shadcn-inspired, reusable SwiftUI components.

| Component | Purpose |
|-----------|---------|
| `ChipView.swift` | Selectable tag/pill for interests and vibes |
| `CardView.swift` | Recommendation card with image, title, price |
| `ButtonStyles.swift` | Primary, secondary, and ghost button styles |
| `InputField.swift` | Text input with label and validation |
| `LoadingView.swift` | Loading spinner with optional message |

#### `/Resources` — Assets
| File | Purpose |
|------|---------|
| `Assets.xcassets/` | App icon, accent color, and image assets |
| `Colors.xcassets/` | Named colors for the design system |

### Test Targets

| Folder | Purpose |
|--------|---------|
| `KnotTests/` | Unit tests for business logic, services, and utilities |
| `KnotUITests/` | UI tests for critical user flows (onboarding, hint capture) |

---

## Backend (`backend/`)

```
backend/
├── app/
│   ├── __init__.py           # App package marker
│   ├── main.py               # FastAPI entry point, app factory, /health endpoint
│   ├── api/                  # Route handlers (one file per API domain)
│   │   ├── __init__.py
│   │   ├── vault.py          # POST/PUT/GET /api/v1/vault — Partner Vault CRUD
│   │   ├── hints.py          # POST/GET/DELETE /api/v1/hints — Hint capture & retrieval
│   │   ├── recommendations.py # POST /api/v1/recommendations — Generation & refresh
│   │   └── users.py          # POST/GET/DELETE /api/v1/users — Account management
│   ├── core/                 # Configuration & cross-cutting concerns
│   │   ├── __init__.py
│   │   ├── config.py         # App settings (API prefix, project name, env vars)
│   │   └── security.py       # Auth middleware — validates Supabase JWT Bearer tokens
│   ├── models/               # Pydantic schemas for request/response validation
│   │   └── __init__.py
│   ├── services/             # Business logic layer
│   │   ├── __init__.py
│   │   └── integrations/     # External API clients
│   │       └── __init__.py   # (Yelp, Ticketmaster, Amazon, Shopify, Firecrawl)
│   ├── agents/               # LangGraph recommendation pipeline
│   │   └── __init__.py       # (hint retrieval → aggregation → filtering → scoring → selection)
│   └── db/                   # Database connection and repository pattern classes
│       ├── __init__.py
│       └── supabase_client.py # Lazy-initialized Supabase clients (anon + service role)
├── supabase/                  # Supabase project configuration
│   └── migrations/            # SQL migrations (run via SQL Editor or Supabase CLI)
│       ├── 00001_enable_pgvector.sql  # Enables pgvector extension for vector search
│       ├── 00002_create_users_table.sql  # Users table with RLS, triggers, and grants
│       ├── 00003_create_partner_vaults_table.sql  # Partner vaults with CHECK, UNIQUE, RLS, CASCADE
│       ├── 00004_create_partner_interests_table.sql  # Partner interests (likes/dislikes) with CHECK, UNIQUE, RLS, CASCADE
│       ├── 00005_create_partner_milestones_table.sql # Partner milestones with CHECK, trigger-based budget defaults, RLS, CASCADE
│       ├── 00006_create_partner_vibes_table.sql     # Partner aesthetic vibes with CHECK (8 values), UNIQUE, RLS, CASCADE
│       ├── 00007_create_partner_budgets_table.sql   # Partner budgets with CHECK (occasion_type, max>=min, min>=0), UNIQUE, RLS, CASCADE
│       ├── 00008_create_partner_love_languages_table.sql # Partner love languages with CHECK (language, priority), dual UNIQUE, RLS, CASCADE
│       ├── 00009_create_hints_table.sql                  # Hints with vector(768) embedding, HNSW index, match_hints() RPC, RLS, CASCADE
│       └── 00010_create_recommendations_table.sql        # Recommendations with CHECK (type), price_cents >= 0, milestone FK SET NULL, RLS, CASCADE
├── tests/                    # Backend test suite (pytest)
│   ├── __init__.py
│   ├── test_imports.py       # Verifies all dependencies are importable (11 tests)
│   ├── test_supabase_connection.py  # Verifies Supabase connectivity and pgvector (11 tests)
│   ├── test_supabase_auth.py # Verifies auth service and Apple Sign-In config (6 tests)
│   ├── test_users_table.py   # Verifies users table schema, RLS, and triggers (10 tests)
│   ├── test_partner_vaults_table.py  # Verifies partner_vaults schema, constraints, RLS, cascades (15 tests)
│   ├── test_partner_interests_table.py  # Verifies partner_interests schema, CHECK/UNIQUE constraints, RLS, cascades (22 tests)
│   ├── test_partner_milestones_table.py # Verifies partner_milestones schema, budget tier trigger, RLS, cascades (28 tests)
│   ├── test_partner_vibes_table.py      # Verifies partner_vibes schema, CHECK/UNIQUE constraints, RLS, cascades (19 tests)
│   ├── test_partner_budgets_table.py    # Verifies partner_budgets schema, CHECK constraints (occasion_type, max>=min, min>=0), UNIQUE, RLS, cascades (27 tests)
│   ├── test_partner_love_languages_table.py # Verifies partner_love_languages schema, CHECK (language, priority), dual UNIQUE, RLS, update semantics, cascades (28 tests)
│   ├── test_hints_table.py               # Verifies hints schema, CHECK (source), vector(768) embedding, HNSW index, match_hints() RPC similarity search, RLS, cascades (30 tests)
│   └── test_recommendations_table.py     # Verifies recommendations schema, CHECK (type, price>=0), milestone FK SET NULL, RLS, data integrity, cascades (31 tests)
├── venv/                     # Python 3.13 virtual environment (gitignored)
├── requirements.txt          # Python dependencies (all packages for MVP)
├── pyproject.toml            # Pytest configuration (asyncio mode, warning filters)
├── .env.example              # Template for environment variables (safe to commit)
├── .env                      # Actual secrets (gitignored, NEVER commit)
└── .gitignore                # Excludes .env, __pycache__, venv, IDE files
```

### Entry Point (`app/main.py`)

| Symbol | Purpose |
|--------|---------|
| `app` | The FastAPI application instance. Title: "Knot API", version: "0.1.0". |
| `health_check()` | `GET /health` — Returns `{"status": "ok"}`. Used by deployment platforms for uptime monitoring. |

API routers from `app/api/` will be registered here via `app.include_router()` as endpoints are implemented.

### Route Handlers (`app/api/`)

Each file defines an `APIRouter` with a URL prefix and tag. Routes will be added as features are implemented.

| File | Prefix | Responsibility |
|------|--------|----------------|
| `vault.py` | `/api/v1/vault` | Partner Vault creation, retrieval, and updates. Accepts the full onboarding payload (basic info, interests, milestones, vibes, budgets, love languages). |
| `hints.py` | `/api/v1/hints` | Hint capture (text/voice), listing, and deletion. Generates vector embeddings via Vertex AI `text-embedding-004`. |
| `recommendations.py` | `/api/v1/recommendations` | Triggers the LangGraph pipeline to generate Choice-of-Three. Handles refresh/re-roll with exclusion logic and feedback collection. |
| `users.py` | `/api/v1/users` | Device token registration (APNs), data export (GDPR), and account deletion. |

### Configuration (`app/core/`)

| File | Purpose |
|------|---------|
| `config.py` | Loads environment variables from `.env` via `python-dotenv`. Exposes `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`, and future API keys. Provides `validate_supabase_config()` to check required vars are present. |
| `security.py` | Auth middleware placeholder. Will extract Bearer tokens from `Authorization` header, validate against Supabase Auth, and return the authenticated user ID. Raises `HTTPException(401)` if invalid. Implemented in Step 2.5. |

### Data Layer (`app/models/`, `app/db/`)

| Folder/File | Purpose |
|-------------|---------|
| `models/` | Pydantic models for API request/response validation. Ensures strict schema adherence (e.g., exactly 5 interests, valid vibe tags). |
| `db/` | Database connection and repository pattern classes. |
| `db/supabase_client.py` | Provides two lazy-initialized Supabase clients: `get_supabase_client()` uses the anon key (respects RLS for user-scoped queries) and `get_service_client()` uses the service_role key (bypasses RLS for admin/background operations). Also provides `test_connection()` to verify database connectivity. |

### Supabase Migrations (`supabase/migrations/`)

SQL migration files to be run in the Supabase SQL Editor or via `supabase db push`.

| File | Purpose |
|------|---------|
| `00001_enable_pgvector.sql` | Enables the `vector` extension (pgvector) required for hint embedding storage and similarity search. Must be run before creating any tables with `vector(768)` columns. |
| `00002_create_users_table.sql` | Creates `public.users` table (id, email, created_at, updated_at) linked to `auth.users` via FK with CASCADE delete. Enables RLS with SELECT/UPDATE/INSERT policies enforcing `auth.uid() = id`. Creates two trigger functions: `handle_updated_at()` (reusable, auto-updates timestamp on row changes) and `handle_new_user()` (SECURITY DEFINER, auto-creates profile on auth signup). Grants permissions to `authenticated` and `anon` roles. |
| `00003_create_partner_vaults_table.sql` | Creates `public.partner_vaults` table (id, user_id, partner_name, relationship_tenure_months, cohabitation_status, location_city, location_state, location_country, created_at, updated_at). `user_id` is UNIQUE (one vault per user) with FK CASCADE to `public.users`. CHECK constraint on `cohabitation_status` for 3 valid enum values. `location_country` defaults to `'US'`. Reuses `handle_updated_at()` trigger from migration 00002. RLS policies enforce `auth.uid() = user_id` for all 4 operations (SELECT, INSERT, UPDATE, DELETE). |
| `00004_create_partner_interests_table.sql` | Creates `public.partner_interests` table (id, vault_id, interest_type, interest_category, created_at). Two CHECK constraints: `interest_type` for 'like'/'dislike', `interest_category` for 40 predefined categories. `UNIQUE(vault_id, interest_category)` prevents duplicate categories and blocks same interest as both like and dislike. FK CASCADE to `partner_vaults`. RLS policies use subquery to `partner_vaults` to check ownership via `auth.uid() = user_id`. Index on `vault_id` for fast lookups. "Exactly 5 likes + 5 dislikes" enforced at application layer, not database. |
| `00005_create_partner_milestones_table.sql` | Creates `public.partner_milestones` table (id, vault_id, milestone_type, milestone_name, milestone_date, recurrence, budget_tier, created_at). Three CHECK constraints: `milestone_type` for 4 types (birthday/anniversary/holiday/custom), `recurrence` for yearly/one_time, `budget_tier` for 3 tiers. Creates `handle_milestone_budget_tier()` BEFORE INSERT trigger that auto-sets budget_tier when not provided: birthday/anniversary → major_milestone, holiday → minor_occasion, custom → must be explicit (NULL rejected by NOT NULL). No UNIQUE constraint on (vault_id, milestone_type) — multiple milestones of same type allowed (e.g., multiple holidays). FK CASCADE to `partner_vaults`. RLS uses subquery pattern. Index on `vault_id`. |
| `00006_create_partner_vibes_table.sql` | Creates `public.partner_vibes` table (id, vault_id, vibe_tag, created_at). CHECK constraint on `vibe_tag` for 8 valid aesthetic values: quiet_luxury, street_urban, outdoorsy, vintage, minimalist, bohemian, romantic, adventurous. `UNIQUE(vault_id, vibe_tag)` prevents duplicate vibes per vault (same deduplication pattern as `partner_interests`). No trigger functions needed — vibes are simple tag storage with no computed defaults. "Minimum 1, maximum 4 vibes per vault" enforced at API layer, not database. FK CASCADE to `partner_vaults`. RLS uses subquery pattern. Index on `vault_id`. |
| `00007_create_partner_budgets_table.sql` | Creates `public.partner_budgets` table (id, vault_id, occasion_type, min_amount, max_amount, currency, created_at). CHECK constraint on `occasion_type` for 3 budget tiers: just_because, minor_occasion, major_milestone. Two cross-column CHECK constraints: `max_amount >= min_amount` (prevents invalid ranges) and `min_amount >= 0` (prevents negative amounts). Amounts stored as **integers in cents** (e.g., 2000 = $20.00) to avoid floating-point precision issues. `UNIQUE(vault_id, occasion_type)` ensures one budget per occasion type per vault. `currency` defaults to `'USD'` — international users can override. No trigger functions needed — budgets are direct value storage. "Exactly 3 tiers per vault" enforced at API layer, not database. FK CASCADE to `partner_vaults`. RLS uses subquery pattern. Index on `vault_id`. |
| `00008_create_partner_love_languages_table.sql` | Creates `public.partner_love_languages` table (id, vault_id, language, priority, created_at). CHECK constraint on `language` for 5 valid values: words_of_affirmation, acts_of_service, receiving_gifts, quality_time, physical_touch. CHECK constraint on `priority` for values 1 (primary) and 2 (secondary) only. **Dual UNIQUE constraint strategy:** `UNIQUE(vault_id, priority)` prevents duplicate priorities per vault (at most one primary, one secondary), and `UNIQUE(vault_id, language)` prevents the same language from being both primary and secondary. Combined with the priority CHECK constraint, the maximum is exactly 2 rows per vault — a third row is impossible because no valid priority slot remains. No trigger functions needed. "Both primary and secondary must exist" minimum cardinality enforced at API layer, not database. FK CASCADE to `partner_vaults`. RLS uses subquery pattern. Index on `vault_id`. |
| `00009_create_hints_table.sql` | Creates `public.hints` table (id, vault_id, hint_text, hint_embedding, source, created_at, is_used). **First table with a pgvector column:** `hint_embedding vector(768)` stores embeddings from Vertex AI `text-embedding-004`. Column is **nullable** for resilience (hints can be stored even if embedding generation fails). CHECK constraint on `source` for 2 values: text_input, voice_transcription. `is_used` defaults to false (tracks whether hint was used in a recommendation). **HNSW index** on `hint_embedding` using `vector_cosine_ops` for fast cosine similarity nearest-neighbor search. Creates **`match_hints()` RPC function** for semantic similarity queries via PostgREST (returns hints ordered by cosine similarity with a computed similarity score). No UNIQUE constraints — unlimited hints per vault. FK CASCADE to `partner_vaults`. RLS uses subquery pattern. Index on `vault_id`. EXECUTE granted on `match_hints()` to authenticated and anon roles. |
| `00010_create_recommendations_table.sql` | Creates `public.recommendations` table (id, vault_id, milestone_id, recommendation_type, title, description, external_url, price_cents, merchant_name, image_url, created_at). Stores AI-generated gift, experience, and date recommendations from the LangGraph pipeline. CHECK constraint on `recommendation_type` for 3 values: gift, experience, date. CHECK constraint on `price_cents >= 0` (stored in cents, nullable when price unknown). `title` is NOT NULL; `description`, `external_url`, `merchant_name`, `image_url` are nullable for resilience against partial external API data. **First table with ON DELETE SET NULL:** `milestone_id` FK to `partner_milestones` uses SET NULL (not CASCADE) — recommendations persist as history even when the milestone they were generated for is deleted. `vault_id` FK still uses CASCADE (deleting vault removes all recommendations). Two indexes: `vault_id` for vault queries, `milestone_id` for milestone queries. No UNIQUE constraints — unlimited recommendations per vault (generated in batches of 3). RLS uses subquery pattern through `partner_vaults`. |

### Business Logic (`app/services/`)

| Folder | Purpose |
|--------|---------|
| `services/` | Core business logic (vault operations, hint processing, notification scheduling). |
| `services/integrations/` | External API clients. Each integration (Yelp, Ticketmaster, Amazon, Shopify, Firecrawl) gets its own service class returning normalized `CandidateRecommendation` objects. |

### AI Pipeline (`app/agents/`)

| Folder | Purpose |
|--------|---------|
| `agents/` | LangGraph agent definitions for the recommendation pipeline. The graph chains: hint retrieval → external API aggregation → interest filtering → vibe/love language scoring → diversity selection → availability verification. |

### Environment Variables (`backend/.env.example`)

All required env vars are templated in `.env.example`:
- **Supabase:** `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`
- **Vertex AI:** `GOOGLE_CLOUD_PROJECT`, `GOOGLE_APPLICATION_CREDENTIALS`
- **External APIs:** Yelp, Ticketmaster, Amazon, Shopify, Firecrawl keys
- **Upstash:** QStash token and URL for notification scheduling
- **APNs:** Key ID, Team ID, auth key path for push notifications

---

## Key Architectural Decisions

### 1. Feature-Based Organization
Code is organized by feature (Auth, Onboarding, Home) rather than by type (Views, Models, Controllers). This keeps related code together and makes features self-contained.

### 2. SwiftData for Local Storage
SwiftData (iOS 17+) provides:
- Automatic persistence
- Swift-native syntax with `@Model` macro
- Integration with SwiftUI via `@Query`

### 3. XcodeGen for Project Configuration
The Xcode project is generated from `project.yml`. Benefits:
- Human-readable, diffable project configuration
- No merge conflicts on `.xcodeproj` files
- Easy to modify build settings

### 4. Strict Concurrency (Swift 6)
Enabled to catch thread-safety issues at compile time. All async code must be properly annotated with `@MainActor` or `Sendable`.

### 5. Environment-Based Configuration
Sensitive values (API keys, Supabase URL) are stored in environment variables, not in code. Use `.env` files locally and configure in deployment platform.

### 6. Layered Backend Architecture
The backend follows a clean separation of concerns:
- **API layer** (`app/api/`) — HTTP request/response handling, input validation via Pydantic
- **Service layer** (`app/services/`) — Business logic, orchestration, external API calls
- **Data layer** (`app/db/`) — Database queries, repository pattern
- **Agent layer** (`app/agents/`) — LangGraph pipeline for AI recommendation generation

Each layer only depends on the layer below it. Route handlers never call the database directly.

### 7. Python Virtual Environment
The backend uses a local `venv/` (gitignored) with Python 3.13. This avoids polluting the system Python and ensures reproducible builds. Activate with `source backend/venv/bin/activate`.

### 8. Dependency Management Strategy
All dependencies are declared in `requirements.txt` without pinned versions to allow flexibility during early development. Key dependency groups:
- **Web:** FastAPI + Uvicorn (ASGI server with hot reload)
- **AI:** LangGraph (graph-based orchestration) + Google Cloud AI Platform (Gemini 1.5 Pro via Vertex AI) + Pydantic AI (structured AI output validation)
- **Database:** Supabase client (PostgreSQL via PostgREST) + pgvector (vector type encoding for embeddings)
- **HTTP:** httpx (async client for external API integrations)
- **Testing:** pytest + pytest-asyncio

Note: `pgvector` is used via its base `Vector` type, not the SQLAlchemy integration, since database access goes through the Supabase client (PostgREST). The SQLAlchemy backend is not installed.

### 9. Dual Supabase Client Pattern
The backend maintains two Supabase clients, both lazy-initialized (created on first use, not at import time):
- **Anon client** (`get_supabase_client()`) — Uses the `anon` (public) key. Respects Row Level Security (RLS). Used for all user-facing operations where the user's JWT enforces access controls.
- **Service client** (`get_service_client()`) — Uses the `service_role` key. **Bypasses RLS entirely.** Only used for admin operations: background jobs, notification processing, migrations, and cross-user queries.

This pattern ensures user data isolation by default while allowing privileged operations when explicitly needed.

### 10. SQL Migrations Strategy
Database schema changes are stored as numbered SQL files in `backend/supabase/migrations/` (e.g., `00001_enable_pgvector.sql`). These can be run manually via the Supabase SQL Editor or via the Supabase CLI (`supabase db push`). Migrations are sequential and should never be modified after being applied — always create a new migration file for changes.

### 11. Test Configuration (`pyproject.toml`)
Pytest is configured with:
- `asyncio_mode = "auto"` — async test functions are detected and run automatically without `@pytest.mark.asyncio`
- `filterwarnings` — suppresses known deprecation warnings from `pyiceberg` (a transitive dependency of `supabase`). Only third-party warnings are suppressed; warnings from our code still surface.

### 12. Test Organization
Tests are organized by scope in `backend/tests/`:
- `test_imports.py` — Smoke tests verifying all dependencies are importable (Step 0.5)
- `test_supabase_connection.py` — Integration tests verifying Supabase connectivity and pgvector (Step 0.6). Uses `@pytest.mark.skipif` to gracefully skip connection tests when credentials aren't configured, while pure library tests (pgvector) always run.
- `test_supabase_auth.py` — Integration tests verifying Supabase Auth service reachability and Apple Sign-In provider configuration (Step 0.7). Checks GoTrue settings/health endpoints and confirms Apple is enabled for native iOS auth.
- `test_users_table.py` — Integration tests verifying the `public.users` table schema, RLS enforcement, and trigger behavior (Step 1.1). Tests create real auth users via the Supabase Admin API, verify the `handle_new_user` trigger auto-creates profile rows, confirm RLS blocks anonymous access, and validate CASCADE delete behavior. Each test uses a `test_auth_user` fixture that creates and cleans up auth users automatically.
- `test_partner_vaults_table.py` — Integration tests verifying the `public.partner_vaults` table schema, constraints, RLS enforcement, and trigger/CASCADE behavior (Step 1.2). 15 tests across 4 classes: table existence, schema verification (columns, NOT NULL, CHECK constraint, UNIQUE, defaults), RLS (anon blocked, service bypasses, user isolation), and triggers/cascades (updated_at auto-updates, cascade delete through auth→users→vaults, FK enforcement). Introduces `test_auth_user_pair` fixture for two-user isolation tests and `test_vault` fixture for vault-dependent tests.
- `test_partner_interests_table.py` — Integration tests verifying the `public.partner_interests` table schema, CHECK constraints (interest_type + interest_category), UNIQUE constraint (prevents duplicates and like+dislike conflicts), RLS enforcement via subquery, data integrity (5 likes + 5 dislikes), and CASCADE behavior (Step 1.3). 22 tests across 5 classes: table existence, schema (columns, CHECK constraints, UNIQUE, NOT NULL), RLS (anon blocked, service bypasses, user isolation), data integrity (insert/retrieve 5+5, no overlap, predefined list), and cascades (vault deletion, full auth chain, FK enforcement). Introduces `test_vault_with_interests` fixture (vault pre-populated with 5 likes + 5 dislikes) and `_insert_interest_raw` helper for testing failure responses.
- `test_partner_milestones_table.py` — Integration tests verifying the `public.partner_milestones` table schema, CHECK constraints (milestone_type + recurrence + budget_tier), budget tier auto-default trigger, RLS enforcement via subquery, data integrity (multiple milestones per vault, field verification), and CASCADE behavior (Step 1.4). 28 tests across 6 classes: table existence, schema (columns, 3 CHECK constraints, NOT NULL, date storage), budget tier defaults (birthday/anniversary auto-major, holiday auto-minor, holiday override, custom user-provided, custom without tier rejected), RLS (anon blocked, service bypasses, user isolation), data integrity (multiple milestones, field verification, duplicate types allowed), and cascades (vault deletion, full auth chain, FK enforcement). Introduces `test_vault_with_milestones` fixture (vault pre-populated with 4 milestones: birthday, anniversary, Valentine's Day, custom) and `_insert_milestone_raw` helper for testing failure responses.
- `test_partner_vibes_table.py` — Integration tests verifying the `public.partner_vibes` table schema, CHECK constraint (vibe_tag for 8 values), UNIQUE constraint (prevents duplicate vibes per vault), RLS enforcement via subquery, data integrity (multiple vibes, single vibe, max 4 vibes), and CASCADE behavior (Step 1.5). 19 tests across 5 classes: table existence, schema (columns, CHECK constraint, NOT NULL, UNIQUE prevents duplicates, same vibe allowed across vaults), RLS (anon blocked, service bypasses, user isolation), data integrity (multiple vibes, field values, max 4, single vibe), and cascades (vault deletion, full auth chain, FK enforcement). Introduces `test_vault_with_vibes` fixture (vault pre-populated with 3 vibes: quiet_luxury, minimalist, romantic) and `_insert_vibe_raw` helper for testing failure responses.
- `test_partner_budgets_table.py` — Integration tests verifying the `public.partner_budgets` table schema, CHECK constraints (occasion_type for 3 values, max_amount >= min_amount, min_amount >= 0), UNIQUE constraint (prevents duplicate occasion types per vault), RLS enforcement via subquery, data integrity (all 3 tiers stored, amounts correct in cents, currency defaults, integer storage, zero min allowed), and CASCADE behavior (Step 1.6). 27 tests across 5 classes: table existence, schema (columns, 3 CHECK constraints, NOT NULL for all required fields, UNIQUE prevents duplicate occasion types, same type allowed across vaults, currency default/override), RLS (anon blocked, service bypasses, user isolation), data integrity (3 tiers stored and verified, amounts in cents, field values, zero min), and cascades (vault deletion, full auth chain, FK enforcement). Introduces `test_vault_with_budgets` fixture (vault pre-populated with 3 budget tiers: just_because $20-$50, minor_occasion $50-$150, major_milestone $100-$500) and `_insert_budget_raw` helper for testing failure responses.
- `test_partner_love_languages_table.py` — Integration tests verifying the `public.partner_love_languages` table schema, CHECK constraints (language for 5 values, priority for 1/2 only), dual UNIQUE constraints (vault_id+priority prevents duplicate priorities, vault_id+language prevents same language at both priorities), RLS enforcement via subquery, data integrity (primary/secondary stored, field values, update primary succeeds, update to conflicting language fails), and CASCADE behavior (Step 1.7). 28 tests across 5 classes: table existence, schema (columns, 2 CHECK constraints, NOT NULL, 2 UNIQUE constraints, third language rejection, same language across vaults allowed, priority 0 rejected), RLS (anon blocked, service bypasses, user isolation), data integrity (primary+secondary stored, field values, primary correct, secondary correct, update primary succeeds, update to same-as-secondary fails), and cascades (vault deletion, full auth chain, FK enforcement). Introduces `test_vault_with_love_languages` fixture (vault pre-populated with primary=quality_time, secondary=receiving_gifts), `_insert_love_language_raw` helper for testing failure responses, and `_update_love_language` helper for testing update semantics.
- `test_hints_table.py` — Integration tests verifying the `public.hints` table schema, CHECK constraint (source for 2 values), vector(768) embedding column (nullable, accepts 768-dim vectors), HNSW index, `match_hints()` RPC function for cosine similarity search, RLS enforcement via subquery, data integrity (multiple hints, mixed sources, is_used default and update, with/without embeddings), vector similarity search (ordering verification with crafted vectors, threshold filtering, match_count limiting, vault scoping, NULL embedding skipping), and CASCADE behavior (Step 1.8). 30 tests across 6 classes: table existence, schema (columns, CHECK constraint, NOT NULL, is_used default, embedding nullable, embedding accepts 768-dim), RLS (anon blocked, service bypasses, user isolation), data integrity (multiple hints, field values, mixed sources, is_used update, with/without embedding), vector search (returns results, ordered by similarity, threshold filters, match_count limits, scoped to vault, skips NULL embeddings), and cascades (vault deletion, full auth chain, FK enforcement). Introduces `test_vault_with_hints` fixture (vault with 3 hints without embeddings), `test_vault_with_embedded_hints` fixture (vault with 3 hints with crafted 768-dim vectors for similarity testing), `_insert_hint_raw` helper for testing failure responses, and `_make_vector` helper for creating padded 768-dim vector strings.
- `test_recommendations_table.py` — Integration tests verifying the `public.recommendations` table schema, CHECK constraints (recommendation_type for 3 values, price_cents >= 0), nullable columns (milestone_id, description, external_url, price_cents, merchant_name, image_url), milestone FK SET NULL behavior, RLS enforcement via subquery, data integrity (3 recommendations per vault/"Choice of Three", all fields populated, all 3 types stored, with/without milestone, prices in cents, external URLs, merchant names), milestone FK behavior (SET NULL on milestone delete preserves recommendation history, FK enforcement rejects invalid milestone_id), and CASCADE behavior (Step 1.9). 31 tests across 6 classes: table existence, schema (columns, CHECK constraints, NOT NULL for title/type, nullable for description/url/price/merchant/image/milestone_id, price accepts zero, price rejects negative), RLS (anon blocked, service bypasses, user isolation), data integrity (3 recs stored, all fields verified, types stored, milestone linked, without milestone, prices in cents, URLs, merchants), milestone FK (SET NULL on delete, FK enforcement), and cascades (vault deletion, full auth chain, FK enforcement). Introduces `test_vault_with_milestone` fixture (vault with birthday milestone), `test_vault_with_recommendations` fixture (vault with 3 recommendations: gift/experience/date linked to milestone), `_insert_recommendation_raw` helper for testing failure responses, and sample recommendation constants (`SAMPLE_GIFT_REC`, `SAMPLE_EXPERIENCE_REC`, `SAMPLE_DATE_REC`).

### 13. Native iOS Auth Strategy
Knot uses **native Sign in with Apple** rather than the web OAuth redirect flow. This means:
- The iOS app presents `SignInWithAppleButton` (AuthenticationServices framework)
- Apple returns an identity token directly to the app
- The app sends this token to Supabase via `signInWithIdToken(provider: .apple, idToken: token)`
- Supabase validates the token with Apple and creates/returns a user session

This approach does NOT require an OAuth Secret Key or Callback URL in the Supabase dashboard. Those are only needed for web-based Sign in with Apple. The Client ID in Supabase must match the iOS app's bundle identifier (`com.ronniejay.knot`).

### 14. Supabase Swift SDK (iOS)
The iOS project depends on three products from `supabase-swift` (v2.41.0):
- **Auth** — Authentication client (sign in, sign out, session management, token refresh)
- **PostgREST** — Type-safe database query builder for Supabase tables
- **Supabase** — Umbrella module that bundles all Supabase services

These are declared in `iOS/project.yml` under `packages` and `dependencies`, and resolved via SPM.

### 15. Reusable vs Table-Specific Trigger Functions
Database trigger functions fall into two categories:

**Reusable (shared across tables):**
- **`handle_updated_at()`** — Generic `BEFORE UPDATE` trigger that sets `NEW.updated_at = now()`. Any table with an `updated_at` column can attach this trigger. Created in migration `00002` and reused by `partner_vaults`, `hints`, etc.
- **`handle_new_user()`** — `AFTER INSERT` trigger on `auth.users` that auto-creates a `public.users` row. Uses `SECURITY DEFINER` to bypass RLS (runs as the function creator, not the calling user).

**Table-specific (logic tied to one table):**
- **`handle_milestone_budget_tier()`** — `BEFORE INSERT` trigger on `partner_milestones` that auto-sets `budget_tier` based on `milestone_type` when the caller does not provide one. Uses a `CASE` statement: birthday/anniversary → `major_milestone`, holiday → `minor_occasion`, custom → no default (NOT NULL rejects). Only fires when `budget_tier IS NULL` — explicit values are never overridden. This allows the app layer to send `major_milestone` for major holidays (Valentine's/Christmas) while the database provides safe defaults for simpler inserts.

### 16. RLS + GRANT Layered Defense
Tables use a two-layer access control strategy:
- **GRANT** — Controls which PostgreSQL roles can perform which operations on the table (e.g., `authenticated` gets SELECT/INSERT/UPDATE, `anon` gets SELECT only)
- **RLS Policies** — Controls which rows each user can see/modify (e.g., `auth.uid() = id` ensures users only access their own data)

Both layers must pass for a query to succeed. The `anon` role has SELECT GRANT but RLS returns empty results (since `auth.uid()` is NULL for anonymous requests). The `service_role` key bypasses RLS entirely.

### 17. Database Test Pattern with Auth Users
Tests that need database rows in RLS-protected tables use the Supabase Admin API (`/auth/v1/admin/users`) to create real auth users. The `test_auth_user` pytest fixture:
1. Creates an auth user with a unique email via the Admin API
2. Waits for the `handle_new_user` trigger to auto-create the `public.users` row
3. Yields the user info (id, email) to the test
4. Cleans up by deleting the auth user (CASCADE removes the `public.users` row)

This pattern will be reused for all future table tests that depend on RLS.

### 18. Partner Vault as Central Data Hub
The `partner_vaults` table is the central entity that all partner-related data hangs off of. Future tables (`partner_interests`, `partner_milestones`, `partner_vibes`, `partner_budgets`, `partner_love_languages`, `hints`, `recommendations`) will all reference `partner_vaults.id` via foreign keys with CASCADE delete. This means deleting a vault cleans up all child data automatically. The CASCADE chain is three levels deep: `auth.users` → `public.users` → `partner_vaults` → (child tables).

### 19. Auto-Generated vs Mirrored Primary Keys
Two patterns are used for primary keys:
- **Mirrored:** `public.users.id` directly mirrors `auth.users.id` (same UUID). This makes it easy to join auth data with profile data.
- **Auto-generated:** `partner_vaults.id` uses `gen_random_uuid()` to create its own identity. The `user_id` column is the FK link. This is used for child entities where the primary key doesn't need to match any external system.

Future tables (interests, milestones, vibes, etc.) will follow the auto-generated pattern with FK references to their parent.

### 20. CHECK Constraints vs Application-Layer Validation
PostgreSQL CHECK constraints are used for simple enum validation (e.g., `cohabitation_status IN ('living_together', 'separate', 'long_distance')`). This provides database-level enforcement that can't be bypassed, even by service-role queries. For complex validation (e.g., "exactly 5 interests per vault"), enforcement will be at the application/API layer (Pydantic models in FastAPI) since PostgreSQL CHECK constraints can't span multiple rows.

### 21. Test Fixture Composition Pattern
Test files use composable pytest fixtures that build on each other:
- `test_auth_user` → creates an auth user (trigger creates `public.users` row)
- `test_vault(test_auth_user)` → creates a vault for that user
- `test_vault_with_interests(test_vault)` → adds 5 likes + 5 dislikes to the vault
- `test_vault_with_milestones(test_vault)` → adds 4 milestones (birthday, anniversary, Valentine's Day, custom "First Date")

Each fixture yields data and relies on CASCADE deletes for automatic cleanup (deleting the auth user cascades through all child data). This avoids manual cleanup logic and ensures tests are isolated.

### 22. PostgREST Error Code Patterns
When testing constraint violations via the PostgREST API:
- **HTTP 400** — NOT NULL violations, CHECK constraint violations
- **HTTP 409** — UNIQUE constraint violations, foreign key violations
- **HTTP 200 with empty array** — RLS blocking (query succeeds but returns no rows)

Tests check for these specific codes to verify the correct constraint is being enforced.

### 23. Supabase SQL Editor Transaction Behavior
The Supabase SQL Editor runs multi-statement SQL as a **single transaction**. If any statement fails (e.g., a typo in a role name), the entire batch is rolled back — including earlier statements that appeared to succeed. When running migrations manually, run in smaller batches to isolate failures. Numbered migration files should be run in order, one at a time.

### 24. RLS Subquery Pattern for Child Tables
Tables that don't have a direct `user_id` column (like `partner_interests`, which only has `vault_id`) use a **subquery pattern** for RLS policies:
```sql
CREATE POLICY "interests_select_own"
    ON public.partner_interests FOR SELECT
    USING (EXISTS (
        SELECT 1 FROM public.partner_vaults
        WHERE partner_vaults.id = partner_interests.vault_id
        AND partner_vaults.user_id = auth.uid()
    ));
```
This checks ownership by joining through the parent table (`partner_vaults`) to find the `user_id`. All future child tables hanging off `partner_vaults` (milestones, vibes, budgets, love languages, hints) will use this same pattern. The subquery is efficient because PostgreSQL optimizes `EXISTS` with a semi-join.

### 25. UNIQUE Composite Constraint for Mutual Exclusion
The `UNIQUE(vault_id, interest_category)` constraint on `partner_interests` serves a dual purpose:
1. **Prevents duplicates** — The same category cannot appear twice for a vault (even with the same `interest_type`)
2. **Enforces mutual exclusion** — A category cannot be both a "like" and a "dislike" for the same vault, since the UNIQUE constraint is on `(vault_id, interest_category)` regardless of `interest_type`

This is more efficient than using a database trigger or complex CHECK constraint, and provides atomic enforcement at the database level. The trade-off is that changing an interest from "like" to "dislike" requires deleting the old row and inserting a new one (rather than updating `interest_type` in place), since the UNIQUE constraint prevents having both simultaneously.

### 26. Database-Level vs Application-Level Validation Split
Step 1.3 establishes the pattern for splitting validation between database and application layers:
- **Database-level** (CHECK, UNIQUE, FK): `interest_type` enum, `interest_category` enum, no duplicate categories per vault, referential integrity
- **Application-level** (Pydantic in FastAPI): "Exactly 5 likes and 5 dislikes per vault" — this requires counting rows across the table, which PostgreSQL CHECK constraints cannot do (they only operate on single rows)

This split will be consistent for future tables. Simple per-row enum/value constraints go in the database. Cross-row cardinality rules go in the API layer.

### 27. Trigger-Based Defaults for Context-Dependent Values
The `partner_milestones` table introduces a new pattern: using a `BEFORE INSERT` trigger to set column defaults that depend on the value of another column in the same row. PostgreSQL's `DEFAULT` clause only supports constant expressions, so it cannot express "if milestone_type is 'birthday', default budget_tier to 'major_milestone'." The `handle_milestone_budget_tier()` trigger solves this by inspecting `NEW.milestone_type` and setting `NEW.budget_tier` when it's NULL. The trigger is designed to be non-destructive — it only modifies NULL values, never overrides explicit ones. This allows the application layer to send explicit values (e.g., `major_milestone` for Valentine's Day holidays) while the database provides safe defaults for simpler inserts (e.g., birthday auto-gets `major_milestone`).

### 28. Year-2000 Placeholder for Yearly Recurring Dates
Milestones with `recurrence = 'yearly'` store their date using year 2000 as a placeholder (e.g., `2000-03-15` for March 15 birthdays). This convention:
- Uses a real `DATE` type (not separate month/day columns), enabling standard date operations
- Avoids ambiguity about which year is "current" at the database level
- Keeps the application logic for "next occurrence" simple: replace year 2000 with the current (or next) year, then check if the date has passed this year
- Was chosen over alternatives like storing month/day separately (harder to query) or storing the actual birth year (privacy concern, and irrelevant for notification scheduling)

One-time milestones (e.g., a specific trip or event) store the actual date with the real year.

### 29. No UNIQUE Constraint on Milestones (Unlike Interests)
The `partner_milestones` table deliberately has NO unique constraint on `(vault_id, milestone_type)` or `(vault_id, milestone_name)`. This is different from `partner_interests`, which uses `UNIQUE(vault_id, interest_category)` to prevent duplicates. The reasoning:
- A vault needs multiple holidays (Christmas, Valentine's Day, New Year's Eve — all type `holiday`)
- A vault might have multiple custom milestones (First Date, Engagement Party — all type `custom`)
- Even milestone names could theoretically repeat (unlikely but not worth constraining)

The only constraint is the FK to `partner_vaults` — every milestone must belong to a valid vault.

### 30. Budget Tier Strategy: Database Defaults + Application Overrides
The budget tier for milestones uses a two-layer strategy:
1. **Database trigger** provides safe defaults: birthday/anniversary → `major_milestone`, holiday → `minor_occasion`
2. **Application layer** overrides for specific cases: Valentine's Day and Christmas holidays get `major_milestone` (the app explicitly sends this value)
3. **User choice** for custom milestones: the app must collect a budget tier during custom milestone creation

This avoids encoding holiday-name-specific logic in the database (which would be brittle and hard to maintain) while still providing sensible defaults that reduce the burden on the API layer for common cases.

### 31. Vibes Table as the Simplest Child Table Pattern
The `partner_vibes` table is the simplest child table in the schema — it serves as a clean reference implementation for the "tag storage" pattern. Unlike `partner_interests` (which has dual-purpose UNIQUE for deduplication + mutual exclusion) and `partner_milestones` (which has a trigger for computed defaults), vibes are a pure many-to-one tag table: each row is just a vault_id + vibe_tag pair with a CHECK constraint. The `UNIQUE(vault_id, vibe_tag)` constraint exists solely for deduplication (no dual-purpose like interests). This pattern will be reused for any future simple tag/enum association tables.

### 32. Consistent Child Table Schema Pattern
By Step 1.5, a clear pattern has emerged for child tables hanging off `partner_vaults`:
- **Primary key:** `id UUID PRIMARY KEY DEFAULT gen_random_uuid()`
- **Parent FK:** `vault_id UUID NOT NULL REFERENCES public.partner_vaults(id) ON DELETE CASCADE`
- **Timestamp:** `created_at TIMESTAMPTZ NOT NULL DEFAULT now()`
- **RLS:** 4 policies (SELECT, INSERT, UPDATE, DELETE) using the subquery pattern to check `auth.uid()` through `partner_vaults.user_id`
- **GRANTs:** Full CRUD for `authenticated`, read-only for `anon`
- **Index:** Single-column index on `vault_id` for fast lookups
- **Cardinality rules:** Enforced at the API layer, not the database (e.g., "1-4 vibes", "exactly 5 likes")

Future child tables (`partner_love_languages`, `hints`, `recommendations`) should follow this same pattern unless they have a specific reason to deviate.

### 33. Monetary Amounts in Cents (Integer Pattern)
The `partner_budgets` table stores monetary amounts as **integers representing cents** (e.g., `2000` = $20.00, `15000` = $150.00). This is a standard financial data pattern that avoids floating-point precision issues (e.g., `0.1 + 0.2 ≠ 0.3` in IEEE 754). Key implications:
- **Database:** `min_amount` and `max_amount` are `INTEGER NOT NULL` — no `NUMERIC` or `DECIMAL` type needed for cents
- **API layer:** Pydantic models accept/return integers in cents
- **iOS UI:** Must convert between cents (API) and dollars (display): `amount_cents / 100` for display, `dollars * 100` for submission
- **Cross-column CHECK:** `CHECK (max_amount >= min_amount)` validates the range at the database level — this is a PostgreSQL feature that operates on multiple columns within the same row (unlike cross-row validation which requires triggers or application logic)

### 34. UNIQUE Constraint for One-Per-Occasion Budget Pattern
The `UNIQUE(vault_id, occasion_type)` constraint on `partner_budgets` ensures each vault has **exactly one budget configuration per occasion type**. This is semantically different from the UNIQUE constraints on other child tables:
- `partner_interests`: `UNIQUE(vault_id, interest_category)` — deduplication + mutual exclusion (like/dislike)
- `partner_vibes`: `UNIQUE(vault_id, vibe_tag)` — pure deduplication
- `partner_budgets`: `UNIQUE(vault_id, occasion_type)` — enforces one-to-one mapping between vault and each occasion type
- `partner_love_languages`: `UNIQUE(vault_id, priority)` + `UNIQUE(vault_id, language)` — dual constraint for priority uniqueness + language mutual exclusion (see §35)

This means updating a budget tier requires an `UPDATE` on the existing row (not `DELETE` + `INSERT`). The API layer should use upsert semantics when the user adjusts their budget sliders.

### 35. Dual UNIQUE Constraint Strategy for Love Languages
The `partner_love_languages` table introduces a new pattern: using **two UNIQUE constraints** together to enforce both priority uniqueness and language mutual exclusion:
- `UNIQUE(vault_id, priority)` — ensures at most one primary (1) and one secondary (2) per vault
- `UNIQUE(vault_id, language)` — ensures the same language cannot appear at both priorities for a vault

Combined with `CHECK(priority IN (1, 2))`, these constraints create a hard maximum of 2 rows per vault. A third insert is impossible because:
1. Priority 1 is taken → `UNIQUE(vault_id, priority)` blocks another priority=1
2. Priority 2 is taken → `UNIQUE(vault_id, priority)` blocks another priority=2
3. Priority 3+ → `CHECK(priority IN (1, 2))` blocks it

This is more restrictive than other child tables:
- `partner_interests`: single UNIQUE, unlimited rows within constraint
- `partner_vibes`: single UNIQUE, up to 8 rows (one per valid vibe)
- `partner_budgets`: single UNIQUE, up to 3 rows (one per occasion type)
- `partner_love_languages`: dual UNIQUE + CHECK, **exactly 0-2 rows** (hard database limit)

Updating a love language (e.g., changing primary from `quality_time` to `physical_touch`) works via a standard PATCH. However, swapping primary and secondary requires a multi-step process (delete one, update the other, re-insert) because the UNIQUE constraints prevent intermediate states where both rows have the same language or priority. The API layer should handle swap operations as a transaction.

### 36. Currency as Flexible Text Column
The `currency` column on `partner_budgets` uses `TEXT NOT NULL DEFAULT 'USD'` rather than a CHECK constraint with a fixed list of ISO 4217 codes. This design choice:
- **Supports international users** without database migrations when adding new currencies
- **Delegates validation** to the API layer (Pydantic model can validate against a known list of ISO 4217 codes)
- **Avoids maintenance burden** of updating a CHECK constraint every time a new currency is needed
- **Mirrors the pattern** used by external APIs (Yelp, Ticketmaster) which return currency codes as strings

### 37. pgvector Column Strategy: Nullable Embeddings
The `hint_embedding` column on `hints` is `vector(768)` with **no NOT NULL constraint** (nullable). This deliberate design choice provides resilience:
- The normal flow (Step 4.4) generates the embedding synchronously via Vertex AI `text-embedding-004` before storing the hint
- If the Vertex AI API is temporarily unavailable, the hint text can still be stored immediately and the embedding backfilled later via a background job
- The `match_hints()` RPC function includes `WHERE h.hint_embedding IS NOT NULL` to exclude unembedded hints from similarity search, ensuring partial data doesn't corrupt search results
- This pattern of "store first, enrich later" is common in systems that depend on external ML APIs for data augmentation

### 38. HNSW vs IVFFlat Index Choice
The `hints` table uses an **HNSW (Hierarchical Navigable Small World)** index instead of IVFFlat for the vector similarity search. Key differences:
- **HNSW:** No pre-build step required (works on empty tables), better recall (accuracy) at the cost of slightly more memory, incrementally updated as data is inserted
- **IVFFlat:** Requires data in the table before building the index (`CREATE INDEX` should happen after initial data load), faster index creation for large batches, slightly less accurate
- For Knot's use case (hints trickle in one-at-a-time via user input), HNSW is the clear winner because it handles incremental inserts naturally
- The `vector_cosine_ops` operator class was chosen because cosine similarity is standard for text embeddings (it measures directional similarity regardless of vector magnitude)

### 39. RPC Functions for pgvector Operations
PostgREST (Supabase's REST API layer) does not natively support pgvector operators like `<=>` (cosine distance), `<->` (L2 distance), or `<#>` (inner product). To perform similarity search via the API, a **PostgreSQL function** must be created and called via the `/rest/v1/rpc/{function_name}` endpoint. The `match_hints()` function:
- Accepts a query vector, vault_id, similarity threshold, and result count
- Uses `1 - (hint_embedding <=> query_embedding)` to compute cosine similarity (the `<=>` operator returns cosine *distance*, which is `1 - similarity`)
- Orders by `hint_embedding <=> query_embedding` ASC (smallest distance = most similar)
- Filters by `hint_embedding IS NOT NULL` (skips unembedded hints) and `similarity >= match_threshold`
- Returns a `similarity` column (1.0 = identical direction, 0.0 = orthogonal)
- Uses `SECURITY INVOKER` (default) — when called by the service client, RLS is bypassed; when called by an authenticated user, RLS ensures they only see their own vault's hints

This RPC pattern will be reused by the LangGraph hint retrieval node (Step 5.2) when performing semantic search to find relevant hints for recommendation generation.

### 40. Hints as an Unbounded Collection
Unlike other child tables that have explicit cardinality limits (5 likes, 5 dislikes, 1-4 vibes, 3 budget tiers, 2 love languages), the `hints` table has **no UNIQUE constraints and no cardinality limits** at the database level. A vault can accumulate unlimited hints over time. This is intentional:
- Hints are the primary input for the "Second Brain" feature — the more hints captured, the better the recommendation quality
- Duplicate hint text is allowed (the user might re-mention something, which is a signal of importance)
- The `is_used` boolean tracks which hints have been incorporated into recommendations, enabling the system to prioritize fresh/unused hints
- Cleanup of old/stale hints can be implemented as a background job in the future

### 41. ON DELETE SET NULL for Recommendation-Milestone Relationship
The `recommendations` table introduces a **new FK delete behavior**: `ON DELETE SET NULL` for `milestone_id`. All previous FK relationships in the schema use `ON DELETE CASCADE`. The reasoning:
- Recommendations are **historical records** — they represent suggestions the AI generated and potentially the user acted on (selected, saved, shared). Deleting a milestone (e.g., removing an anniversary) should not erase the gift recommendations that were generated for it.
- When a milestone is deleted, `milestone_id` becomes NULL, effectively making the recommendation a "just because" historical entry. All other fields (title, price, merchant, URL) remain intact.
- The `vault_id` FK still uses CASCADE because deleting a vault means the user is removing all partner data — recommendations have no meaning without the vault.
- Future tables that reference `recommendations` (like `recommendation_feedback` in Step 1.10) will use CASCADE, since feedback is meaningless without the recommendation it refers to.

This creates a **mixed FK strategy** in the schema:
| Parent Table | Child Table | Delete Behavior | Reason |
|-------------|-------------|----------------|--------|
| `partner_vaults` | `recommendations` | CASCADE | Vault deletion = remove all partner data |
| `partner_milestones` | `recommendations` | SET NULL | Milestone deletion should preserve history |

### 42. Dual Index Pattern for Multi-Access Queries
The `recommendations` table is the **first child table with two indexes** (beyond the primary key):
- `idx_recommendations_vault_id` — for queries like "get all recommendations for this vault" (the standard child-table index)
- `idx_recommendations_milestone_id` — for queries like "get recommendations generated for this specific milestone"

Previous child tables only needed a single `vault_id` index because they were only queried via their parent vault. Recommendations have a second access pattern: when a milestone notification fires (Step 7.3), the system needs to check if recommendations already exist for that milestone. The milestone index enables this lookup without a full table scan.

### 43. Nullable Columns for External API Resilience
The `recommendations` table makes `description`, `external_url`, `price_cents`, `merchant_name`, and `image_url` all nullable, unlike `title` and `recommendation_type` which are NOT NULL. This is a deliberate design for **external API resilience**:
- External APIs (Yelp, Ticketmaster, Amazon, Shopify) may return partial data — a restaurant might have a name and URL but no image, or an event might not have a fixed price
- The LangGraph pipeline (Steps 5.1–5.8) aggregates data from multiple sources, and not all sources provide every field
- Making these columns nullable allows the pipeline to store partial recommendations rather than failing entirely when one field is missing
- The iOS UI (Step 6.1) should handle NULL fields gracefully — showing placeholder images, "Price unavailable" text, etc.

This differs from `partner_budgets` where `min_amount` and `max_amount` are NOT NULL because those are user-provided values that must always be present.

### 44. Recommendations as an Unbounded Append-Only Collection
Like `hints`, the `recommendations` table has **no UNIQUE constraints and no cardinality limits**. Recommendations are generated in batches of 3 (the "Choice of Three") and simply appended to the table. Key implications:
- Multiple batches of 3 can exist for the same vault and milestone (e.g., initial batch + refreshed batch)
- The same recommendation could theoretically be regenerated (e.g., if the user refreshes and the API returns the same item)
- Historical recommendations are never deleted by the system — only by vault CASCADE or explicit user action
- The `recommendation_feedback` table (Step 1.10) will link to specific recommendation IDs to track which ones were selected, refreshed, saved, or shared

---

## Data Flow

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│   SwiftUI   │────▶│  Services   │────▶│  Supabase   │
│    Views    │◀────│   Layer     │◀────│  Backend    │
└─────────────┘     └─────────────┘     └─────────────┘
       │                   │
       ▼                   ▼
┌─────────────┐     ┌─────────────┐
│  SwiftData  │     │   FastAPI   │
│   (Local)   │     │   Backend   │
└─────────────┘     └─────────────┘
```

1. **Views** call **Services** for data operations
2. **Services** communicate with **Supabase** (auth, database) and **FastAPI** (recommendations)
3. **SwiftData** provides offline-capable local storage
4. **FastAPI** orchestrates LangGraph pipeline and external APIs
