# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Required Reading Before Writing Code
- Always read `memory-bank/architecture.md` before writing any code — includes the full database schema.
- Always read `memory-bank/PRD.md` before writing any code.
- After adding a major feature or completing a milestone, update `memory-bank/architecture.md`.

## Project Overview

Knot is an AI-powered relationship management app that helps partners capture preferences ("hints") and receive curated gift/experience recommendations. It consists of a **Python/FastAPI backend** and a **SwiftUI iOS client**, connected through **Supabase** (PostgreSQL + Auth).

## Architecture

### Backend (`backend/`)
- **Framework:** FastAPI with async handlers
- **AI Pipeline:** LangGraph 6-node recommendation pipeline (`app/agents/`) — hint retrieval → aggregation → filtering → matching → selection → verification
- **Embeddings:** Vertex AI `text-embedding-004` (768-dim) for semantic search via pgvector
- **Auth:** JWT validation against Supabase Auth in `app/core/security.py` using `Depends(get_current_user_id)`
- **DB Clients:** `app/db/supabase_client.py` provides `get_supabase_client()` (respects RLS) and `get_service_client()` (bypasses RLS for admin ops)
- **Routes:** `app/api/vault.py` (Partner Vault CRUD), `app/api/hints.py` (hint capture/deletion)
- **Models:** Pydantic schemas in `app/models/`
- **Entry point:** `app/main.py`

### iOS (`iOS/`)
- **Swift 6** with strict concurrency, **SwiftUI**, **SwiftData** for local persistence
- **XcodeGen:** Project generated from `iOS/project.yml` — do not edit `.xcodeproj` directly
- **Feature-based organization:** `Features/Auth/`, `Features/Onboarding/`, `Features/Home/`, `Features/Settings/`
- **MVVM pattern:** ViewModels are `@Observable @MainActor`, views use `@Environment` and `@Query`
- **SPM dependencies:** Supabase (Auth, PostgREST), LucideIcons
- **SwiftData models:** `PartnerVaultLocal`, `HintLocal`, `MilestoneLocal`, `RecommendationLocal`

### Documentation (`memory-bank/`)
Strategic docs: `PRD.md`, `architecture.md`, `techstack.md`, `IMPLEMENTATION_PLAN.md`, `progress.md`. The `architecture.md` file contains detailed per-file descriptions.

## Build & Run Commands

### Backend
```bash
# Setup
cd backend && python3 -m venv venv && source venv/bin/activate && pip install -r requirements.txt

# Run dev server
cd backend && source venv/bin/activate && uvicorn app.main:app --reload --host 0.0.0.0 --port 8000

# Run all tests
cd backend && pytest tests/ -v

# Run a single test file
cd backend && pytest tests/test_filtering_node.py -v

# Run a specific test function
cd backend && pytest tests/test_filtering_node.py::test_function_name -v
```

### iOS
```bash
# Generate Xcode project (required after changing project.yml)
cd iOS && xcodegen generate

# Build
xcodebuild build -scheme Knot -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -project iOS/Knot.xcodeproj

# Run tests
xcodebuild test -scheme Knot -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -project iOS/Knot.xcodeproj
```

## Key Patterns

- **Async-first backend:** All route handlers and DB calls are `async def`. Use `asyncio.to_thread()` for synchronous SDKs (e.g., Vertex AI).
- **Graceful degradation:** Vertex AI unavailable → hints saved with NULL embeddings. Embedding failure → returns `None`, doesn't block the request.
- **Backend test auth:** Tests create real Supabase auth users via admin API, require `.env` with Supabase credentials. Vertex AI tests use `unittest.mock.patch` with `AsyncMock`.
- **pytest config:** `asyncio_mode = "auto"` in `pyproject.toml` — no need for `@pytest.mark.asyncio`.
- **iOS constants:** `iOS/Knot/Core/Constants.swift` contains API base URL, Supabase config, 41 interest categories, 8 vibes, 5 love languages.

## Environment Variables

Backend requires a `.env` file (see `backend/.env.example`). Key vars:
- `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY` — required
- `GOOGLE_CLOUD_PROJECT`, `GOOGLE_APPLICATION_CREDENTIALS` — for Vertex AI embeddings
- API keys for external integrations: `YELP_API_KEY`, `TICKETMASTER_API_KEY`, `FIRECRAWL_API_KEY`
