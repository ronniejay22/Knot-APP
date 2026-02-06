# Implementation Plan: Project Knot

**Document Purpose:** Step-by-step instructions for AI developers to build the Knot MVP.  
**Last Updated:** February 3, 2026  
**Reference Documents:** PRD.md, techstack.md

---

## Clarifications & Design Decisions

This section captures decisions made during planning to resolve ambiguities.

### Design System
- **Framework:** SwiftUI (native, no external UI library)
- **Aesthetic:** Clean, minimalist, shadcn-inspired. AI developers will create the design system (colors, typography, spacing) as part of implementation.
- **Icons:** Lucide-Swift

### Vibe Options (8 Total)
```
quiet_luxury, street_urban, outdoorsy, vintage, minimalist, bohemian, romantic, adventurous
```

### Predefined Interest Categories (41 Options)
Users select from this list during onboarding (exactly 5 likes, 5 dislikes):
```
Travel, Cooking, Movies, Music, Reading, Sports, Gaming, Art, Photography, Fitness,
Fashion, Technology, Nature, Food, Coffee, Wine, Dancing, Theater, Concerts, Museums,
Shopping, Yoga, Hiking, Beach, Pets, Cars, DIY, Gardening, Meditation, Podcasts,
Baking, Camping, Cycling, Running, Swimming, Skiing, Surfing, Painting, Board Games, Karaoke
```

### Text Embedding Model
- **Model:** Vertex AI `text-embedding-004`
- **Vector Dimension:** 768
- **Database Column:** `vector(768)`

### Supported Holidays (US Major)
Auto-populated milestone options:
```
Valentine's Day (Feb 14), Mother's Day (2nd Sunday May), Father's Day (3rd Sunday June),
Independence Day (Jul 4), Halloween (Oct 31), Thanksgiving (4th Thursday Nov),
Christmas (Dec 25), New Year's Eve (Dec 31)
```

### Budget Tier Mapping
| Milestone Type | Budget Tier |
|----------------|-------------|
| Birthday | `major_milestone` |
| Anniversary | `major_milestone` |
| Valentine's Day | `major_milestone` |
| Christmas | `major_milestone` |
| Mother's Day / Father's Day | `minor_occasion` |
| Other Holidays | `minor_occasion` |
| Custom Milestones | User selects tier during creation |
| No specific occasion (browsing) | `just_because` |

### Love Language Weighting
Recommendations are scored with love language multipliers:
| Love Language | Effect |
|---------------|--------|
| `receiving_gifts` | Gift-type recommendations: +40% score boost |
| `quality_time` | Experience/date recommendations: +40% score boost |
| `acts_of_service` | Practical/useful gifts: +20% score boost |
| `words_of_affirmation` | Personalized/sentimental items: +20% score boost |
| `physical_touch` | Couples experiences (spa, dance class): +20% score boost |

Primary love language gets full boost; secondary gets half (e.g., +20% instead of +40%).

### Offline Mode
- **Not supported for MVP.** App requires internet connection.
- Show "No internet connection" message if offline.

### Notification Content
Notifications include specific context:
- Title: `"[Partner Name]'s [Milestone] is in [X] days"`
- Body: `"I've found 3 '[Vibe]' options based on [his/her] interest in '[Interest]'. Tap to view."`

### Refresh Exclusion Logic
When user taps "Refresh," show a bottom sheet asking why:
- "Too expensive" → Exclude higher price tier, favor lower
- "Too cheap" → Exclude lower price tier, favor higher  
- "Not their style" → Exclude that vibe category
- "Already have something similar" → Exclude that merchant/category
- "Just show me different options" → Exclude exact same items, no attribute filtering

### Partner Vaults
- **One partner per user for MVP.**
- Future: Support multiple profiles (parent, sibling, friend).

### International Support
- Support non-US users and locations.
- Use location-aware API calls (Yelp, Ticketmaster support international).
- Currency: Display in user's local currency where APIs support it.
- Holidays: US holidays auto-populated; international users can add custom milestones.

### API Failure Handling
- If external APIs fail, show user-friendly error: "Unable to find recommendations right now. Please try again."
- Log errors for monitoring.
- No cached fallbacks for MVP.

### Deep Linking
- Domain: Use Vercel backend domain (configure during deployment)
- Web fallback: Simple "Download Knot on the App Store" landing page

### Database Migrations
- Use Supabase CLI (`supabase migration new`, `supabase db push`)
- Store migration files in `/backend/supabase/migrations/`

### SDK Versions
- iOS: Latest stable `supabase-swift`
- Python: Latest stable `supabase-py`

### Hint Length
- Maximum: 500 characters
- Enforced in iOS UI (character counter) and backend API (422 if exceeded)

### Out of Scope for MVP
- Calendar integration (Google/iCal sync)
- "Weekend Outlook" Thursday push (requires calendar)
- PredictHQ API (Ticketmaster sufficient for MVP)
- Multiple partner profiles
- Offline mode

---

## Phase 0: Project Scaffolding & Environment Setup

### Step 0.1: Create iOS Project Structure
**Instruction:** Create a new Xcode project named "Knot" using SwiftUI as the interface and SwiftData for persistence. Set the minimum deployment target to iOS 17.0. Configure the project with strict concurrency checking enabled for Swift 6.

**Test:** Open the project in Xcode. Verify it builds successfully with zero warnings. Confirm SwiftData is listed in the project's frameworks. Run on simulator and confirm a blank app launches.

---

### Step 0.2: Set Up iOS Folder Architecture
**Instruction:** Create the following folder structure within the Knot iOS project:
- `/App` — App entry point and configuration
- `/Features` — Feature modules (Onboarding, Home, Recommendations, HintCapture)
- `/Core` — Shared utilities, extensions, and constants
- `/Services` — API clients, authentication, and data services
- `/Models` — SwiftData models and DTOs
- `/Components` — Reusable UI components (shadcn-style)
- `/Resources` — Assets, colors, and fonts

**Test:** Verify all folders appear in Xcode's project navigator. Create a placeholder `.swift` file in each folder to confirm the folder is recognized by the build system.

---

### Step 0.3: Install iOS Dependencies
**Instruction:** Add the following Swift Package dependencies to the Xcode project:
- Lucide Icons (Swift port) for iconography
- Any shadcn/ui SwiftUI port available, or prepare to build custom components matching shadcn aesthetic

**Test:** Import Lucide in a test view and render a single icon (e.g., `Heart`). Confirm the icon displays correctly in the preview canvas.

---

### Step 0.4: Create Backend Project Structure
**Instruction:** Create a new directory named `backend/` at the project root. Initialize a Python 3.12+ project with a `pyproject.toml` or `requirements.txt`. Create the following folder structure:
- `/app` — FastAPI application entry point
- `/app/api` — API route handlers
- `/app/core` — Configuration, settings, and constants
- `/app/models` — Pydantic models and database schemas
- `/app/services` — Business logic and external API integrations
- `/app/agents` — LangGraph agent definitions
- `/app/db` — Database connection and repository classes

**Test:** Run `python --version` and confirm Python 3.12+. Create a minimal FastAPI app with a single `/health` endpoint that returns `{"status": "ok"}`. Start the server with `uvicorn` and verify the endpoint responds.

---

### Step 0.5: Install Backend Dependencies
**Instruction:** Add the following dependencies to the backend project:
- `fastapi` and `uvicorn[standard]` — Web framework
- `langgraph` — AI orchestration
- `google-cloud-aiplatform` — Gemini 1.5 Pro access via Vertex AI
- `pydantic` and `pydantic-ai` — Data validation
- `supabase` — Database client
- `pgvector` — Vector search support
- `httpx` — Async HTTP client for external APIs
- `python-dotenv` — Environment variable management

