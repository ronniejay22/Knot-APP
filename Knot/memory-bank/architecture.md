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
│       └── __init__.py
├── tests/                    # Backend test suite (pytest)
│   ├── __init__.py
│   └── test_imports.py       # Verifies all dependencies are importable (11 tests)
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
| `config.py` | Application settings constants (`API_V1_PREFIX`, `PROJECT_NAME`). Will be expanded with pydantic-settings to load and validate environment variables in Step 0.5. |
| `security.py` | Auth middleware placeholder. Will extract Bearer tokens from `Authorization` header, validate against Supabase Auth, and return the authenticated user ID. Raises `HTTPException(401)` if invalid. Implemented in Step 2.5. |

### Data Layer (`app/models/`, `app/db/`)

| Folder | Purpose |
|--------|---------|
| `models/` | Pydantic models for API request/response validation. Ensures strict schema adherence (e.g., exactly 5 interests, valid vibe tags). |
| `db/` | Repository classes for Supabase/PostgreSQL queries. Handles all database operations with proper RLS context. |

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

### 9. Test Configuration (`pyproject.toml`)
Pytest is configured with:
- `asyncio_mode = "auto"` — async test functions are detected and run automatically without `@pytest.mark.asyncio`
- `filterwarnings` — suppresses known deprecation warnings from `pyiceberg` (a transitive dependency of `supabase`). Only third-party warnings are suppressed; warnings from our code still surface.

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
