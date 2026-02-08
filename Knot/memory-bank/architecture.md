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
| `Knot/Knot.entitlements` | App entitlements file. Currently contains `com.apple.developer.applesignin` for Sign in with Apple capability. Future entitlements (push notifications, associated domains for deep links) will be added here. Referenced by `CODE_SIGN_ENTITLEMENTS` in `project.yml`. |

### Source Code (`iOS/Knot/`)

#### `/App` — Application Entry Point
| File | Purpose |
|------|---------|
| `KnotApp.swift` | Main app entry point. Configures SwiftData ModelContainer and injects it into the app environment. |
| `ContentView.swift` | Root auth state router. Creates `AuthViewModel` as `@State`, injects it into the SwiftUI environment via `.environment()`, and starts the `authStateChanges` listener via `.task`. Routes between three states: loading spinner (`isCheckingSession`), `HomeView` (`isAuthenticated`), or `SignInView` (default). |

#### `/Features` — Feature Modules
Organized by feature, each containing Views, ViewModels, and feature-specific components.

| Folder | Status | Purpose |
|--------|--------|---------|
| `Auth/` | **Active** | Apple Sign-In flow, session management, auth state |
| `Home/` | **Placeholder** | Placeholder for session persistence verification (Step 2.3). Full build in Step 4.1. |
| `Onboarding/` | **Active** | Partner Vault creation (9-step wizard). Container + ViewModel at root, step views in `Steps/` subfolder. |
| `Recommendations/` | Planned | Choice-of-Three UI, refresh flow |
| `HintCapture/` | Planned | Text and voice hint input |
| `Settings/` | Planned | User preferences, account management |

##### `Auth/` — Authentication Feature
| File | Purpose |
|------|---------|
| `SignInView.swift` | Sign-in screen with Apple Sign-In button. Displays Knot branding (Lucide heart icon, title, tagline), three value proposition rows, and `SignInWithAppleButton` from `AuthenticationServices`. Delegates auth logic to `AuthViewModel` (shared via `@Environment`). Shows a loading overlay during Supabase sign-in. Contains a private `SignInFeatureRow` component for the value prop list. Uses `@Bindable` wrapper for alert binding. |
| `AuthViewModel.swift` | `@Observable @MainActor` class managing the full auth lifecycle. On launch, listens to `authStateChanges` to restore sessions from Keychain (`initialSession` event). Handles Apple Sign-In → Supabase Auth flow with OIDC nonce security. Provides `signOut()` (Step 2.4) which calls `supabase.auth.signOut()` to invalidate the server session, clear the Keychain, and emit `signedOut` through the listener. Exposes `isCheckingSession` (initial load), `isLoading` (sign-in in progress), `isAuthenticated` (drives root navigation), `signInError`, `showError`. All auth state transitions flow through `listenForAuthChanges()`. |

##### `Home/` — Home Feature (Placeholder)
| File | Purpose |
|------|---------|
| `HomeView.swift` | Placeholder Home screen created in Step 2.3 for session persistence verification, updated in Step 2.4 with sign-out functionality. Shows Knot branding, welcome message, session status indicator (Lucide `circleCheck` icon), and Sign Out button (red bordered with `logOut` icon) + toolbar icon. Reads `AuthViewModel` from environment and calls `signOut()` async. Will be replaced with the full Home screen (hint capture, milestone cards, network monitoring) in Step 4.1; sign-out moves to Settings in Step 11.1. |

##### `Onboarding/` — Partner Vault Onboarding Flow
| File | Purpose |
|------|---------|
| `OnboardingViewModel.swift` | `@Observable @MainActor` class managing all onboarding state. Also defines `CustomMilestone` struct (Identifiable, Sendable — name, month, day, recurrence) and `HolidayOption` struct (Identifiable, Sendable — id, displayName, month, day, iconName; static `allHolidays` with 5 US holidays). Contains `OnboardingStep` enum (9 cases: welcome through completion) with `title`, `isFirst`, `isLast`, `totalSteps`. Holds `currentStep`, `progress` (0.0–1.0), `canProceed` flag, `validationMessage` (computed, returns user-facing error string or nil), and all data properties for Steps 3.2–3.8 (partnerName, selectedInterests, selectedDislikes, selectedVibes, budget amounts, love languages, milestones incl. `customMilestones: [CustomMilestone]`). Provides `goToNextStep()`, `goToPreviousStep()` navigation methods, `daysInMonth()` / `clampDay()` static date helpers, and `validateCurrentStep()` centralized validation (switch on `currentStep` — `.basicInfo` checks name non-empty, `.interests` checks count == 5, `.dislikes` checks count == 5 AND `isDisjoint(with: selectedInterests)`, `.milestones` checks custom milestones have non-empty names, `.vibes` checks count >= 1, `.budget` checks max >= min for all three tiers, `.loveLanguages` checks both primary and secondary are non-empty, `default` returns `true` for placeholder steps). `validationMessage` mirrors the same switch with step-specific user-facing strings (e.g., "Pick at least 1 vibe to continue."). Navigation methods call `validateCurrentStep()` after every step change. Step views also call it via `.onAppear` / `.onChange` for real-time validation. Created by `OnboardingContainerView` and injected into environment — all step views share the same instance. |
| `OnboardingContainerView.swift` | Navigation shell for the 9-step onboarding flow. Owns `OnboardingViewModel` via `@State` and injects it into the SwiftUI environment. Displays: (1) animated progress bar at top with step title and "Step X of 9" counter, (2) current step view in center via `@ViewBuilder` switch, (3) validation error banner (red, slides up, auto-dismisses after 3s) when user taps Next on an invalid step, (4) Back/Next/Get Started buttons at bottom. All buttons use `.fixedSize(horizontal: true, vertical: false)` to prevent text wrapping, `.subheadline` font, height 44. Next button is always tappable — when `canProceed` is false, it shows the error banner from `viewModel.validationMessage` instead of advancing; tint dims to 40% opacity as a visual hint. Back button hidden on first step; "Get Started" replaces "Next" on last step. Error banner auto-clears on step change. Uses `.id(viewModel.currentStep)` for step identity and `.transition(.asymmetric(...))` for slide animations. Accepts `onComplete` closure called when user finishes onboarding. |