**Test:** Create a `requirements.txt` or update `pyproject.toml`. Run `pip install` and verify all packages install without errors. Import each package in a test script to confirm availability.

---

### Step 0.6: Set Up Supabase Project
**Instruction:** Create a new Supabase project named "knot-prod" (or "knot-dev" for development). Enable the pgvector extension in the SQL editor. Note the project URL, anon key, and service role key. Store these in a `.env` file in the backend directory (add `.env` to `.gitignore`).

**Test:** Use the Supabase dashboard to run a simple query: `SELECT 1;`. Confirm it returns successfully. Test the connection from Python using the Supabase client library with the stored credentials.

---

### Step 0.7: Configure Supabase Auth with Apple Sign-In
**Instruction:** In Supabase dashboard, navigate to Authentication > Providers. Enable Apple as a provider. Configure the Apple Developer credentials (Services ID, Team ID, Key ID, and private key). Set the callback URL in your Apple Developer account to match Supabase's provided URL.

**Test:** Using the Supabase Auth UI or a test client, initiate an Apple Sign-In flow. Confirm a user record is created in the `auth.users` table upon successful authentication.

---

## Phase 1: Database Schema & Models

### Step 1.1: Create Users Table
**Instruction:** Create a `users` table in Supabase with the following columns:
- `id` (UUID, primary key, references auth.users)
- `email` (text, nullable)
- `created_at` (timestamp with timezone, default now)
- `updated_at` (timestamp with timezone, default now)

Set up Row Level Security (RLS) so users can only read/update their own row.

**Test:** Insert a test row manually. Attempt to read it with a different user's JWT — it should fail. Read with the correct user's JWT — it should succeed.

---

### Step 1.2: Create Partner Vault Table
**Instruction:** Create a `partner_vaults` table with the following columns:
- `id` (UUID, primary key, auto-generated)
- `user_id` (UUID, foreign key to users.id, unique)
- `partner_name` (text, not null)
- `relationship_tenure_months` (integer)
- `cohabitation_status` (text, enum: 'living_together', 'separate', 'long_distance')
- `location_city` (text)
- `location_state` (text)
- `location_country` (text, default 'US')
- `created_at` (timestamp with timezone)
- `updated_at` (timestamp with timezone)

Enable RLS: users can only access their own vault.

**Test:** Create a vault entry for a test user. Query the table with that user's credentials and confirm the data returns. Query with a different user and confirm empty result.

---

### Step 1.3: Create Interests Table
**Instruction:** Create a `partner_interests` table:
- `id` (UUID, primary key)
- `vault_id` (UUID, foreign key to partner_vaults.id)
- `interest_type` (text, enum: 'like', 'dislike')
- `interest_category` (text, not null, must be from predefined list)
- `created_at` (timestamp)

Valid interest categories (41 total):
```
Travel, Cooking, Movies, Music, Reading, Sports, Gaming, Art, Photography, Fitness,
Fashion, Technology, Nature, Food, Coffee, Wine, Dancing, Theater, Concerts, Museums,
Shopping, Yoga, Hiking, Beach, Pets, Cars, DIY, Gardening, Meditation, Podcasts,
Baking, Camping, Cycling, Running, Swimming, Skiing, Surfing, Painting, Board Games, Karaoke
```

Enforce in application layer:
- Each vault must have exactly 5 likes and exactly 5 dislikes
- An interest cannot be both a like AND a dislike for the same vault
- Interest must be from the predefined list

**Test:** Insert 5 likes and 5 dislikes for a test vault. Attempt to insert a 6th like via the API layer and confirm it is rejected. Attempt to insert an interest not in the predefined list and confirm rejection. Attempt to add "Hiking" as both like and dislike — confirm rejection.

---

### Step 1.4: Create Milestones Table
**Instruction:** Create a `partner_milestones` table:
- `id` (UUID, primary key)
- `vault_id` (UUID, foreign key to partner_vaults.id)
- `milestone_type` (text, enum: 'birthday', 'anniversary', 'holiday', 'custom')
- `milestone_name` (text, not null)
- `milestone_date` (date, not null) — For yearly recurrence, store with year 2000 as placeholder
- `recurrence` (text, enum: 'yearly', 'one_time')
- `budget_tier` (text, enum: 'just_because', 'minor_occasion', 'major_milestone')
- `created_at` (timestamp)

