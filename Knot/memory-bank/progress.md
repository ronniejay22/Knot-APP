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

## Next Steps

- [ ] **Step 0.6:** Set Up Supabase Project
- [ ] **Step 0.7:** Configure Supabase Auth with Apple Sign-In

---

## Notes for Future Developers

1. **Regenerating the Xcode project:** If you modify `project.yml`, run:
   ```bash
   cd iOS && xcodegen generate
   ```

2. **Bundle Identifier:** Changed from `com.knot.app` (taken) to `com.ronniejay.knot`

3. **Running on Simulator:** Select iPhone 17 Pro simulator (available: iPhone 17, 17 Pro, 17 Pro Max, iPhone Air on iOS 26.2). Avoid physical device to skip provisioning profile issues during development.

4. **XcodeGen required:** Install with `brew install xcodegen`