| Step View (in `Steps/`) | Step # | Purpose |
|--------------------------|--------|---------|
| `OnboardingWelcomeView.swift` | 1 | Welcome screen with Knot branding and checklist of vault sections (basics, interests, milestones, budget, love languages). Read-only informational step. |
| `OnboardingBasicInfoView.swift` | 2 | **Active (Step 3.2).** Partner basic info form with 4 sections: (1) Partner name `TextField` with `.givenName` content type, deferred "Required" validation hint via `@State hasInteractedWithName`, and `@FocusState` keyboard chaining (name → city → state → dismiss); (2) Relationship tenure — two `Picker(.menu)` controls for years (0–30) and months (0–11) using `Binding(get:set:)` to decompose/recompose `viewModel.relationshipTenureMonths`; (3) Cohabitation status `Picker(.segmented)` with contextual description text; (4) Location city/state `TextField`s with `.addressCity`/`.addressState` content types (optional). Calls `viewModel.validateCurrentStep()` on `.onAppear` and `.onChange(of: partnerName)`. Uses `@Bindable var vm = viewModel` in `body` for binding syntax, `Binding(get:set:)` in computed properties. `ScrollView` with `.scrollDismissesKeyboard(.interactively)`. |
| `OnboardingInterestsView.swift` | 3 | **Active (Step 3.3).** Dark-themed 3-column grid of visual interest cards with search bar. Each card (`InterestImageCard`, private struct) prefers an asset catalog image (`imageName(for:)` → `"Interests/interest-{slug}"` via `UIImage(named:)` nil check) rendered as a full-bleed `.resizable().aspectRatio(contentMode: .fill)` photo; falls back to a hue-rotated `LinearGradient` background with large semi-transparent SF Symbol icon when no image exists. Interest name at bottom-left with dark gradient overlay for text readability. Selected cards show a pink border + checkmark badge. Shake animation rejects 6th selection. Search bar filters 40 categories in real-time with clear button and empty-state message. Counter shows "X selected (Y more needed)" in pink. Uses `viewModel.selectedInterests` (Set<String>), `toggleInterest()` for add/remove logic, and `triggerShake()` with `DispatchQueue.main.asyncAfter` for animation. Static functions `cardGradient(for:)`, `iconName(for:)`, and `imageName(for:)` generate per-card visuals. `imageName(for:)` is also called by `OnboardingDislikesView` for consistent visuals. All colors use `Theme` constants. |
| `OnboardingDislikesView.swift` | 4 | **Active (Step 3.4).** Dark-themed 3-column card grid matching InterestsView visual style. Displays all 40 interest categories; interests already selected as likes in Step 3.3 appear grayed out with heart badge and `.disabled(true)`. User selects exactly 5 dislikes. Contains `DislikeImageCard` (private struct) with 4 visual states: unselected (photo or gradient), selected/disliked (pink border + checkmark), disabled/liked (flat gray `Color(white: 0.18)`, 50% opacity, heart badge — always gray regardless of image availability), shaking (6th attempt rejection). Prefers asset catalog images via `OnboardingInterestsView.imageName(for:)`, falls back to gradient + SF Symbol via `.cardGradient(for:)` and `.iconName(for:)`. Search bar, selection counter, and shake animation match the Interests screen. Calls `viewModel.validateCurrentStep()` via `.onAppear` and `.onChange(of: selectedDislikes)`. |
| `OnboardingMilestonesView.swift` | 5 | **Active (Step 3.5).** Full milestones input screen with 4 sections: (1) Birthday — required, month/day `Picker(.menu)` controls with `Binding(get:set:)` that auto-clamps day via `OnboardingViewModel.clampDay()` on month change, "Required" capsule badge, human-readable date below; (2) Anniversary — optional `Toggle` that reveals month/day pickers with `.opacity.combined(with: .move(edge: .top))` transition, wrapped in a `Theme.surface.opacity(0.5)` card; (3) Holiday Quick-Add — `VStack` of `HolidayChip` components (private struct) for 5 US holidays (Valentine's Day, Mother's Day, Father's Day, Christmas, New Year's Eve), each with SF Symbol icon, name, date, and `Lucide.circleCheck`/`circle` toggle indicator, selected state uses `Theme.accent.opacity(0.12)` background; (4) Custom Milestones — list of `CustomMilestone` entries with star icon, name, date, recurrence, X delete button, plus "Add Custom Milestone" dashed-border button that opens a `.sheet` with `NavigationStack` containing name `TextField`, month/day pickers, yearly/one-time segmented recurrence `Picker`, Cancel/Save toolbar. Reusable `monthPicker()` and `dayPicker()` private helpers used in both main view and sheet. Sheet uses `@State` local properties (not ViewModel) for temporary state, cleared via `resetCustomSheetState()`. 3 `#Preview` variants. |
| `OnboardingVibesView.swift` | 6 | **Active (Step 3.6).** Dark-themed 2-column grid of 8 visual vibe cards. Each card (`VibeCard`, private struct) has a hand-tuned `LinearGradient` background unique to its vibe aesthetic, a large semi-transparent Lucide icon watermark (offset upper-right), a small opaque Lucide icon above the name, the vibe display name (`.headline.weight(.bold)`), and a short description (`.caption`). Dark overlay gradient ensures text readability. Selected cards show pink border + checkmark badge + 1.02x scale. No maximum limit — all 8 vibes can be selected; minimum 1 required. Static functions `displayName(for:)`, `vibeDescription(for:)`, `vibeIcon(for:)`, and `vibeGradient(for:)` map `snake_case` vibe keys to display data. Lucide icons used: `gem`, `building2`, `trees`, `watch`, `penLine`, `sun`, `heart`, `compass`. Counter shows "X selected" with checkmark or "(pick at least 1)". Calls `viewModel.validateCurrentStep()` via `.onAppear` and `.onChange(of: selectedVibes)`. 3 `#Preview` variants. |
| `OnboardingBudgetView.swift` | 7 | **Active (Step 3.7).** Dark-themed budget tiers screen with 3 tier cards (Just Because, Minor Occasion, Major Milestone). Each card (`BudgetTierCard`, private struct) displays an accent-colored icon badge (`Lucide.coffee` / `Lucide.gift` / `Lucide.sparkles`), title/subtitle, a "Select all" link, and a 2-column `LazyVGrid` of multi-select preset range buttons (`BudgetRangeOption`, fileprivate struct). Users can select multiple ranges per tier — effective min/max is computed as `min(selected mins)` / `max(selected maxes)`. At least one range must stay selected. Each tier has 4 preset options (e.g., $5–$20, $20–$50, $50–$100, $100–$200 for Just Because). Selected state tracked via `viewModel.*Ranges` (`Set<String>` of range IDs like `"2000-5000"`). Dollar formatting via file-level `formatDollars()` function (avoids `@MainActor` isolation issues). `toggle()` helper uses `inout Set<String>`; `syncBudget()` recomputes effective min/max via closures. `.clipShape()` prevents button overflow outside card corners. 3 `#Preview` variants. |
| `OnboardingLoveLanguagesView.swift` | 8 | **Active (Step 3.8).** Dark-themed love language selection with 5 full-width cards in a `ScrollView`. Each card (`LoveLanguageCard`, private struct) displays a unique `LinearGradient` background, circular Lucide icon badge, display name (`.headline.weight(.bold)`), and contextual description (`.caption`). Two-step selection: first tap sets **Primary** (pink border, "PRIMARY" capsule badge, 1.02x scale), second tap on different card sets **Secondary** (muted pink border, "SECONDARY" badge). Badge is a `ZStack(alignment: .topTrailing)` overlay — completely independent of text layout so long names never wrap. `LoveLanguageSelectionState` (private `Equatable` enum: `.unselected`, `.primary`, `.secondary`) drives all visual states via `.animation(.easeInOut, value: selectionState)`. `selectLanguage()` handles 5 branches: tap primary clears both, tap secondary clears it, no primary sets primary, no secondary sets secondary, both set replaces secondary. Dynamic header subtitle guides through selection states. Status bar at bottom shows contextual progress. Personalized title with partner name from Step 3.2. Static functions `displayName(for:)`, `languageDescription(for:)`, `languageIcon(for:)`, `languageGradient(for:)` map `snake_case` keys to display data. Lucide icons: `messageCircle`, `heartHandshake`, `gift`, `clock`, `hand`. Calls `viewModel.validateCurrentStep()` via `.onAppear` and `.onChange(of: primaryLoveLanguage/secondaryLoveLanguage)`. 3 `#Preview` variants. |
| `OnboardingCompletionView.swift` | 9 | **Active (Step 3.9).** Scrollable completion screen with success header and comprehensive partner profile summary. Contains 6 `SummaryCard` sections: Partner Info (name, tenure, cohabitation, location), Interests & Dislikes (`CompactTag` pills in `FlowLayout`), Milestones (birthday, anniversary, holidays, custom — with computed "Next up: X in Y days" indicator using `nextUpcomingMilestone()`), Aesthetic Vibes (accent capsule pills with Lucide icons via `OnboardingVibesView.vibeIcon(for:)`/`.displayName(for:)`), Budget Tiers (3 rows with Lucide `coffee`/`gift`/`sparkles` icons and formatted dollar ranges), Love Languages (Primary/Secondary rows with Lucide icons via `OnboardingLoveLanguagesView.languageIcon(for:)`/`.displayName(for:)` and rank capsule badges). Private structs: `SummaryCard<Content: View>` (generic card container with icon + title header), `CompactTag` (capsule pill with `.accent`/`.muted` styles). File-level `formatDollars()` avoids `@MainActor` isolation. Formatting helpers: `formatTenure()`, `formatCohabitation()`, `formatMonthDay()`. "Get Started" button is in the container's navigation bar. 3 `#Preview` variants (Empty, Full Profile, Minimal Profile). |

#### `/Core` — Shared Utilities
| File | Purpose |
|------|---------|
| `Constants.swift` | App-wide constants: API URLs, Supabase configuration (`projectURL`, `anonKey`), validation rules, predefined categories (40 interests, 8 vibes, 5 love languages). |
| `Theme.swift` | **App-wide design system (Step 3.3).** Centralizes all colors, gradients, and surfaces for the dark purple aesthetic. Contains: `backgroundGradient` (dark purple LinearGradient from `(0.10, 0.05, 0.16)` to `(0.05, 0.02, 0.10)`), `surface` / `surfaceElevated` / `surfaceBorder` (semi-transparent white at 8%/12%/12% opacity), `accent` (Color.pink), `textPrimary` / `textSecondary` / `textTertiary` (white at 100%/60%/35% opacity), and `progressTrack` / `progressFill`. All views MUST use `Theme` constants — never hardcode colors. |

Future files:
- `Extensions.swift` — Swift type extensions
- `NetworkMonitor.swift` — Online/offline detection