**Budget Tier Defaults (set automatically based on type):**
| Milestone Type | Default Budget Tier |
|----------------|---------------------|
| birthday | major_milestone |
| anniversary | major_milestone |
| holiday (Valentine's, Christmas) | major_milestone |
| holiday (Mother's Day, Father's Day, other) | minor_occasion |
| custom | User selects during creation |

**Test:** Insert a birthday milestone — confirm budget_tier defaults to 'major_milestone'. Insert a custom milestone — confirm user-provided budget_tier is stored. Insert a milestone with invalid type — confirm constraint rejects it.

---

### Step 1.5: Create Aesthetic Vibes Table
**Instruction:** Create a `partner_vibes` table:
- `id` (UUID, primary key)
- `vault_id` (UUID, foreign key to partner_vaults.id)
- `vibe_tag` (text, not null, CHECK constraint for valid values)

Valid vibe options (8 total):
```
quiet_luxury, street_urban, outdoorsy, vintage, minimalist, bohemian, romantic, adventurous
```

Add a CHECK constraint in PostgreSQL to enforce valid values.

**Test:** Insert 2-3 vibe tags for a vault. Query and confirm they return. Attempt to insert an invalid vibe tag (e.g., 'fancy') and confirm the database rejects it with a constraint violation.

---

### Step 1.6: Create Budget Tiers Table
**Instruction:** Create a `partner_budgets` table:
- `id` (UUID, primary key)
- `vault_id` (UUID, foreign key to partner_vaults.id)
- `occasion_type` (text, enum: 'just_because', 'minor_occasion', 'major_milestone')
- `min_amount` (integer, in cents)
- `max_amount` (integer, in cents)
- `currency` (text, default 'USD')

**Test:** Insert budget tiers for all three occasion types. Query and confirm correct amounts. Verify that `max_amount` >= `min_amount` constraint is enforced.

---

### Step 1.7: Create Love Languages Table
**Instruction:** Create a `partner_love_languages` table:
- `id` (UUID, primary key)
- `vault_id` (UUID, foreign key to partner_vaults.id)
- `language` (text, enum: 'words_of_affirmation', 'acts_of_service', 'receiving_gifts', 'quality_time', 'physical_touch')
- `priority` (integer, 1 = primary, 2 = secondary)

Constraint: Each vault has exactly one primary (1) and one secondary (2).

**Test:** Insert a primary and secondary love language. Attempt to insert a third and confirm rejection. Update primary to a different language and confirm success.

---

### Step 1.8: Create Hints Table with Vector Embedding
**Instruction:** Create a `hints` table:
- `id` (UUID, primary key)
- `vault_id` (UUID, foreign key to partner_vaults.id)
- `hint_text` (text, not null)
- `hint_embedding` (vector(768), for semantic search)
- `source` (text, enum: 'text_input', 'voice_transcription')
- `created_at` (timestamp)
- `is_used` (boolean, default false) — marks if hint was used in a recommendation

Create an index on `hint_embedding` using pgvector's ivfflat or hnsw.

**Test:** Insert a hint with a dummy embedding vector. Perform a similarity search using a test vector and confirm results return ordered by similarity.

---

### Step 1.9: Create Recommendations History Table
**Instruction:** Create a `recommendations` table:
- `id` (UUID, primary key)
- `vault_id` (UUID, foreign key)
- `milestone_id` (UUID, foreign key, nullable)
- `recommendation_type` (text, enum: 'gift', 'experience', 'date')
- `title` (text)
- `description` (text)
- `external_url` (text)
- `price_cents` (integer)
- `merchant_name` (text)
- `image_url` (text)
- `created_at` (timestamp)

**Test:** Insert a recommendation record. Query by vault_id and confirm it returns with all fields populated.

---

### Step 1.10: Create User Feedback Table
**Instruction:** Create a `recommendation_feedback` table:
- `id` (UUID, primary key)
- `recommendation_id` (UUID, foreign key)
- `user_id` (UUID, foreign key)
- `action` (text, enum: 'selected', 'refreshed', 'saved', 'shared', 'rated')
- `rating` (integer, 1-5, nullable)
- `feedback_text` (text, nullable)
- `created_at` (timestamp)

**Test:** Insert feedback for a recommendation with action 'selected'. Query feedback by recommendation_id and confirm the record exists.

---

### Step 1.11: Create Notification Queue Table
**Instruction:** Create a `notification_queue` table:
- `id` (UUID, primary key)
- `user_id` (UUID, foreign key)
- `milestone_id` (UUID, foreign key)
- `scheduled_for` (timestamp with timezone)
- `days_before` (integer, enum: 14, 7, 3)
- `status` (text, enum: 'pending', 'sent', 'failed', 'cancelled')
- `sent_at` (timestamp, nullable)
- `created_at` (timestamp)

**Test:** Insert a notification scheduled for a future date. Query pending notifications and confirm it appears. Update status to 'sent' and confirm the change persists.

---

### Step 1.12: Create SwiftData Models (iOS)
**Instruction:** Create SwiftData `@Model` classes mirroring the key database tables for offline access:
- `PartnerVaultLocal`
- `HintLocal`
- `MilestoneLocal`
- `RecommendationLocal`

Include a `syncStatus` property (enum: synced, pendingUpload, pendingDownload) on each model.

**Test:** Create a local vault entry in SwiftData. Fetch it and confirm all properties are accessible. Delete the app and reinstall — confirm data persists via SwiftData's default storage.

---

## Phase 2: Authentication Flow

### Step 2.1: Implement Apple Sign-In Button (iOS)
**Instruction:** In the `/Features/Auth` folder, create a `SignInView` that displays the standard Apple Sign-In button using `SignInWithAppleButton` from AuthenticationServices. Style the button to match the app's design system (dark mode, rounded corners).

**Test:** Run the app on a simulator with a sandbox Apple ID. Tap the button and confirm the Apple Sign-In sheet appears. Complete sign-in and confirm a credential is returned.

---

### Step 2.2: Connect Apple Sign-In to Supabase Auth (iOS)
**Instruction:** After receiving the Apple credential, extract the identity token. Send this token to Supabase Auth using `supabase.auth.signInWithIdToken(provider: .apple, idToken: token)`. Store the returned session securely in the iOS Keychain.

**Test:** Complete the sign-in flow. Check Supabase dashboard > Authentication > Users and confirm a new user appears with the Apple provider. On iOS, confirm the session token is stored and retrievable.

---

### Step 2.3: Implement Session Persistence (iOS)
**Instruction:** On app launch, check for an existing session in Keychain. If valid, automatically authenticate the user and navigate to the Home screen. If expired or missing, show the Sign-In screen.

**Test:** Sign in, force-quit the app, and relaunch. Confirm the user is still authenticated without re-signing in. Clear the Keychain, relaunch, and confirm the Sign-In screen appears.

---

### Step 2.4: Implement Sign-Out (iOS)
**Instruction:** Create a sign-out function that calls `supabase.auth.signOut()`, clears the Keychain session, and navigates the user back to the Sign-In screen.

**Test:** Sign in, then sign out. Confirm the Sign-In screen appears. Attempt to access a protected endpoint — confirm it fails with an authentication error.

---

### Step 2.5: Create Backend Auth Middleware
**Instruction:** In the FastAPI backend, create a dependency that extracts the Bearer token from the Authorization header, validates it against Supabase Auth, and returns the authenticated user's ID. Raise `HTTPException(401)` if invalid.

**Test:** Call a protected endpoint with a valid token — confirm it returns successfully. Call with an invalid token — confirm 401 response. Call with no token — confirm 401 response.

---

## Phase 3: Partner Vault (Onboarding Flow)

### Step 3.1: Design Onboarding Flow Navigation (iOS)
**Instruction:** Create an `OnboardingCoordinator` or navigation container that manages a multi-step onboarding flow. Define the step order:
1. Welcome / Value Proposition
2. Partner Basic Info (name, tenure, cohabitation, location)
3. Interests (5 likes)
4. Dislikes (5 hard avoids)
5. Milestones (birthday, anniversary)
6. Aesthetic Vibes (multi-select)
7. Budget Tiers
8. Love Languages
9. Completion / Transition to Home

**Test:** Navigate through all steps using "Next" buttons. Confirm each step is reachable. Press "Back" and confirm previous steps retain entered data.

---

### Step 3.2: Build Partner Basic Info Screen (iOS)
**Instruction:** Create `PartnerBasicInfoView` with input fields for:
- Partner's name (text field, required)
- Relationship tenure (picker: months/years)
- Cohabitation status (segmented control: Living Together, Separate, Long Distance)
- Location (city/state text fields with autocomplete if feasible)

Validate that name is not empty before allowing "Next."

**Test:** Enter a name and select options. Tap "Next" and confirm navigation proceeds. Clear the name field, tap "Next," and confirm an error message appears preventing progression.

---

### Step 3.3: Build Interests Selection Screen (iOS)
**Instruction:** Create `InterestsSelectionView` that displays all 41 predefined interest categories as tappable chips/pills in a scrollable grid. User must select exactly 5 as "likes." Display a counter showing "3 of 5 selected." Disable "Next" until exactly 5 are selected.

Visual design:
- Unselected: Light gray background, dark text
- Selected: Primary color background, white text with checkmark
- Chips should wrap to multiple rows

Interest categories to display:
```
Travel, Cooking, Movies, Music, Reading, Sports, Gaming, Art, Photography, Fitness,
Fashion, Technology, Nature, Food, Coffee, Wine, Dancing, Theater, Concerts, Museums,
Shopping, Yoga, Hiking, Beach, Pets, Cars, DIY, Gardening, Meditation, Podcasts,
Baking, Camping, Cycling, Running, Swimming, Skiing, Surfing, Painting, Board Games, Karaoke
```

**Test:** Tap 4 interests — confirm "Next" is disabled and counter shows "4 of 5". Tap a 5th — confirm "Next" enables. Tap a 6th — confirm it is rejected (show subtle shake or toast). Tap a selected interest — confirm it deselects.

---

### Step 3.4: Build Dislikes Selection Screen (iOS)
**Instruction:** Create `DislikesSelectionView` with identical chip-selection UI to the interests screen, but labeled as "Hard Avoids" or "Things they don't like." Require exactly 5 selections.

Important: Gray out / disable any interests that were already selected as "likes" in the previous step to prevent conflicts.

**Test:** Confirm interests selected as likes in Step 3.3 appear disabled/grayed out. Select 5 different interests as dislikes. Confirm "Next" enables only when exactly 5 are selected. Attempt to select a "liked" interest — confirm it cannot be selected.

---

### Step 3.5: Build Milestones Input Screen (iOS)
**Instruction:** Create `MilestonesInputView` with the following sections:

**Required:**
- Partner's Birthday (date picker, month + day only for yearly recurrence)

**Optional:**
- Anniversary (date picker)

**Holiday Quick-Add (US Major):**
Display toggleable chips for common holidays. When selected, the milestone is auto-created:
- Valentine's Day (Feb 14)
- Mother's Day (2nd Sunday of May) — show only if partner is a mother
- Father's Day (3rd Sunday of June) — show only if partner is a father
- Christmas (Dec 25)
- New Year's Eve (Dec 31)

**Custom Milestones:**
- "Add Custom" button opens a sheet with: name (text), date (picker), recurrence (yearly/one-time)

Use a clean date picker UI. For yearly milestones, only capture month and day (year is calculated dynamically).

**Test:** Enter a birthday and tap "Next" — confirm navigation proceeds. Skip anniversary — confirm it's allowed. Toggle "Valentine's Day" on — confirm it appears in the milestones list. Add a custom milestone named "First Date" — confirm it appears. Toggle a holiday off — confirm it's removed.

---

### Step 3.6: Build Aesthetic Vibes Screen (iOS)
**Instruction:** Create `VibesSelectionView` displaying the predefined vibe options as visual cards or chips (with icons from Lucide). Allow multi-select (minimum 1, maximum 4). Show selected state clearly with visual feedback.

**Test:** Tap a vibe — confirm it highlights as selected. Tap again — confirm it deselects. Select 4 vibes and attempt to select a 5th — confirm it's rejected. Proceed with 1 vibe — confirm it's allowed.

---

### Step 3.7: Build Budget Tiers Screen (iOS)
**Instruction:** Create `BudgetTiersView` with three sections:
- "Just Because" (casual dates/small gifts) — slider or range input
- "Minor Occasion" (monthly date nights) — slider or range input
- "Major Milestone" (birthday/anniversary) — slider or range input

Display dollar amounts clearly. Set sensible defaults ($20-50, $50-150, $100-500).

**Test:** Adjust sliders and confirm values update in real-time. Attempt to set max below min — confirm it's prevented or auto-corrects. Proceed and confirm values are stored.

---

### Step 3.8: Build Love Languages Screen (iOS)
**Instruction:** Create `LoveLanguagesView` displaying the 5 love languages as selectable options. Implement a two-step selection: first select Primary, then select Secondary (different from primary). Use clear visual hierarchy (larger/highlighted for primary).

**Test:** Select a primary love language — confirm it's highlighted. Select the same as secondary — confirm it's rejected. Select a different one as secondary — confirm both are stored.

---

### Step 3.9: Build Onboarding Completion Screen (iOS)
**Instruction:** Create `OnboardingCompleteView` showing a success message, a summary of the partner profile (name, vibe tags, upcoming milestone), and a "Get Started" CTA button.

**Test:** Verify all entered data displays correctly on this screen. Tap "Get Started" and confirm navigation to the Home screen.

---

### Step 3.10: Create Vault Submission API Endpoint (Backend)
**Instruction:** Create a `POST /api/v1/vault` endpoint that accepts the complete Partner Vault payload (basic info, interests, dislikes, milestones, vibes, budgets, love languages). Validate using Pydantic models. Insert into all relevant tables within a database transaction.

**Test:** Send a valid payload — confirm 201 response and data appears in all tables. Send an invalid payload (missing required field) — confirm 422 response with validation errors. Send with 4 interests instead of 5 — confirm rejection.

---

### Step 3.11: Connect iOS Onboarding to Backend API
**Instruction:** In the iOS app, after the user completes onboarding, serialize all collected data into a JSON payload matching the API schema. Send to `POST /api/v1/vault` with the auth token. Handle success (navigate to Home) and error (show alert, allow retry) responses.

**Test:** Complete onboarding on iOS. Check backend database and confirm all data is stored correctly. Simulate a network error and confirm the app shows an error message and allows retry.

---

### Step 3.12: Implement Vault Edit Functionality (iOS + Backend)
**Instruction:** Create an "Edit Profile" screen accessible from Settings that loads the existing vault data and allows modifications to any section. Create a `PUT /api/v1/vault` endpoint that updates existing records.

**Test:** Edit the partner's name and save. Refresh and confirm the change persists. Edit interests (change one) and confirm the update reflects in recommendations logic.

---

## Phase 4: Home Screen & Hint Capture

### Step 4.1: Build Home Screen Layout (iOS)
**Instruction:** Create `HomeView` with the following sections:
- Header showing partner name and days until next milestone
- Prominent Hint Capture input (text field + microphone button)
- "Upcoming" section showing the next 1-2 milestones as cards
- "Recent Hints" preview showing last 3 hints captured

**Network Connectivity:**
- Monitor network status using `NWPathMonitor`
- If offline, show a persistent banner at the top: "No internet connection. Connect to use Knot."
- Disable all interactive elements (hint capture, recommendation views) when offline
- Auto-dismiss banner and re-enable features when connection restored

**Test:** Verify all sections render. Confirm milestone countdown is accurate. Confirm hint preview updates when new hints are added. Enable airplane mode — confirm offline banner appears and inputs are disabled. Disable airplane mode — confirm banner dismisses and app becomes interactive.

---

### Step 4.2: Implement Text Hint Capture (iOS)
**Instruction:** Create a text input component at the top of the Home screen:
- Placeholder text: "What did they mention today?"
- Multi-line text field (expandable, max 3 lines visible)
- Character counter in bottom-right: "42/500"
- Counter turns red when approaching limit (450+)
- Submit button (arrow icon) appears when text is entered
- Disable submit when empty or over 500 characters

On submit:
1. Call the hint capture API
2. Show brief success animation (checkmark + haptic)
3. Clear the input field
4. Update "Recent Hints" section below

**Test:** Type a hint and submit — confirm it appears in "Recent Hints." Submit an empty string — confirm submit button is disabled. Type 501 characters — confirm counter turns red and submit is disabled. Type exactly 500 characters — confirm submit works.

---

### Step 4.3: Implement Voice Hint Capture (iOS)
**Instruction:** Add a microphone button next to the text input. When tapped, start recording using `AVAudioEngine` or `SFSpeechRecognizer`. Display a recording indicator. On stop, transcribe the audio to text using on-device Speech Recognition. Submit the transcription as a hint.

**Test:** Tap the microphone and speak a hint. Confirm transcription appears in the text field. Submit and confirm it's saved. Test with background noise and confirm reasonable transcription quality.

---

### Step 4.4: Create Hint Submission API Endpoint (Backend)
**Instruction:** Create a `POST /api/v1/hints` endpoint that accepts:
- `hint_text` (string, required, max 500 characters)
- `source` (enum: text_input, voice_transcription)

Processing steps:
1. Validate hint_text is not empty and ≤ 500 characters
2. Generate embedding using **Vertex AI `text-embedding-004`** model (768 dimensions)
3. Store hint_text, embedding, and source in the `hints` table
4. Return the created hint with ID

Use async/await for the embedding generation to avoid blocking.

**Test:** Submit a hint — confirm 201 response. Query the database and confirm both `hint_text` and `hint_embedding` (768-dimension vector) are populated. Submit without text — confirm 422 error. Submit with 501 characters — confirm 422 error with "Hint too long" message.

---

### Step 4.5: Implement Hint List View (iOS)
**Instruction:** Create `HintsListView` accessible from the Home screen that displays all captured hints in reverse chronological order. Each hint shows the text, date captured, and source icon (keyboard vs microphone). Allow swipe-to-delete.

**Test:** Navigate to the list and confirm all hints appear. Delete a hint and confirm it's removed. Add a new hint from Home and confirm it appears at the top of the list.

---

### Step 4.6: Create Hint Deletion API Endpoint (Backend)
**Instruction:** Create a `DELETE /api/v1/hints/{hint_id}` endpoint that soft-deletes or hard-deletes the specified hint. Validate that the hint belongs to the authenticated user.

**Test:** Delete a hint — confirm 204 response. Attempt to delete another user's hint — confirm 403 or 404 response. Query the deleted hint — confirm it no longer returns.

---

## Phase 5: AI Recommendation Engine (LangGraph)

### Step 5.1: Define Recommendation State Schema
**Instruction:** In the backend `/app/agents` folder, define a Pydantic model for the LangGraph state that includes:
- `vault_data` (full partner profile)
- `relevant_hints` (list of semantically similar hints)
- `milestone_context` (upcoming milestone details, if applicable)
- `budget_range` (min/max for the occasion type)
- `candidate_recommendations` (list of raw options from APIs)
- `filtered_recommendations` (list after vibe/interest filtering)
- `final_three` (the selected trio)

**Test:** Instantiate the state model with sample data. Confirm all fields are accessible and properly typed. Serialize to JSON and confirm valid output.

---

### Step 5.2: Create Hint Retrieval Node
**Instruction:** Create a LangGraph node `retrieve_relevant_hints` that:
1. Takes the milestone context or current date
2. Queries pgvector for the top 10 semantically similar hints using the milestone name as the query
3. Returns the hints to add to the state

**Test:** Seed the database with 20 hints. Run the node with a query "birthday gift ideas." Confirm it returns hints mentioning gifts, wants, or related topics. Confirm irrelevant hints are ranked lower.

---

### Step 5.3: Create External API Aggregation Node
**Instruction:** Create a LangGraph node `aggregate_external_data` that:
1. Reads the vault's interests and vibes
2. Calls relevant external APIs (stubbed initially):
   - Gift APIs: Search Shopify/Amazon for products matching interests
   - Experience APIs: Search Ticketmaster/Yelp for events/restaurants matching vibes
3. Returns raw candidate recommendations (aim for 15-20 candidates)

**Test:** Run the node with mock API responses. Confirm it returns a list of candidates with title, price, URL, and merchant. Confirm candidates are within the budget range.

---

### Step 5.4: Create Semantic Filtering Node
**Instruction:** Create a LangGraph node `filter_by_interests` that:
1. Takes candidate recommendations and the 5 interests + 5 dislikes
2. Uses Gemini 1.5 Pro to score each candidate against interests (positive) and dislikes (negative)
3. Removes any candidate that matches a dislike
4. Ranks remaining candidates by interest alignment score
5. Returns the top 9 candidates

**Test:** Provide candidates including one that matches a dislike (e.g., "golf equipment" when "golf" is a dislike). Confirm that candidate is removed. Confirm candidates matching interests are ranked higher.

---

### Step 5.5: Create Vibe and Love Language Matching Node
**Instruction:** Create a LangGraph node `match_vibes_and_love_languages` that:

**Vibe Matching:**
1. Takes the filtered candidates and the vault's vibe tags (up to 4 from 8 options)
2. Uses Gemini 1.5 Pro to classify each candidate's "vibe"
3. Score boost for vibe match: +30% for each matching vibe tag

**Love Language Weighting:**
Apply score multipliers based on partner's love languages:

| Love Language | Recommendation Type | Primary Boost | Secondary Boost |
|---------------|---------------------|---------------|-----------------|
| `receiving_gifts` | Gift-type items | +40% | +20% |
| `quality_time` | Experiences/dates | +40% | +20% |
| `acts_of_service` | Practical/useful gifts | +20% | +10% |
| `words_of_affirmation` | Personalized/sentimental items | +20% | +10% |
| `physical_touch` | Couples experiences (spa, dance class) | +20% | +10% |

**Final Scoring:**
```
final_score = base_interest_score × (1 + vibe_boost) × (1 + love_language_boost)
```

Return candidates re-ranked by final_score.

**Test:** 
1. Set vibes to "quiet_luxury" and "minimalist." Confirm loud/flashy candidates are ranked lower.
2. Set primary love language to "receiving_gifts." Confirm gift-type recommendations rank higher than experiences.
3. Set primary to "quality_time," secondary to "receiving_gifts." Confirm experiences rank highest, gifts rank second.

---

### Step 5.6: Create Diversity Selection Node
**Instruction:** Create a LangGraph node `select_diverse_three` that:
1. Takes the top 9 ranked candidates
2. Selects 3 that maximize diversity across: price tier (low/mid/high), type (gift vs experience), and merchant
3. Returns exactly 3 recommendations

**Test:** Provide 9 candidates with varying prices and types. Confirm the final 3 span different price points. Confirm at least one gift and one experience are included (if available). Confirm no two recommendations are from the same merchant.

---

### Step 5.7: Create Availability Verification Node
**Instruction:** Create a LangGraph node `verify_availability` that:
1. Takes the 3 selected recommendations
2. For each, makes a HEAD or GET request to the external URL
3. Confirms the URL returns 200 and the item/event is still available
4. If unavailable, replaces with the next-best candidate from the pool
5. Returns 3 verified recommendations

**Test:** Provide 3 recommendations, one with an invalid URL. Confirm the invalid one is replaced. Confirm all 3 final recommendations have verified URLs.

---

### Step 5.8: Compose Full LangGraph Pipeline
**Instruction:** Create the main LangGraph `RecommendationGraph` that chains the nodes:
1. `retrieve_relevant_hints` — Fetch semantically similar hints from pgvector
2. `aggregate_external_data` — Call external APIs (Yelp, Ticketmaster, Amazon, etc.)
3. `filter_by_interests` — Remove candidates matching dislikes, boost matches
4. `match_vibes_and_love_languages` — Apply vibe and love language scoring
5. `select_diverse_three` — Pick 3 diverse recommendations
6. `verify_availability` — Confirm URLs are valid, replace if not

Define edges and conditional logic:
- If `aggregate_external_data` returns 0 candidates → return error state "No recommendations found for this location"
- If `filter_by_interests` filters all candidates → return error state "Try adjusting your preferences"
- If `verify_availability` cannot find 3 valid URLs after 3 retries → return partial results with warning

**Test:** Run the full graph with a complete vault and milestone. Confirm it returns exactly 3 recommendations within 3 seconds. Confirm all recommendations match interests, vibes, and love language preferences.

---

### Step 5.9: Create Recommendations API Endpoint (Backend)
**Instruction:** Create a `POST /api/v1/recommendations/generate` endpoint that:
1. Accepts `milestone_id` (optional) and `occasion_type`
2. Loads the user's vault data
3. Runs the LangGraph pipeline
4. Stores the 3 recommendations in the database
5. Returns the recommendations as JSON

**Test:** Call the endpoint with a valid milestone_id. Confirm 3 recommendations return with all required fields (title, description, price, URL, image). Confirm response time is under 3 seconds.

---

### Step 5.10: Implement Refresh (Re-roll) Logic
**Instruction:** Create a `POST /api/v1/recommendations/refresh` endpoint that accepts:
- `rejected_recommendation_ids` (array of UUIDs)
- `rejection_reason` (enum, required)

Valid rejection reasons and their effects:
| Reason | Exclusion Logic |
|--------|-----------------|
| `too_expensive` | Exclude recommendations at or above the rejected price tier; favor lower prices |
| `too_cheap` | Exclude recommendations at or below the rejected price tier; favor higher prices |
| `not_their_style` | Exclude the vibe category of rejected recommendations |
| `already_have_similar` | Exclude the same merchant and product category |
| `show_different` | Exclude only the exact same items; no attribute filtering |

Processing:
1. Store feedback with action='refreshed' and the reason
2. Load the original candidate pool (or re-aggregate if not cached)
3. Apply exclusion filters based on rejection reason
4. Re-run diversity selection and availability verification
5. Return 3 new recommendations

**Test:** Generate initial recommendations. Call refresh with reason `too_expensive`. Confirm new recommendations are at a lower price point. Call refresh with reason `not_their_style` on a "romantic" vibe recommendation. Confirm new recommendations exclude "romantic" vibe.

---

## Phase 6: Choice-of-Three UI (iOS)

### Step 6.1: Build Recommendation Card Component (iOS)
**Instruction:** Create a `RecommendationCard` component displaying:
- Hero image (async loaded)
- Title (2 lines max)
- Short description (3 lines max)
- Price badge
- Merchant logo/name
- "Select" button

Style using shadcn-inspired design: rounded corners, subtle shadows, clean typography.

**Test:** Render a card with sample data. Confirm image loads. Confirm text truncates properly. Confirm button is tappable.

---

### Step 6.2: Build Choice-of-Three Horizontal Scroll (iOS)
**Instruction:** Create `RecommendationsView` that displays exactly 3 `RecommendationCard` components in a horizontal scroll (paging enabled). Add a "Refresh" button below the cards. Show a loading state while recommendations are being fetched.

**Test:** Fetch recommendations and confirm 3 cards appear. Swipe horizontally and confirm paging between cards. Tap "Refresh" and confirm new cards load.

---

### Step 6.3: Implement Card Selection Flow (iOS)
**Instruction:** When the user taps "Select" on a card:
1. Show a confirmation bottom sheet with full details
2. If confirmed, record feedback (action='selected')
3. Deep-link to the external merchant URL using `UIApplication.shared.open()`

**Test:** Select a card and confirm the confirmation sheet appears. Confirm "Open in [Merchant]" opens Safari/app with the correct URL. Confirm feedback is recorded in the backend.

---

### Step 6.4: Implement Refresh Flow with Reason Selection (iOS)
**Instruction:** When the user taps "Refresh":

1. Show a bottom sheet asking "Why are you refreshing?" with options:
   - "Too expensive" 
   - "Too cheap"
   - "Not their style"
   - "Already have something similar"
   - "Just show me different options"

2. After user selects a reason:
   - Dismiss the sheet
   - Animate the current cards sliding out (fade + scale down)
   - Show a loading spinner with text "Finding better options..."
   - Call refresh API with rejected IDs and selected reason
   - Animate new cards sliding in (fade + scale up)

3. Provide haptic feedback on both sheet dismissal and new cards appearing.

**Test:** Tap refresh — confirm bottom sheet appears with all 5 options. Select "Too expensive" — confirm sheet dismisses, animation plays, and new recommendations load. Verify new recommendations are actually cheaper. Select "Just show me different options" — confirm new cards are simply different items without price filtering.

---

### Step 6.5: Implement Manual Vibe Override (iOS)
**Instruction:** Add an "Adjust Vibe" button on the recommendations screen that opens a sheet allowing the user to temporarily select different vibes for this session only. When saved, trigger a refresh with the overridden vibes.

**Test:** Open the override sheet and select a different vibe. Confirm refresh returns recommendations matching the new vibe. Navigate away and return — confirm the override is cleared and default vibes are used.

---

### Step 6.6: Implement Save/Share Actions (iOS)
**Instruction:** Add "Save" and "Share" buttons to each recommendation card:
- Save: Stores the recommendation locally for later reference
- Share: Opens the system share sheet with the recommendation URL and a custom message

Record feedback for each action.

**Test:** Tap "Save" and confirm the recommendation appears in a "Saved" section. Tap "Share" and confirm the share sheet opens with the correct URL. Check backend and confirm feedback is recorded.

---

## Phase 7: Proactive Notifications

### Step 7.1: Set Up Upstash Scheduler (Backend)
**Instruction:** Create an Upstash account and set up a QStash queue. Configure webhook URL pointing to your backend endpoint `POST /api/v1/notifications/process`. Store Upstash credentials in environment variables.

**Test:** Manually publish a test message to QStash. Confirm your webhook receives the payload. Confirm the request includes proper authentication headers.

---

### Step 7.2: Create Notification Scheduling Logic (Backend)
**Instruction:** Create a function `schedule_milestone_notifications(milestone_id)` that:
1. Calculates dates for 14, 7, and 3 days before the milestone
2. Creates entries in the `notification_queue` table for each
3. Schedules corresponding jobs in Upstash QStash

Call this function when a milestone is created or updated.

**Test:** Create a milestone 20 days in the future. Confirm 3 notification_queue entries are created with correct `scheduled_for` dates. Confirm QStash shows 3 scheduled jobs.

---

### Step 7.3: Create Notification Processing Endpoint (Backend)
**Instruction:** Create `POST /api/v1/notifications/process` that:
1. Validates the request is from Upstash (check signature)
2. Reads the notification_queue entry
3. Generates recommendations for the milestone
4. Sends a push notification to the user's device via APNs
5. Updates the queue entry status to 'sent'

**Test:** Trigger the endpoint with a valid notification ID. Confirm recommendations are generated. Confirm push notification is received on the test device. Confirm queue status updates to 'sent'.

---

### Step 7.4: Implement Push Notification Registration (iOS)
**Instruction:** On app launch (after authentication), request push notification permissions. If granted, register for remote notifications and send the device token to the backend via `POST /api/v1/users/device-token`.

**Test:** Launch app and grant notification permission. Check backend database for the stored device token. Deny permission on another device and confirm graceful handling.

---

### Step 7.5: Create Push Notification Service (Backend)
**Instruction:** Create a service that sends APNs push notifications using the stored device token. Include:
- Title: "[Partner Name]'s [Milestone] is in [X] days"
- Body: "I've found 3 [Vibe] options based on their interests. Tap to see them."
- Category: Allow "View" and "Snooze" actions

**Test:** Send a test push notification to a registered device. Confirm it appears with correct title and body. Tap the notification and confirm the app opens to the recommendations screen.

---

### Step 7.6: Implement DND Respect Logic (Backend + iOS)
**Instruction:** Before sending a notification:
1. Check if current time is within "quiet hours" (configurable, default 10pm-8am user local time)
2. If in quiet hours, reschedule the notification for 8am

On iOS, use `UNUserNotificationCenter` to check notification settings and respect system DND.

**Test:** Schedule a notification for 11pm. Confirm it's rescheduled to 8am next day. Enable system DND on device and confirm notification is queued, not delivered.

---

### Step 7.7: Create Notification History View (iOS)
**Instruction:** Create a `NotificationsView` accessible from the profile/settings area showing:
- Past notifications with date and milestone
- Status (viewed, acted upon, dismissed)
- Option to access the recommendations from that notification

**Test:** Trigger several notifications over multiple days. View the history and confirm all appear. Tap a past notification and confirm the associated recommendations load.

---

## Phase 8: External API Integrations

### Step 8.1: Implement Yelp Fusion API Integration
**Instruction:** Create a service `YelpService` in `/app/services/integrations/` that:
1. Searches businesses by location (city, state, country), category, and price range
2. Supports international locations (Yelp Fusion supports 30+ countries)
3. Returns normalized results with name, rating, price, address, URL, image, and currency
4. Handles rate limiting (5000 calls/day) with exponential backoff
5. Handles errors gracefully (timeout, invalid location, no results)

Store API key in environment variables.

**Test:** Search for restaurants in "San Francisco" with category "romantic" — confirm results return. Search for restaurants in "London, UK" — confirm international results return with GBP prices. Test with invalid location "ZZZZZ" — confirm graceful error handling (empty results, no crash).

---

### Step 8.2: Implement Ticketmaster API Integration
**Instruction:** Create a service `TicketmasterService` that:
1. Searches events by location (supports international via country code), date range, and genre
2. Maps interest categories to Ticketmaster genres:
   - "Concerts" → Music
   - "Theater" → Arts & Theatre
   - "Sports" → Sports
3. Returns normalized results with name, date, venue, price range (min/max), URL, image, and currency
4. Filters to only include events with available tickets (`onsaleStatus: "onsale"`)
5. Handles rate limiting (5 calls/second)

**Test:** Search for concerts in "Los Angeles" in next 30 days — confirm results return. Search for events in "London, GB" — confirm international results with GBP prices. Confirm only events with available tickets are included (no "offsale" events).

---

### Step 8.3: Implement Amazon Associates API Integration
**Instruction:** Create a service `AmazonService` that:
1. Searches products by keyword and category
2. Returns normalized results with title, price, URL (with affiliate tag), and image
3. Filters by price range

**Test:** Search for "gardening gifts" under $50. Confirm results return within price range. Confirm URLs include the affiliate tag.

---

### Step 8.4: Implement Shopify Storefront API Integration
**Instruction:** Create a service `ShopifyService` that:
1. Connects to partner Shopify stores (configurable list)
2. Searches products by keyword and collection
3. Returns normalized results with title, price, URL, and image

**Test:** Search for products matching "jewelry" on a test Shopify store. Confirm results return with buy URLs. Confirm prices are in the expected currency.

---

### Step 8.5: Implement OpenTable/Resy Integration
**Instruction:** Create a service `ReservationService` that:
1. Searches restaurants with available reservations
2. Filters by date, time, party size, and cuisine
3. Returns results with availability slots and direct booking URL

**Test:** Search for available reservations for 2 people on a Saturday evening. Confirm results include specific time slots. Confirm booking URLs are valid.

---

### Step 8.6: Implement Firecrawl for Curated Content
**Instruction:** Create a service `CuratedContentService` using Firecrawl that:
1. Crawls predefined city guide URLs (configurable list)
2. Extracts "best of" lists (best new restaurants, trending experiences)
3. Normalizes extracted data to match recommendation schema
4. Caches results to avoid excessive crawling (refresh daily)

**Test:** Crawl a test city guide page. Confirm extracted venues match the source content. Confirm cached results are used on subsequent calls within 24 hours.

---

### Step 8.7: Create Aggregator Service
**Instruction:** Create an `AggregatorService` that:
1. Calls all relevant integration services in parallel using `asyncio.gather()`
2. Normalizes all results to a common `CandidateRecommendation` schema:
   ```
   {
     "id": UUID,
     "source": "yelp" | "ticketmaster" | "amazon" | "shopify" | "firecrawl",
     "type": "gift" | "experience" | "date",
     "title": string,
     "description": string,
     "price_cents": integer,
     "currency": string,
     "external_url": string,
     "image_url": string,
     "merchant_name": string,
     "location": { "city": string, "country": string } | null,
     "metadata": { ... source-specific data }
   }
   ```
3. Deduplicates results (same venue from Yelp and OpenTable — prefer OpenTable for reservation URL)
4. Handles partial failures gracefully:
   - If 1-2 APIs fail, continue with remaining results
   - If all APIs fail, raise `AggregationError` with message "Unable to find recommendations right now"
   - Log all failures for monitoring
5. Returns the unified candidate list

**Test:** Call the aggregator with interests "Italian food, live music." Confirm results include both restaurants and concerts. Confirm no duplicates appear. Measure and confirm total aggregation time is under 2 seconds. Simulate Yelp API failure — confirm other results still return. Simulate all APIs failing — confirm appropriate error is raised.

---

## Phase 9: Deep Linking & Handoff

### Step 9.1: Configure Universal Links (iOS)
**Instruction:** Set up Universal Links for the Knot app:
1. Create an `apple-app-site-association` file on your backend domain
2. Add associated domains capability in Xcode
3. Handle incoming URLs in `SceneDelegate` or `App` struct

**Test:** Create a link to `https://yourapp.com/recommendation/123`. Tap it on a device with the app installed. Confirm the app opens to that recommendation. Tap on a device without the app and confirm web fallback works.

---

### Step 9.2: Implement Recommendation Deep Link Handler (iOS)
**Instruction:** When the app opens via a deep link to a recommendation:
1. Parse the recommendation ID from the URL
2. Fetch the recommendation details from the backend
3. Navigate directly to the recommendation detail view

**Test:** Open a recommendation deep link. Confirm the app navigates directly to that recommendation without showing the home screen first. Test with an invalid ID and confirm graceful error handling.

---

### Step 9.3: Implement External Merchant Handoff (iOS)
**Instruction:** When the user selects a recommendation and confirms:
1. Open the merchant URL using `UIApplication.shared.open(url, options: [.universalLinksOnly: false])`
2. If the merchant has an app installed, prefer opening in-app
3. Log the handoff event for analytics

**Test:** Select a recommendation with an Amazon URL. Confirm Amazon app opens if installed, otherwise Safari. Confirm the correct product page loads. Check analytics log for the handoff event.

---

### Step 9.4: Implement Return-to-App Flow (iOS)
**Instruction:** After the user completes a purchase externally and returns to Knot:
1. Show a prompt asking "Did you complete your purchase?"
2. If yes, mark the recommendation as "purchased" and prompt for feedback
3. If no, offer to save for later

**Test:** Select a recommendation and open the merchant. Return to the app. Confirm the prompt appears. Select "Yes" and confirm the recommendation is marked as purchased.

---

## Phase 10: Feedback & Learning Loop

### Step 10.1: Implement Post-Selection Rating Prompt (iOS)
**Instruction:** After a recommendation is marked as purchased (or 3 days after selection), show a rating prompt:
1. "How did [Partner Name] like the [gift/experience]?"
2. 5-star rating selector
3. Optional text feedback field

Store feedback via the backend API.

**Test:** Mark a recommendation as purchased. Wait for the prompt (or trigger manually). Submit a 5-star rating. Confirm feedback is stored in the database.

---

### Step 10.2: Create Feedback Analysis Job (Backend)
**Instruction:** Create a scheduled job that:
1. Analyzes feedback patterns (which vibes get high ratings, which interests lead to refreshes)
2. Updates a `user_preferences_weights` table with learned weights
3. Runs weekly

**Test:** Seed the database with feedback data (high ratings for "romantic" vibe, low for "adventurous"). Run the job. Confirm weights are updated. Confirm subsequent recommendations favor "romantic."

---

### Step 10.3: Integrate Learned Weights into Recommendation Graph
**Instruction:** Update the `match_vibes` and `filter_by_interests` nodes to:
1. Load the user's learned preference weights
2. Apply weights as multipliers to candidate scores
3. Gradually personalize results over time

**Test:** Set up a user with strong preference weights for "receiving_gifts" love language. Generate recommendations. Confirm gift-type recommendations are ranked higher than experiences.

---

### Step 10.4: Implement App Store Review Prompt (iOS)
**Instruction:** After a user rates a recommendation 5 stars:
1. Wait 2 seconds
2. Prompt: "Would you like to share your experience with others?"
3. If yes, trigger `SKStoreReviewController.requestReview()`

Limit to once per 90 days per Apple guidelines.

**Test:** Give a 5-star rating. Confirm the prompt appears. Tap yes and confirm the App Store review sheet appears. Give another 5-star rating immediately and confirm the prompt does not appear again.

---

## Phase 11: Settings & Profile Management

### Step 11.1: Build Settings Screen (iOS)
**Instruction:** Create `SettingsView` with sections:
- Account (email, sign out, delete account)
- Partner Profile (edit vault)
- Notifications (toggle, quiet hours)
- Privacy (data export, clear hints)
- About (version, terms, privacy policy)

**Test:** Navigate to Settings and confirm all sections render. Tap each option and confirm it navigates to the correct sub-screen or triggers the correct action.

---

### Step 11.2: Implement Account Deletion (iOS + Backend)
**Instruction:** Create a "Delete Account" flow that:
1. Shows a confirmation dialog explaining data will be permanently deleted
2. Requires re-authentication (Apple Sign-In)
3. Calls `DELETE /api/v1/users/me` endpoint
4. Clears local data and signs out

Backend: Delete all user data from all tables, revoke Supabase auth.

**Test:** Initiate account deletion. Confirm warning appears. Confirm re-authentication is required. Complete deletion and confirm user cannot sign back in with the same account.

---

### Step 11.3: Implement Data Export (Backend)
**Instruction:** Create a `GET /api/v1/users/me/export` endpoint that:
1. Compiles all user data (vault, hints, recommendations, feedback)
2. Formats as JSON
3. Returns as a downloadable file

**Test:** Request export. Confirm JSON file downloads. Open the file and confirm all user data is present and readable.

---

### Step 11.4: Implement Notification Preferences (iOS + Backend)
**Instruction:** Create a notification preferences screen allowing users to:
- Toggle notifications on/off
- Set quiet hours (start time, end time)
- Choose which milestones trigger notifications

Store preferences in the backend and apply to notification scheduling logic.

**Test:** Disable notifications. Confirm no notifications are sent. Enable and set quiet hours to 9pm-9am. Schedule a notification for 10pm and confirm it's rescheduled to 9am.

---

## Phase 12: Testing & Quality Assurance

### Step 12.1: Write Unit Tests for LangGraph Nodes
**Instruction:** Create unit tests for each LangGraph node:
- Mock external API responses
- Test edge cases (no candidates found, all candidates filtered out)
- Verify state transformations

Target: 90% code coverage for `/app/agents/` folder.

**Test:** Run pytest with coverage. Confirm all tests pass. Confirm coverage is at or above 90%.

---

### Step 12.2: Write Integration Tests for API Endpoints
**Instruction:** Create integration tests for all API endpoints:
- Test authentication (valid/invalid/missing tokens)
- Test happy paths and error paths
- Test database state changes

Use a test database (separate from production).

**Test:** Run the integration test suite. Confirm all tests pass. Confirm test database is properly isolated.

---

### Step 12.3: Write UI Tests for Critical Flows (iOS)
**Instruction:** Create XCUITests for:
- Complete onboarding flow
- Hint capture (text and voice)
- Recommendation selection and refresh
- Sign out and sign in

**Test:** Run the UI test suite on simulator. Confirm all tests pass. Confirm no flaky tests (run 3 times consecutively).

---

### Step 12.4: Perform End-to-End Testing
**Instruction:** Manually test the complete user journey:
1. Sign up with Apple
2. Complete onboarding with real data
3. Capture 5 hints over 2 days
4. Wait for a milestone notification (use a milestone 3 days away)
5. View and select a recommendation
6. Complete the external purchase
7. Return and rate the experience

Document any bugs or UX issues.

**Test:** Complete the E2E flow without errors. Confirm all data persists correctly. Confirm the experience is smooth and intuitive.

---

### Step 12.5: Performance Testing
**Instruction:** Test performance requirements:
- Recommendation generation must complete in < 3 seconds
- API endpoints must respond in < 500ms (excluding recommendation generation)
- App launch to interactive must be < 2 seconds

Use profiling tools (Xcode Instruments, backend APM).

**Test:** Run load tests with 100 concurrent users. Confirm response times meet requirements. Identify and resolve any bottlenecks.

---

## Phase 13: Deployment & Launch

### Step 13.1: Set Up Production Environment
**Instruction:** Create production instances:
- Supabase project (production tier)
- Vercel project (production deployment)
- Upstash queue (production tier)
- Configure environment variables for all services

**Test:** Deploy backend to production Vercel. Hit the `/health` endpoint and confirm 200 response. Verify environment variables are correctly loaded.

---

### Step 13.2: Configure CI/CD Pipeline
**Instruction:** Set up GitHub Actions (or similar) to:
- Run tests on every PR
- Deploy to staging on merge to `develop`
- Deploy to production on merge to `main`
- Run database migrations automatically

**Test:** Push a commit to `develop`. Confirm tests run and staging deploys. Merge to `main`. Confirm production deploys successfully.

---

### Step 13.3: Submit to App Store
**Instruction:** Prepare App Store submission:
- Screenshots for all required device sizes
- App description highlighting key features
- Privacy policy URL
- App Review notes explaining the Apple Sign-In and notification usage

Submit for review.

**Test:** Confirm submission is accepted. Respond to any reviewer questions promptly. Confirm app is approved and available for download.

---

### Step 13.4: Post-Launch Monitoring
**Instruction:** Set up monitoring and alerting:
- Crash reporting (Sentry or Firebase Crashlytics)
- API monitoring (uptime, error rates)
- User analytics (Mixpanel or Amplitude)

**Test:** Trigger a test crash in development. Confirm it appears in the crash reporting dashboard. Create a test event and confirm it appears in analytics.

---

## Appendix A: Environment Variables

Document all required environment variables:

```
# Supabase
SUPABASE_URL=
SUPABASE_ANON_KEY=
SUPABASE_SERVICE_ROLE_KEY=

# Vertex AI
GOOGLE_CLOUD_PROJECT=
GOOGLE_APPLICATION_CREDENTIALS=

# External APIs
YELP_API_KEY=
TICKETMASTER_API_KEY=
AMAZON_ASSOCIATE_TAG=
AMAZON_ACCESS_KEY=
AMAZON_SECRET_KEY=
SHOPIFY_STOREFRONT_TOKEN=
FIRECRAWL_API_KEY=

# Upstash
UPSTASH_QSTASH_TOKEN=
UPSTASH_QSTASH_URL=

# APNs
APNS_KEY_ID=
APNS_TEAM_ID=
APNS_AUTH_KEY_PATH=
```

---

## Appendix B: API Endpoint Summary

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/health` | Health check |
| POST | `/api/v1/vault` | Create partner vault |
| PUT | `/api/v1/vault` | Update partner vault |
| GET | `/api/v1/vault` | Get partner vault |
| POST | `/api/v1/hints` | Create hint |
| GET | `/api/v1/hints` | List hints |
| DELETE | `/api/v1/hints/{id}` | Delete hint |
| POST | `/api/v1/recommendations/generate` | Generate recommendations |
| POST | `/api/v1/recommendations/refresh` | Refresh recommendations |
| POST | `/api/v1/recommendations/{id}/feedback` | Submit feedback |
| POST | `/api/v1/users/device-token` | Register push token |
| GET | `/api/v1/users/me/export` | Export user data |
| DELETE | `/api/v1/users/me` | Delete account |
| POST | `/api/v1/notifications/process` | Process notification (webhook) |

---

*End of Implementation Plan*
