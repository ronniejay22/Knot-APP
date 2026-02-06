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
│       └── 00002_create_users_table.sql  # Users table with RLS, triggers, and grants
├── tests/                    # Backend test suite (pytest)
│   ├── __init__.py
│   ├── test_imports.py       # Verifies all dependencies are importable (11 tests)
│   ├── test_supabase_connection.py  # Verifies Supabase connectivity and pgvector (11 tests)
│   ├── test_supabase_auth.py # Verifies auth service and Apple Sign-In config (6 tests)
│   └── test_users_table.py   # Verifies users table schema, RLS, and triggers (10 tests)
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

### 15. Reusable Trigger Functions
Database trigger functions are designed for reuse across tables:
- **`handle_updated_at()`** — Generic `BEFORE UPDATE` trigger that sets `NEW.updated_at = now()`. Any table with an `updated_at` column can attach this trigger. Created in migration `00002` and will be reused by `partner_vaults`, `hints`, etc.
- **`handle_new_user()`** — `AFTER INSERT` trigger on `auth.users` that auto-creates a `public.users` row. Uses `SECURITY DEFINER` to bypass RLS (runs as the function creator, not the calling user).

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

### 18. Supabase SQL Editor Transaction Behavior
The Supabase SQL Editor runs multi-statement SQL as a **single transaction**. If any statement fails (e.g., a typo in a role name), the entire batch is rolled back — including earlier statements that appeared to succeed. When running migrations manually, run in smaller batches to isolate failures. Numbered migration files should be run in order, one at a time.

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