#### `/Services` — Data & API Layer
| File | Status | Purpose |
|------|--------|---------|
| `SupabaseClient.swift` | **Active** | Singleton `SupabaseManager.client` initialized with `Constants.Supabase.projectURL` and `anonKey`. The Supabase Swift SDK automatically handles Keychain session storage and token refresh. Used by `AuthViewModel` and future service classes. |
| `APIClient.swift` | Planned | HTTP client for backend API calls |
| `AuthService.swift` | Planned | Authentication logic (sign in, sign out, session) |
| `VaultService.swift` | Planned | Partner Vault CRUD operations |
| `HintService.swift` | Planned | Hint capture and retrieval |
| `RecommendationService.swift` | Planned | Recommendation fetching and feedback |

#### `/Models` — Data Models
| File | Purpose |
|------|---------|
| `SyncStatus.swift` | Shared enum (`synced`, `pendingUpload`, `pendingDownload`) tracking local-to-Supabase sync state. Used by all `@Model` classes. Stored as raw `String` in SwiftData with a computed property for type-safe access. |
| `PartnerVaultLocal.swift` | SwiftData `@Model` mirroring `partner_vaults` table. Stores partner profile (name, tenure, cohabitation, location) locally. `remoteID` is nullable (NULL until synced with Supabase). |
| `HintLocal.swift` | SwiftData `@Model` mirroring `hints` table. Stores captured hints (text, source, isUsed). Deliberately excludes `hint_embedding` (vector(768)) — embeddings are server-side only for semantic search. |
| `MilestoneLocal.swift` | SwiftData `@Model` mirroring `partner_milestones` table. Stores milestones (type, name, date, recurrence, budgetTier) for Home screen countdown display. |
| `RecommendationLocal.swift` | SwiftData `@Model` mirroring `recommendations` table. Stores AI-generated recommendations for Choice-of-Three display. `description` renamed to `descriptionText` to avoid Swift protocol conflict. |
| `DTOs.swift` | Data Transfer Objects for API requests/responses (future) |

#### `/Components` — Reusable UI Components
Shadcn-inspired, reusable SwiftUI components.

| Component | Status | Purpose |
|-----------|--------|---------|
| `FlowLayout.swift` | **Active** | Custom `Layout` protocol implementation for wrapping flow (CSS `flex-wrap` equivalent). Arranges subviews left-to-right, wrapping to the next row when they exceed available width. Configurable `horizontalSpacing` and `verticalSpacing`. Created in Step 3.3 for chip grids; will be used by DislikesView (Step 3.4) and VibesView (Step 3.6). |
| `ChipView.swift` | Planned | Selectable tag/pill for interests and vibes |
| `CardView.swift` | Planned | Recommendation card with image, title, price |
| `ButtonStyles.swift` | Planned | Primary, secondary, and ghost button styles |
| `InputField.swift` | Planned | Text input with label and validation |
| `LoadingView.swift` | Planned | Loading spinner with optional message |

#### `/Resources` — Assets
| File | Purpose |
|------|---------|
| `Assets.xcassets/` | App icon, accent color, and image assets |
| `Assets.xcassets/Interests/` | **Namespaced folder group** (`provides-namespace: true`) containing 40 image sets for interest card backgrounds. Convention: `interest-{lowercased-hyphenated}` (e.g., `interest-travel`, `interest-board-games`). Each set holds a JPEG (~280x400px). Referenced in code as `"Interests/interest-travel"` via `OnboardingInterestsView.imageName(for:)`. Cards gracefully fall back to gradient + SF Symbol when an image set is empty. |
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
│       ├── 00010_create_recommendations_table.sql        # Recommendations with CHECK (type), price_cents >= 0, milestone FK SET NULL, RLS, CASCADE
│       ├── 00011_create_recommendation_feedback_table.sql # Recommendation feedback with CHECK (action, rating 1-5), dual FK (recommendation + user), direct RLS, CASCADE
│       └── 00012_create_notification_queue_table.sql      # Notification queue with CHECK (days_before 14/7/3, status), DEFAULT pending, partial index, direct RLS, CASCADE
├── tests/                    # Backend test suite (pytest)
│   ├── __init__.py
│   ├── test_imports.py       # Verifies all dependencies are importable (11 tests)
│   ├── test_supabase_connection.py  # Verifies Supabase connectivity and pgvector (11 tests)
│   ├── test_supabase_auth.py # Verifies auth service and Apple Sign-In config (6 tests)
│   ├── test_auth_middleware.py # Verifies backend auth middleware — valid/invalid/missing tokens, malformed headers, health unprotected (14 tests)
│   ├── test_users_table.py   # Verifies users table schema, RLS, and triggers (10 tests)
│   ├── test_partner_vaults_table.py  # Verifies partner_vaults schema, constraints, RLS, cascades (15 tests)
│   ├── test_partner_interests_table.py  # Verifies partner_interests schema, CHECK/UNIQUE constraints, RLS, cascades (22 tests)
│   ├── test_partner_milestones_table.py # Verifies partner_milestones schema, budget tier trigger, RLS, cascades (28 tests)
│   ├── test_partner_vibes_table.py      # Verifies partner_vibes schema, CHECK/UNIQUE constraints, RLS, cascades (19 tests)
│   ├── test_partner_budgets_table.py    # Verifies partner_budgets schema, CHECK constraints (occasion_type, max>=min, min>=0), UNIQUE, RLS, cascades (27 tests)
│   ├── test_partner_love_languages_table.py # Verifies partner_love_languages schema, CHECK (language, priority), dual UNIQUE, RLS, update semantics, cascades (28 tests)
│   ├── test_hints_table.py               # Verifies hints schema, CHECK (source), vector(768) embedding, HNSW index, match_hints() RPC similarity search, RLS, cascades (30 tests)
│   ├── test_recommendations_table.py     # Verifies recommendations schema, CHECK (type, price>=0), milestone FK SET NULL, RLS, data integrity, cascades (31 tests)
│   ├── test_recommendation_feedback_table.py # Verifies recommendation_feedback schema, CHECK (action, rating 1-5), dual FK CASCADE, direct RLS, data integrity, cascades (27 tests)
│   └── test_notification_queue_table.py  # Verifies notification_queue schema, CHECK (days_before, status), DEFAULT pending, status transitions, partial index, direct RLS, cascades (26 tests)
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
| `health_check()` | `GET /health` — Returns `{"status": "ok"}`. Unprotected. Used by deployment platforms for uptime monitoring. |
| `get_current_user()` | `GET /api/v1/me` — **Protected** endpoint that returns `{"user_id": "<uuid>"}`. Uses `Depends(get_current_user_id)` to validate the Bearer token. Serves as a "who am I" endpoint and auth middleware verification route. Added in Step 2.5. |

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
| `security.py` | **Auth middleware (Step 2.5).** Exports `get_current_user_id` — a FastAPI dependency that extracts the Bearer token from the `Authorization` header via `HTTPBearer(auto_error=False)`, validates it against Supabase Auth's `/auth/v1/user` endpoint using `httpx.AsyncClient`, and returns the authenticated user's UUID string. Raises `HTTPException(401)` with `WWW-Authenticate: Bearer` header for all failure cases: missing token, invalid/expired token, network errors, and malformed responses. Uses a private `_get_apikey()` helper with lazy import of `SUPABASE_ANON_KEY` to avoid circular dependencies. Usage: `async def route(user_id: str = Depends(get_current_user_id))`. |

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
| `00011_create_recommendation_feedback_table.sql` | Creates `public.recommendation_feedback` table (id, recommendation_id, user_id, action, rating, feedback_text, created_at). Stores user feedback on AI-generated recommendations — tracks selections, refreshes, saves, shares, and star ratings. CHECK constraint on `action` for 5 values: selected, refreshed, saved, shared, rated. CHECK constraint on `rating` for 1-5 range (nullable — only required for 'rated' action). `feedback_text` is nullable for optional text feedback. **First table with dual FK CASCADE:** `recommendation_id` FK to `recommendations` (CASCADE) and `user_id` FK to `users` (CASCADE) — feedback is deleted when either the recommendation or user is removed. **First table with direct RLS** (not vault subquery): policies use `user_id = auth.uid()` directly since the table has its own `user_id` column. Two indexes: `recommendation_id` for querying by recommendation, `user_id` for querying by user. No UNIQUE constraints — multiple feedback entries per recommendation allowed (e.g., selected then rated). |
| `00012_create_notification_queue_table.sql` | Creates `public.notification_queue` table (id, user_id, milestone_id, scheduled_for, days_before, status, sent_at, created_at). Schedules proactive push notifications for upcoming milestones at 14, 7, and 3 days before. CHECK constraint on `days_before` for 3 discrete values: 14, 7, 3. CHECK constraint on `status` for 4 values: pending, sent, failed, cancelled. `status` defaults to `'pending'` via DEFAULT clause. `sent_at` is nullable (NULL until notification is actually sent). `user_id` FK to `users` (CASCADE) and `milestone_id` FK to `partner_milestones` (CASCADE) — notifications are cleaned up when either the user or milestone is deleted. Uses direct RLS (`user_id = auth.uid()`). **First table with a partial composite index:** `(status, scheduled_for) WHERE status = 'pending'` — optimized for the notification processing job's "find all pending notifications due now" query. Also has standard indexes on `user_id` and `milestone_id`. |

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

### 0. App-Wide Dark Theme & Design System
The entire app uses a dark purple aesthetic, enforced at the app level:
- **`KnotApp.swift`** applies `.preferredColorScheme(.dark)` on the root `ContentView`, so ALL views render in dark mode. Individual views should never set this modifier.
- **`Theme.swift`** centralizes all colors. Views reference `Theme.accent`, `Theme.surface`, `Theme.backgroundGradient`, etc. — never hardcode color values.
- **Background gradient** is applied by each major container (`SignInView`, `OnboardingContainerView`, `HomeView`) with `.ignoresSafeArea()`. Step views inside the onboarding container are transparent and inherit the container background.
- **SwiftUI semantic colors** (`.primary`, `.secondary`, `.tertiary`) resolve correctly in dark mode. Use `Theme.textSecondary` / `.textTertiary` only when the exact reference-design opacity is needed.

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
- `test_auth_middleware.py` — Integration tests verifying the FastAPI auth middleware (Step 2.5). 14 tests across 5 classes: valid token (200 response, correct user_id, JSON structure), invalid token (garbage token, fake JWT, empty bearer — all 401), no token (missing header returns 401 with descriptive message and WWW-Authenticate header per RFC 7235), malformed headers (Basic auth and raw token without Bearer prefix — both 401), and health endpoint unprotected (200 with and without auth). Tests create real Supabase auth users via the Admin API, sign them in to get valid JWTs, and clean up automatically. Introduces `test_auth_user_with_token` fixture (creates user, signs in, yields user info + access_token, deletes on teardown) and `client` fixture (FastAPI TestClient from `app.main`).
- `test_users_table.py` — Integration tests verifying the `public.users` table schema, RLS enforcement, and trigger behavior (Step 1.1). Tests create real auth users via the Supabase Admin API, verify the `handle_new_user` trigger auto-creates profile rows, confirm RLS blocks anonymous access, and validate CASCADE delete behavior. Each test uses a `test_auth_user` fixture that creates and cleans up auth users automatically.
- `test_partner_vaults_table.py` — Integration tests verifying the `public.partner_vaults` table schema, constraints, RLS enforcement, and trigger/CASCADE behavior (Step 1.2). 15 tests across 4 classes: table existence, schema verification (columns, NOT NULL, CHECK constraint, UNIQUE, defaults), RLS (anon blocked, service bypasses, user isolation), and triggers/cascades (updated_at auto-updates, cascade delete through auth→users→vaults, FK enforcement). Introduces `test_auth_user_pair` fixture for two-user isolation tests and `test_vault` fixture for vault-dependent tests.
- `test_partner_interests_table.py` — Integration tests verifying the `public.partner_interests` table schema, CHECK constraints (interest_type + interest_category), UNIQUE constraint (prevents duplicates and like+dislike conflicts), RLS enforcement via subquery, data integrity (5 likes + 5 dislikes), and CASCADE behavior (Step 1.3). 22 tests across 5 classes: table existence, schema (columns, CHECK constraints, UNIQUE, NOT NULL), RLS (anon blocked, service bypasses, user isolation), data integrity (insert/retrieve 5+5, no overlap, predefined list), and cascades (vault deletion, full auth chain, FK enforcement). Introduces `test_vault_with_interests` fixture (vault pre-populated with 5 likes + 5 dislikes) and `_insert_interest_raw` helper for testing failure responses.
- `test_partner_milestones_table.py` — Integration tests verifying the `public.partner_milestones` table schema, CHECK constraints (milestone_type + recurrence + budget_tier), budget tier auto-default trigger, RLS enforcement via subquery, data integrity (multiple milestones per vault, field verification), and CASCADE behavior (Step 1.4). 28 tests across 6 classes: table existence, schema (columns, 3 CHECK constraints, NOT NULL, date storage), budget tier defaults (birthday/anniversary auto-major, holiday auto-minor, holiday override, custom user-provided, custom without tier rejected), RLS (anon blocked, service bypasses, user isolation), data integrity (multiple milestones, field verification, duplicate types allowed), and cascades (vault deletion, full auth chain, FK enforcement). Introduces `test_vault_with_milestones` fixture (vault pre-populated with 4 milestones: birthday, anniversary, Valentine's Day, custom) and `_insert_milestone_raw` helper for testing failure responses.
- `test_partner_vibes_table.py` — Integration tests verifying the `public.partner_vibes` table schema, CHECK constraint (vibe_tag for 8 values), UNIQUE constraint (prevents duplicate vibes per vault), RLS enforcement via subquery, data integrity (multiple vibes, single vibe, max 4 vibes), and CASCADE behavior (Step 1.5). 19 tests across 5 classes: table existence, schema (columns, CHECK constraint, NOT NULL, UNIQUE prevents duplicates, same vibe allowed across vaults), RLS (anon blocked, service bypasses, user isolation), data integrity (multiple vibes, field values, max 4, single vibe), and cascades (vault deletion, full auth chain, FK enforcement). Introduces `test_vault_with_vibes` fixture (vault pre-populated with 3 vibes: quiet_luxury, minimalist, romantic) and `_insert_vibe_raw` helper for testing failure responses.
- `test_partner_budgets_table.py` — Integration tests verifying the `public.partner_budgets` table schema, CHECK constraints (occasion_type for 3 values, max_amount >= min_amount, min_amount >= 0), UNIQUE constraint (prevents duplicate occasion types per vault), RLS enforcement via subquery, data integrity (all 3 tiers stored, amounts correct in cents, currency defaults, integer storage, zero min allowed), and CASCADE behavior (Step 1.6). 27 tests across 5 classes: table existence, schema (columns, 3 CHECK constraints, NOT NULL for all required fields, UNIQUE prevents duplicate occasion types, same type allowed across vaults, currency default/override), RLS (anon blocked, service bypasses, user isolation), data integrity (3 tiers stored and verified, amounts in cents, field values, zero min), and cascades (vault deletion, full auth chain, FK enforcement). Introduces `test_vault_with_budgets` fixture (vault pre-populated with 3 budget tiers: just_because $20-$50, minor_occasion $50-$150, major_milestone $100-$500) and `_insert_budget_raw` helper for testing failure responses.
- `test_partner_love_languages_table.py` — Integration tests verifying the `public.partner_love_languages` table schema, CHECK constraints (language for 5 values, priority for 1/2 only), dual UNIQUE constraints (vault_id+priority prevents duplicate priorities, vault_id+language prevents same language at both priorities), RLS enforcement via subquery, data integrity (primary/secondary stored, field values, update primary succeeds, update to conflicting language fails), and CASCADE behavior (Step 1.7). 28 tests across 5 classes: table existence, schema (columns, 2 CHECK constraints, NOT NULL, 2 UNIQUE constraints, third language rejection, same language across vaults allowed, priority 0 rejected), RLS (anon blocked, service bypasses, user isolation), data integrity (primary+secondary stored, field values, primary correct, secondary correct, update primary succeeds, update to same-as-secondary fails), and cascades (vault deletion, full auth chain, FK enforcement). Introduces `test_vault_with_love_languages` fixture (vault pre-populated with primary=quality_time, secondary=receiving_gifts), `_insert_love_language_raw` helper for testing failure responses, and `_update_love_language` helper for testing update semantics.
- `test_hints_table.py` — Integration tests verifying the `public.hints` table schema, CHECK constraint (source for 2 values), vector(768) embedding column (nullable, accepts 768-dim vectors), HNSW index, `match_hints()` RPC function for cosine similarity search, RLS enforcement via subquery, data integrity (multiple hints, mixed sources, is_used default and update, with/without embeddings), vector similarity search (ordering verification with crafted vectors, threshold filtering, match_count limiting, vault scoping, NULL embedding skipping), and CASCADE behavior (Step 1.8). 30 tests across 6 classes: table existence, schema (columns, CHECK constraint, NOT NULL, is_used default, embedding nullable, embedding accepts 768-dim), RLS (anon blocked, service bypasses, user isolation), data integrity (multiple hints, field values, mixed sources, is_used update, with/without embedding), vector search (returns results, ordered by similarity, threshold filters, match_count limits, scoped to vault, skips NULL embeddings), and cascades (vault deletion, full auth chain, FK enforcement). Introduces `test_vault_with_hints` fixture (vault with 3 hints without embeddings), `test_vault_with_embedded_hints` fixture (vault with 3 hints with crafted 768-dim vectors for similarity testing), `_insert_hint_raw` helper for testing failure responses, and `_make_vector` helper for creating padded 768-dim vector strings.
- `test_recommendations_table.py` — Integration tests verifying the `public.recommendations` table schema, CHECK constraints (recommendation_type for 3 values, price_cents >= 0), nullable columns (milestone_id, description, external_url, price_cents, merchant_name, image_url), milestone FK SET NULL behavior, RLS enforcement via subquery, data integrity (3 recommendations per vault/"Choice of Three", all fields populated, all 3 types stored, with/without milestone, prices in cents, external URLs, merchant names), milestone FK behavior (SET NULL on milestone delete preserves recommendation history, FK enforcement rejects invalid milestone_id), and CASCADE behavior (Step 1.9). 31 tests across 6 classes: table existence, schema (columns, CHECK constraints, NOT NULL for title/type, nullable for description/url/price/merchant/image/milestone_id, price accepts zero, price rejects negative), RLS (anon blocked, service bypasses, user isolation), data integrity (3 recs stored, all fields verified, types stored, milestone linked, without milestone, prices in cents, URLs, merchants), milestone FK (SET NULL on delete, FK enforcement), and cascades (vault deletion, full auth chain, FK enforcement). Introduces `test_vault_with_milestone` fixture (vault with birthday milestone), `test_vault_with_recommendations` fixture (vault with 3 recommendations: gift/experience/date linked to milestone), `_insert_recommendation_raw` helper for testing failure responses, and sample recommendation constants (`SAMPLE_GIFT_REC`, `SAMPLE_EXPERIENCE_REC`, `SAMPLE_DATE_REC`).
- `test_recommendation_feedback_table.py` — Integration tests verifying the `public.recommendation_feedback` table schema, CHECK constraints (action for 5 values, rating for 1-5 range), dual FK CASCADE (recommendation_id + user_id), direct RLS enforcement (`user_id = auth.uid()`), data integrity (selected action, rated with text, multiple feedback per recommendation), and CASCADE behavior (Step 1.10). 27 tests across 5 classes: table existence, schema (columns, action CHECK with all 5 values tested, rating range CHECK rejects 0 and 6, rating accepts 1-5, rating nullable, feedback_text nullable/stores value, action NOT NULL), RLS (anon blocked, service bypasses, user isolation), data integrity (selected action queried by recommendation_id, rated with text stored, multiple entries per recommendation), and cascades (recommendation deletion, full auth chain, recommendation_id FK enforcement, user_id FK enforcement). Introduces `test_vault_with_recommendation` fixture (vault with a gift recommendation), `test_feedback_selected` fixture (feedback with action='selected'), `_insert_feedback_raw` helper for testing failure responses, and `_delete_feedback` helper.
- `test_notification_queue_table.py` — Integration tests verifying the `public.notification_queue` table schema, CHECK constraints (days_before for 14/7/3, status for 4 values), DEFAULT status to 'pending', status transition semantics, direct RLS enforcement (`user_id = auth.uid()`), data integrity (pending stored, 3 per milestone ordered, field values, status update to sent with sent_at, status update to cancelled), and CASCADE behavior (Step 1.11). 26 tests across 5 classes: table existence, schema (columns, days_before CHECK rejects invalid/accepts 14/7/3, status CHECK rejects invalid/accepts all 4, status defaults to pending, sent_at nullable, scheduled_for NOT NULL, days_before NOT NULL), RLS (anon blocked, service bypasses, user isolation), data integrity (pending queryable, 3 per milestone at 14/7/3, field values verified, update to sent with sent_at, update to cancelled), and cascades (milestone deletion, full auth chain, milestone_id FK enforcement, user_id FK enforcement). Introduces `test_vault_with_milestone` fixture (vault with birthday milestone), `test_notification_pending` fixture (single pending at 14 days), `test_three_notifications` fixture (14/7/3 set), `_insert_notification_raw` helper, `_update_notification` helper, and `_future_timestamp` helper for generating ISO 8601 timestamps.

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
- The `recommendation_feedback` table (Step 1.10) links to specific recommendation IDs to track which ones were selected, refreshed, saved, or shared

### 45. Direct RLS vs Vault Subquery RLS
Two RLS patterns are now used in the schema:

**Vault Subquery Pattern** (used by child tables of `partner_vaults`):
```sql
USING (EXISTS (
    SELECT 1 FROM public.partner_vaults
    WHERE partner_vaults.id = child_table.vault_id
    AND partner_vaults.user_id = auth.uid()
))
```
Used by: `partner_interests`, `partner_milestones`, `partner_vibes`, `partner_budgets`, `partner_love_languages`, `hints`, `recommendations`

**Direct User ID Pattern** (used by tables with their own `user_id` column):
```sql
USING (user_id = auth.uid())
```
Used by: `users`, `recommendation_feedback`, `notification_queue`

The direct pattern is simpler and more performant (no subquery/join needed). It's used when the table has a direct relationship to the user, not mediated through the partner vault. The `recommendation_feedback` and `notification_queue` tables have their own `user_id` because they model user actions and system events rather than partner profile data.

### 46. Dual FK CASCADE on Feedback Table
The `recommendation_feedback` table is the **first table with foreign keys to two different parent tables** that both use CASCADE:
- `recommendation_id → recommendations ON DELETE CASCADE`
- `user_id → users ON DELETE CASCADE`

This means a feedback row can be deleted from two independent paths:
1. When the recommendation is deleted (e.g., vault deletion cascading through `vaults → recommendations → feedback`)
2. When the user account is deleted (e.g., `auth.users → users → feedback`)

This is safe because feedback is meaningless without either the recommendation it refers to or the user who provided it. Both CASCADE paths lead to correct cleanup.

### 47. Partial Composite Index for Job Processing
The `notification_queue` table introduces a **partial index** — the first in the schema:
```sql
CREATE INDEX idx_notification_queue_status_scheduled
    ON public.notification_queue (status, scheduled_for)
    WHERE status = 'pending';
```

This index only includes rows where `status = 'pending'`, making it highly efficient for the notification processing job's primary query pattern: "find all pending notifications scheduled before NOW." Key benefits:
- The index is much smaller than a full index (excludes sent/failed/cancelled rows that accumulate over time)
- As notifications are processed and marked 'sent', they automatically leave the index
- The composite `(status, scheduled_for)` allows PostgreSQL to satisfy both the filter and the sort in a single index scan

This pattern is recommended for any "job queue" table where the processing query always filters by a specific status value.

### 48. Notification Queue as CASCADE (Not SET NULL)
The `notification_queue.milestone_id` uses `ON DELETE CASCADE` (not SET NULL like `recommendations.milestone_id`). The reasoning:
- **Notifications are prospective** — they represent future actions to be taken. If the milestone is deleted, the notifications are meaningless and should be cleaned up.
- **Recommendations are retrospective** — they represent past suggestions that the user may have acted on. Preserving them as historical records (with `milestone_id` set to NULL) is valuable for the feedback/learning loop.

This creates a clear pattern: **forward-looking references CASCADE, backward-looking references SET NULL.**

### 49. SwiftData Model Design Decisions
The SwiftData models (Step 1.12) follow several deliberate design choices:

**Raw String for Enum Storage:**
SwiftData has limitations with persisting custom enums directly. `SyncStatus` is stored as `syncStatusRaw: String` with a computed `syncStatus` property for type-safe access. This pattern should be used for all future SwiftData enums.

**Nullable `remoteID` for Offline-First:**
All models use `remoteID: UUID?` (nullable) rather than a required ID. When a record is created locally (e.g., capturing a hint while offline), it won't have a Supabase UUID until it's synced. The nullable pattern enables offline-first creation without dummy IDs.

**No SwiftData `@Relationship` Links:**
The models do NOT define SwiftData `@Relationship` between them (e.g., vault → hints). Relationships are managed via UUID foreign keys, matching the Supabase schema pattern. This avoids SwiftData's complex relationship lifecycle management and keeps the models as simple data containers. SwiftData relationships can be added later if local query performance demands it.

**Excluded Server-Only Columns:**
`HintLocal` excludes `hint_embedding` (768-float vector). This column is only used server-side for semantic search via the `match_hints()` RPC function. Storing it on-device would waste ~3KB per hint with no local utility.

### 51. SignInView Architecture (Step 2.1)
The `SignInView` is the first feature view in the app and establishes patterns for future feature views:

**View-Only Pattern (No ViewModel Yet):**
Step 2.1 uses a simple `@State`-based view without a separate ViewModel. The sign-in result handler is a private method on the view struct. This is intentional for the MVP — the view is simple enough that a ViewModel would be over-engineering. A ViewModel (`AuthViewModel`) will be introduced in Step 2.2 when Supabase session management adds complexity.

**Private Sub-Components:**
The `SignInFeatureRow` component is `private` within `SignInView.swift` rather than being placed in `/Components/`. This is because it's a presentational component specific to the sign-in screen with no reuse potential. Components that ARE reusable across features (like `ChipView`, `CardView`) should go in `/Components/`.

**Error Handling Strategy:**
The view distinguishes between user-initiated cancellation (`ASAuthorizationError.canceled`) and system errors. Cancellation is silently ignored (standard iOS behavior — the user knowingly dismissed the sheet). All other errors surface as alerts. This two-tier error handling pattern should be followed for all user-facing flows.

**Credential Extraction Pattern:**
The Apple credential provides three key pieces: `user` (stable Apple user ID), `email` (only on first sign-in, nil on subsequent), and `identityToken` (JWT for server validation). The identity token is the critical piece for Step 2.2 — it's sent to Supabase Auth via `signInWithIdToken(provider: .apple, idToken: token)`.

### 52. Entitlements File Strategy
The `Knot.entitlements` file is the central location for all iOS app capabilities. Currently contains only Sign in with Apple. Future additions will include:
- `aps-environment` — Push notification entitlement (Step 7.4)
- `com.apple.developer.associated-domains` — Universal links for deep linking (Step 9.1)

The entitlements file is referenced in two places in `project.yml`:
1. `entitlements.path` — XcodeGen uses this to set up the Xcode project correctly
2. `CODE_SIGN_ENTITLEMENTS` — The build setting that tells the code signing process which entitlements to embed

### 53. ContentView as Auth State Router (Step 2.3)
`ContentView` is the root auth state router with three states:
1. **`isCheckingSession = true`** → Shows a loading spinner while the Supabase SDK checks the Keychain for a stored session
2. **`isAuthenticated = true`** → Shows `HomeView()`
3. **`isAuthenticated = false`** → Shows `SignInView()`

```swift
struct ContentView: View {
    @State private var authViewModel = AuthViewModel()
    var body: some View {
        Group {
            if authViewModel.isCheckingSession { ProgressView() }
            else if authViewModel.isAuthenticated { HomeView() }
            else { SignInView() }
        }
        .environment(authViewModel)
        .task { await authViewModel.listenForAuthChanges() }
    }
}
```

The `AuthViewModel` is created here and injected into the SwiftUI environment. All child views share the same auth state instance. The `.task` modifier starts the `authStateChanges` listener, which runs for the lifetime of the root view.

### 54. Apple Developer Program Requirement
Sign in with Apple requires the **paid Apple Developer Program** ($99/year) for full functionality. Without it:
- Error 1000 (`ASAuthorizationError.unknown`) occurs when tapping the sign-in button
- App IDs cannot be registered with the Sign in with Apple capability
- The Apple Sign-In sheet will not appear on the Simulator or device

The free Apple Developer account allows building and running on the Simulator but cannot access Certificates, Identifiers & Profiles. This is a prerequisite for Steps 2.1–2.4 to be fully testable end-to-end. The code implementation is correct regardless of enrollment status.

**Critical: Team Selection in Xcode**
After enrolling in the paid program, Xcode may still default to the **"Personal Team"** (the free tier). The Team dropdown in Signing & Capabilities will show two entries with the same name -- select the one that is NOT labeled "(Personal Team)". Using the Personal Team will produce: *"Cannot create a iOS App Development provisioning profile... Personal development teams do not support the Sign In with Apple capability."* The correct paid team ID for this project is `VN5G3R8J23`.

### 55. Sign in with Apple — Simulator Testing Checklist
Validated end-to-end on iPhone 17 Pro Simulator (iOS 26.2). Three prerequisites for the Apple Sign-In sheet to appear:
1. **Paid Apple Developer Program** enrolled and active
2. **Correct team selected** in Xcode Signing & Capabilities (not "Personal Team")
3. **Apple ID signed in** on the Simulator (Settings > Apple Account)

The sign-in flow returns three pieces of data:
- `credential.user` — Stable Apple user ID (e.g., `000817.ddb36fbe43e549ce802859bbb818cfc2.0307`). This never changes for the same Apple ID + app combination.
- `credential.email` — Only returned on **first** sign-in. Subsequent sign-ins return `nil`. The app must persist this on first login.
- `credential.identityToken` — JWT for server-side validation. This is sent to Supabase Auth in Step 2.2.

### 56. AuthViewModel — OIDC Nonce Flow (Step 2.2)
The `AuthViewModel` implements the OpenID Connect (OIDC) nonce pattern to prevent replay attacks:

1. **Generate nonce:** `randomNonceString()` creates a 32-character cryptographically random string using `SecRandomCopyBytes`. This is the "raw nonce."
2. **Hash for Apple:** `sha256()` hashes the raw nonce using `CryptoKit.SHA256`. The hash is set on `ASAuthorizationAppleIDRequest.nonce`. Apple embeds this hash in the identity token JWT.
3. **Send raw to Supabase:** The *unhashed* nonce is sent to Supabase via `OpenIDConnectCredentials(nonce:)`. Supabase hashes it server-side and compares against the hash embedded in the JWT — if they match, the token is valid and hasn't been replayed.

**Why `nonisolated`?** The `configureRequest()` method is `nonisolated` because `SignInWithAppleButton`'s `request` closure may run off the main actor. It uses `MainActor.assumeIsolated` to safely write `currentNonce` to the actor-isolated property. The utility methods (`randomNonceString`, `sha256`) are `nonisolated static` because they're pure functions.

### 57. SupabaseManager Singleton Pattern (Step 2.2)
`SupabaseManager` is an `enum` (not a `class` or `struct`) to prevent accidental instantiation. It exposes a single `static let client` — the `SupabaseClient` instance used throughout the app.

**Keychain session storage** is handled automatically by the Supabase Swift SDK. When `signInWithIdToken` succeeds, the SDK stores the access token, refresh token, and user metadata in the iOS Keychain. On subsequent app launches, the SDK retrieves the stored session — Step 2.3 will use this to determine if the user is already authenticated.

**Thread safety:** The `SupabaseClient` is designed to be called from any thread. The `AuthViewModel` ensures UI state updates happen on `@MainActor`, but the Supabase network calls are standard `async/await`.

### 58. XcodeGen Entitlements Regeneration Gotcha (Step 2.2)
Running `xcodegen generate` can overwrite the `Knot.entitlements` file to an empty `<dict/>` if the `entitlements` section in `project.yml` doesn't include `properties`. The fix is to declare capabilities in two places:

```yaml
# project.yml
entitlements:
  path: Knot/Knot.entitlements
  properties:                              # <-- THIS prevents overwriting
    com.apple.developer.applesignin:
      - Default
```

Without the `properties` key, XcodeGen creates a blank entitlements file. With it, the file is generated with the correct content. This is critical when adding future entitlements (push notifications, associated domains).

### 59. Supabase Anon Key Safety (Step 2.2)
The `Constants.Supabase.anonKey` is a **publishable** key — it is safe to embed in the app binary. It grants only the permissions defined by Row Level Security (RLS) policies on each table. The actual data access is controlled by the JWT (obtained after `signInWithIdToken`) which encodes the user's `auth.uid()`. All Supabase tables use RLS policies that check `auth.uid()` against the row's `user_id` column.

### 60. Session Persistence via authStateChanges (Step 2.3)
The Supabase Swift SDK provides an `AsyncSequence` called `authStateChanges` that emits `(AuthChangeEvent, Session?)` tuples. The event lifecycle:

1. **`initialSession`** — Always the first event. Contains the session restored from iOS Keychain, or `nil` if no session exists. This is the mechanism for session persistence — no manual Keychain code is needed.
2. **`signedIn`** — Emitted after a successful `signInWithIdToken` call. The `isAuthenticated` flag is set here (not in the sign-in method itself).
3. **`signedOut`** — Emitted after `signOut()`. Clears `isAuthenticated`.
4. **`tokenRefreshed`** — Emitted when the SDK silently refreshes an expired access token using the stored refresh token.
5. **`userUpdated`** — Emitted when user metadata changes.

All auth state transitions flow through this single listener (`listenForAuthChanges()` in `AuthViewModel`). This creates a **single source of truth** for auth state — no manual `isAuthenticated` assignments outside the listener.

### 61. Environment-Based ViewModel Sharing (Step 2.3)
The `AuthViewModel` is shared across the view hierarchy using SwiftUI's `@Observable` + `@Environment` pattern:

```
ContentView (@State authViewModel) ──.environment(authViewModel)──▶ SignInView (@Environment)
                                                                  ▶ HomeView (@Environment)
```

This replaces the older `@EnvironmentObject` pattern. Key implications:
- `ContentView` owns the `AuthViewModel` via `@State` (keeps it alive)
- Child views access it via `@Environment(AuthViewModel.self)` (read-only reference)
- For `$`-binding (e.g., `.alert(isPresented:)`), child views create a local `@Bindable var viewModel = authViewModel`
- All views react to the same `isAuthenticated` state — when the listener flips it, `ContentView` automatically swaps between `SignInView` and `HomeView`

### 62. isCheckingSession Anti-Flash Pattern (Step 2.3)
Without `isCheckingSession`, the app would show a flash of the Sign-In screen on every launch:
1. App starts → `isAuthenticated = false` (default) → `SignInView` renders
2. ~100ms later → Keychain check completes → `isAuthenticated = true` → `HomeView` renders

The `isCheckingSession = true` default introduces a third state (loading spinner) that absorbs this delay, preventing the jarring flash. The transition is: loading → Home (if session exists) or loading → Sign-In (if not).

### 63. HomeView Placeholder (Step 2.3 → Step 4.1)
`Features/Home/HomeView.swift` is a minimal placeholder created in Step 2.3 solely to verify session persistence navigation works. Updated in Step 2.4 to add sign-out functionality. It shows:
- Knot branding (Lucide heart icon)
- "Welcome to Knot" message
- "Session restored from Keychain" status indicator (Lucide `circleCheck` icon)
- Sign Out button (red bordered, full-width) and toolbar icon (Step 2.4)

The full Home screen (hint capture, milestone cards, network monitoring) will replace this in Step 4.1. The sign-out button will move to the Settings screen in Step 11.1.

### 64. Sign-Out Flow — Listener-Driven State (Step 2.4)
The `signOut()` method in `AuthViewModel` deliberately does NOT set `isAuthenticated = false` directly. Instead, it calls `SupabaseManager.client.auth.signOut()` and relies on the `authStateChanges` listener to handle the `signedOut` event:

```
signOut() → Supabase SDK → server invalidation + Keychain clear → emits signedOut → listener sets isAuthenticated = false → ContentView swaps to SignInView
```

This is the same pattern used for sign-in (Step 2.3): `signInWithIdToken()` does not set `isAuthenticated = true` — the `signedIn` event does. Maintaining this pattern ensures a **single source of truth** for auth state. If any future code needs to check auth state, `isAuthenticated` is always driven by the Supabase SDK's event stream, never by manual assignment.

The sign-out also invalidates the session server-side (revokes the refresh token), so even if the local Keychain were somehow restored, the session would be rejected by Supabase Auth on the next API call.

### 65. Dual Sign-Out UI Affordances (Step 2.4)
`HomeView` provides two ways to sign out:
1. **Body button** — A prominent red bordered `Button(role: .destructive)` with Lucide `logOut` icon and "Sign Out" text. Full-width, 48pt height, `.buttonStyle(.bordered)` with `.tint(.red)`. Visible and discoverable for testing.
2. **Toolbar button** — A navigation bar `ToolbarItem(placement: .topBarTrailing)` with just the `logOut` icon. Tinted `.primary` to blend with the navigation bar.

Both call `authViewModel.signOut()` inside a `Task { }` block (since `signOut()` is `async`). Both are temporary — the permanent sign-out UI will live in the Settings screen (Step 11.1). The body button will be removed when the full Home screen is built (Step 4.1).

### 66. Onboarding Navigation Architecture (Step 3.1)
The onboarding flow uses a **container + step views** pattern:

```
ContentView (auth router)
  └── OnboardingContainerView (@State OnboardingViewModel)
        ├── Progress Bar (GeometryReader + animated fill)
        ├── Step Content (@ViewBuilder switch on currentStep)
        │     ├── OnboardingWelcomeView (@Environment OnboardingViewModel)
        │     ├── OnboardingBasicInfoView (@Environment OnboardingViewModel)
        │     ├── ... (7 more step views)
        │     └── OnboardingCompletionView (@Environment OnboardingViewModel)
        └── Navigation Buttons (Back / Next / Get Started)
```

Key design decisions:
- **Single ViewModel for all steps:** Unlike the Auth flow (where `AuthViewModel` handles one concern), the `OnboardingViewModel` holds ALL onboarding data across 9 steps. This is intentional — the data is interdependent (e.g., dislikes must exclude likes, budget tiers map to milestone types) and needs to persist across back/forward navigation.
- **Container owns the ViewModel:** `OnboardingContainerView` creates `OnboardingViewModel` via `@State` and injects it into the environment. This mirrors the `ContentView` → `AuthViewModel` ownership pattern.
- **Step views are stateless readers:** Each step view reads the shared `OnboardingViewModel` from `@Environment` and writes to its data properties. No step view creates its own `@State` data — everything lives in the ViewModel.
- **`.id()` for transition animations:** The step content uses `.id(viewModel.currentStep)` to force SwiftUI to treat each step as a new view identity. Without this, SwiftUI would try to diff the views in-place and the slide transition animation wouldn't fire.

### 67. ContentView Four-State Auth Router (Step 3.1)
`ContentView` now routes between four states (up from three in Step 2.3):

1. **`isCheckingSession = true`** → Loading spinner (checking Keychain)
2. **`isAuthenticated = true && hasCompletedOnboarding = true`** → `HomeView()`
3. **`isAuthenticated = true && hasCompletedOnboarding = false`** → `OnboardingContainerView`
4. **`isAuthenticated = false`** → `SignInView()`

The `hasCompletedOnboarding` flag is currently in-memory only (resets on app relaunch). Step 3.11 will check for an existing vault on session restore to persist this across launches.

### 68. OnboardingStep Enum Design
The `OnboardingStep` enum uses `Int` raw values (0–8) for two purposes:
1. **Progress calculation:** `progress = Double(step.rawValue) / Double(totalSteps - 1)` gives 0.0–1.0
2. **Navigation:** `OnboardingStep(rawValue: current + 1)` safely advances; returns `nil` at bounds

Computed properties (`title`, `isFirst`, `isLast`) keep the container view clean — no switch statements needed for basic step metadata.

### 69. Centralized Step Validation Pattern (Step 3.2)
The `OnboardingViewModel.validateCurrentStep()` method centralizes all step-level validation in a single switch statement:

```swift
func validateCurrentStep() {
    switch currentStep {
    case .basicInfo:
        canProceed = !partnerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    // Future: case .interests: canProceed = selectedInterests.count == 5
    default:
        canProceed = true
    }
}
```

This replaces the previous pattern of resetting `canProceed = true` in `goToNextStep()`/`goToPreviousStep()`. The method is called from three places:
1. **`goToNextStep()`** — validates the new step after advancing
2. **`goToPreviousStep()`** — validates the previous step when going back
3. **Step views** — via `.onAppear` (initial validation) and `.onChange(of: property)` (real-time validation as user types)

This dual-trigger approach (ViewModel-level + view-level) ensures validation is always up-to-date regardless of how the step is reached.

### 70. @Bindable Scoping and Custom Binding Strategy (Step 3.2)
`OnboardingBasicInfoView` introduces a pattern for handling bindings in views with `@Environment` `@Observable` objects:

- **Inside `body`:** `@Bindable var vm = viewModel` provides `$vm.partnerName` syntax for `TextField` and `Picker` controls. Bindings are passed as parameters to private methods (e.g., `nameSection(name: $vm.partnerName)`).
- **Inside computed properties:** `Binding(get:set:)` is used directly with the `@Environment` property (e.g., in `tenureSection`), since `@Bindable` is scoped to `body` and not accessible in other properties/methods.

This split is necessary because SwiftUI's `@Bindable` property wrapper can only be declared as a local variable inside `body`. Future step views should follow the same pattern: `@Bindable` for simple bindings in body, `Binding(get:set:)` for derived/computed bindings in extracted sub-views.

### 71. Deferred Validation Hint UX Pattern (Step 3.2)
The "Name is required to continue" hint uses a `@State private var hasInteractedWithName` flag to defer display:
- **On first load:** hint is hidden (user hasn't typed yet, showing an error would be jarring)
- **After first keystroke:** `hasInteractedWithName = true` (set via `.onChange(of: partnerName)`)
- **After clearing:** hint appears (user had text and deleted it — this is a meaningful validation failure)
- **After navigating away and back:** `hasInteractedWithName` resets to `false` (view is recreated via `.id()`) — hint is hidden again because the user must have had a valid name to leave the step

This pattern should be reused for any required field that starts empty. It decouples the validation error UX (when to show the message) from the `canProceed` validation logic (which always runs, even on first load).

### 72. Keyboard Submit Chaining Pattern (Step 3.2)
`OnboardingBasicInfoView` uses `@FocusState` with a `Field` enum to chain keyboard submit actions:
```
Name → (submit) → City → (submit) → State → (submit) → Dismiss keyboard
```
Each `TextField` uses `.focused($focusedField, equals: .fieldCase)` and `.onSubmit { focusedField = .nextField }`. The last field sets `focusedField = nil` to dismiss the keyboard. Combined with `.scrollDismissesKeyboard(.interactively)` on the `ScrollView`, this provides a smooth keyboard experience.

### 73. Tenure Decomposition Pattern (Step 3.2)
The ViewModel stores relationship tenure as a single integer (`relationshipTenureMonths: Int`). The UI decomposes this into two pickers (years 0–30 and months 0–11) using custom `Binding(get:set:)`:
- **get:** `viewModel.relationshipTenureMonths / 12` for years, `% 12` for months
- **set:** Recomposes as `newYears * 12 + remainingMonths` or `currentYears * 12 + newMonths`

This keeps the ViewModel data model simple (matches the database `relationship_tenure_months` integer column in `partner_vaults`) while providing an intuitive UI. The summary line (`"2 years, 6 months"`) is a computed property on the view that reads the ViewModel value.

### 74. Backend Auth Middleware — Server-Side Token Validation (Step 2.5)
The `get_current_user_id` FastAPI dependency validates tokens by calling Supabase's GoTrue API (`GET /auth/v1/user`) rather than decoding JWTs locally. Key design decisions:
- **Server-side validation over local JWT decode:** Ensures tokens are validated against the live session state — revoked sessions, expired tokens, and tampered JWTs are all properly rejected. The tradeoff is a network round-trip to Supabase on every authenticated request (~50-100ms), which is acceptable for MVP volume.
- **`HTTPBearer(auto_error=False)`:** By default, FastAPI's `HTTPBearer` returns 403 when the Authorization header is missing. Setting `auto_error=False` gives us control to return 401 with a descriptive message and `WWW-Authenticate: Bearer` header (RFC 7235 compliance).
- **`apikey` header required by Supabase:** Supabase's API gateway (Kong) requires the `apikey` header on every request, even authenticated ones. The anon key is used here — it's safe because actual access control is enforced by the Bearer token (JWT) and RLS policies, not the apikey.
- **Lazy `_get_apikey()` import:** The helper uses `from app.core.config import SUPABASE_ANON_KEY` inside the function body to avoid circular imports when `security.py` is imported at module level by `main.py`.
- **All failure paths return 401:** Missing token, invalid token, expired token, network errors, and malformed responses all raise `HTTPException(401)` with descriptive detail messages. This ensures the client always knows the issue is authentication-related.
- **Usage pattern:** All protected route handlers use `user_id: str = Depends(get_current_user_id)` to inject the authenticated user's UUID. The vault, hints, and recommendations endpoints will all follow this pattern.

### 75. Auth Middleware Test Strategy (Step 2.5)
The `test_auth_middleware.py` tests use a different approach from database table tests:
- **FastAPI TestClient:** Tests use `TestClient(app)` from `fastapi.testclient` to make HTTP requests against the actual FastAPI app in-process, not against a deployed server. This tests the full middleware pipeline (header extraction → Supabase validation → user ID return).
- **Real Supabase auth users:** The `test_auth_user_with_token` fixture creates a real auth user via the Admin API, signs them in to get a valid JWT, and cleans up on teardown. This tests against real Supabase infrastructure, not mocks.
- **`time.sleep(0.5)` in fixture:** After creating the auth user, the fixture waits 500ms for the `handle_new_user` trigger to fire and create the `public.users` row. Without this, the sign-in may race the trigger.
- **Comprehensive negative testing:** Tests verify not just that invalid tokens return 401, but also: garbage strings, structurally valid but fabricated JWTs (proves middleware validates with Supabase, not just format), empty bearers, Basic auth instead of Bearer, and raw tokens without the "Bearer " prefix.

### 50. Complete Database Schema Summary (End of Phase 1)
With Phase 1 complete, the full database schema consists of 12 tables:

| # | Table | Parent FK | Delete Behavior | RLS Pattern |
|---|-------|-----------|----------------|-------------|
| 1 | `users` | `auth.users` | CASCADE | Direct (`id = auth.uid()`) |
| 2 | `partner_vaults` | `users` | CASCADE | Direct (`user_id = auth.uid()`) |
| 3 | `partner_interests` | `partner_vaults` | CASCADE | Vault subquery |
| 4 | `partner_milestones` | `partner_vaults` | CASCADE | Vault subquery |
| 5 | `partner_vibes` | `partner_vaults` | CASCADE | Vault subquery |
| 6 | `partner_budgets` | `partner_vaults` | CASCADE | Vault subquery |
| 7 | `partner_love_languages` | `partner_vaults` | CASCADE | Vault subquery |
| 8 | `hints` | `partner_vaults` | CASCADE | Vault subquery |
| 9 | `recommendations` | `partner_vaults` + `partner_milestones` | CASCADE + SET NULL | Vault subquery |
| 10 | `recommendation_feedback` | `recommendations` + `users` | CASCADE + CASCADE | Direct (`user_id = auth.uid()`) |
| 11 | `notification_queue` | `users` + `partner_milestones` | CASCADE + CASCADE | Direct (`user_id = auth.uid()`) |

Total test count: **305 tests** across 15 test files (291 database/infrastructure + 14 auth middleware).

### 51. Badge overlay pattern (`ZStack` vs inline `HStack`)
When adding selection badges (e.g., "PRIMARY", "SECONDARY") to cards, **never** place them inline with text content in an `HStack` — long text like "Words of Affirmation" will wrap when the badge appears, causing layout jank. Instead, use a `ZStack(alignment: .topTrailing)` with the badge as a separate overlay layer. The text content (`HStack` with icon + name + description) sits in one layer; the badge floats in the top-right corner in another layer. This pattern keeps text layout completely stable regardless of selection state. Used in `LoveLanguageCard` (Step 3.8); should be adopted for any future card components with dynamic badges.

### 52. Love language selection state as `Equatable` enum
`LoveLanguageSelectionState` is a `private enum` with three cases: `.unselected`, `.primary`, `.secondary`. It conforms to `Equatable` (not `Sendable` — only used in view code). The `.animation(.easeInOut, value: selectionState)` modifier on `LoveLanguageCard` uses this as its value parameter, enabling smooth transitions between all three visual states in a single animation declaration. This pattern (dedicated selection enum + value-based animation) is cleaner than using multiple boolean flags.

### 53. Two-step selection with single handler function
The love languages screen implements a two-step selection (primary then secondary) with a single `selectLanguage()` function that handles 5 branches in priority order: (1) tap primary → clear both, (2) tap secondary → clear it, (3) no primary → set primary, (4) no secondary → set secondary, (5) replace secondary. This keeps the logic centralized rather than split across separate "select primary" / "select secondary" functions. The priority ordering matters — tapping the current primary always resets, regardless of whether a secondary exists.

### 54. Love language gradients are hand-tuned (like vibes)
Each love language card has a manually defined 2-color gradient that semantically matches the language's meaning (warm peach for affirmation, teal for service, amber for quality time, etc.). This follows the same pattern as vibes (note #46) — with only 5 options, curated colors are worth the effort vs. algorithmic hue rotation.

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
